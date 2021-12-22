//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2; 

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./libraries/FixedPoint.sol";
import "./libraries/FullMath.sol";
import "./libraries/Babylonian.sol";
import "./libraries/BitMath.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/UniswapV2OracleLibrary.sol";

/// @title Balancer AMM reward calculation and claiming contract
contract ShyftBALV2LPStaking is Ownable {
  using FixedPoint for *;
  using SafeERC20 for IERC20;
  using SafeMath  for uint256;

  /// @dev Seconds for a week
  uint256 private constant SECONDS_A_WEEK = 1 weeks;
  /// @dev Period of updating cumulative price of a specific token // 10 minutes
  uint256 private constant PERIOD = 1 minutes; 
  /// @dev Start date - Unix timestamp - ex: 1625596114
  uint256 public startDate;
  /// @dev Shyft token address
  IERC20 public shyftToken;

  /// @dev Base token to calculate the price of a token
  address public baseToken;
  /// @dev A proxy to get the price of base token
  address public baseTokenProxy;

  /// @dev Uniswap V2 Factory address
  address private constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
  /// @dev Uniswap V2 Router02 address
  address private constant UNISWAP_ROUTER  = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

  /// @dev A struct for cumulative price observation
  struct Observation {
    uint32 timestampLast;
    uint256 price0CumulativeLast;
    uint256 price1CumulativeLast;
    uint256 price0;
    uint256 price1;
  }
  /// @dev A struct for multiple tokens' balances struct
  struct BalancePair {
    uint256 balanceA;
    uint256 balanceB;
  }
  /// @dev A struct for pool data
  struct PoolData {
    IERC20 lpToken;
    uint256 numShyftPerWeek;
    uint256 lastClaimDate;
    uint256 shyftPerStock;
  }
  /// @dev A struct for user data
  struct UserData {
    uint256 lpAmount;
    uint256 preReward;
  }
  
  /// @dev An array of pool data
  PoolData[] public poolData;
  /// @dev A mapping of user data of pool id and user address to user data
  mapping (uint256 => mapping (address => UserData)) public userData;
  /// @dev A mapping of observation of token to observation data
  mapping (address => Observation) public pairObservation;

  /// @dev An event for lp token deposited
  event Deposited(
    address indexed _from,
    uint256 indexed _id,
    uint256 _amount
  );

  /// @dev An event for lp token withdrew
  event Withdrew(
    address indexed _to,
    uint256 indexed _id,
    uint256 _amount
  );

  /// @param _shyftToken Shyft token address
  /// @param _baseToken Base token address to get price of a token
  /// @param _baseTokenProxy A proxy to get price of the base token
  /// @param _startDate Contract start date
  /// @dev Constructor function

  constructor(
    IERC20 _shyftToken,
    address _baseToken,
    address _baseTokenProxy,
    uint256 _startDate
  ) {
    shyftToken     = _shyftToken;
    baseToken      = _baseToken;
    baseTokenProxy = _baseTokenProxy;
    startDate      = _startDate;

    // prepair to transfer base token to a pool by uniswap router to add liquidity
    IERC20(baseToken).approve(UNISWAP_ROUTER, type(uint256).max);
  }
  
  /// @param _balLPToken Balancer pool address
  /// @param _numShyftPerWeek Reward SHFT number for a week
  /// @dev Add a new Balancer Pool

  function addPool(
    IERC20 _balLPToken, 
    uint256 _numShyftPerWeek
  ) public onlyOwner {
    uint256 timestamp = block.timestamp;
    uint256 lastRewardDate = timestamp > startDate ? timestamp : startDate;
    poolData.push(PoolData({
      lpToken: _balLPToken,
      // rewardToken: _rewardToken,
      numShyftPerWeek: _numShyftPerWeek,
      lastClaimDate: lastRewardDate,
      shyftPerStock: 0 
    }));
  }
  
  /// @param _balPoolId Balancer pool's id
  /// @param _numShyftPerWeek Reward SHFT number for a week
  /// @dev Change numShyftPerWeek for a sepcific Balancer Pool

  function changeNumShyftPerWeek(
    uint256 _balPoolId,
    uint256 _numShyftPerWeek
  ) public onlyOwner {
    PoolData storage pool = poolData[_balPoolId];
    pool.numShyftPerWeek = _numShyftPerWeek;
  }

  /// @param _rewardToken Reward token address to fund
  /// @param _amount Funding amount of the token
  /// @dev Fund reward token

  function preFund(
    IERC20 _rewardToken, 
    uint256 _amount
  ) public {
    require(msg.sender != address(0), "ShyftBALV2LPStaking: REQUIRE_VALID_ADDRESS");
    require(_amount > 0, "ShyftBALV2LPStaking: REQUIRE_POSITIVE_VALUE");
    require(_rewardToken.balanceOf(msg.sender) >= _amount, "ShyftBALV2LPStaking: INSUFFICIENT_REWARD_TOKEN_AMOUNT");
    _rewardToken.transferFrom(msg.sender, address(this), _amount);

    // prepair to transfer token to a pool by uniswap router to add liquidity
    _rewardToken.approve(UNISWAP_ROUTER, type(uint256).max);
  }
  
  /// @param _balPoolId Balancer pool's id
  /// @dev Get pending reward for a user and a specific Balancer pool

  function pendingReward(
    uint256 _balPoolId
  ) public view returns (uint256 pendingAmount) {
    PoolData storage pool = poolData[_balPoolId];
    UserData storage user = userData[_balPoolId][msg.sender];

    uint256 timestamp = block.timestamp;

    uint256 shyftPerStock = pool.shyftPerStock;
    uint256 totalPoolLP = pool.lpToken.balanceOf(address(this));

    if (user.lpAmount > 0 && totalPoolLP > 0 && timestamp > pool.lastClaimDate) {
      uint256 diffDate = getDiffDate(timestamp, pool.lastClaimDate);
      uint256 totalReward = diffDate.mul(1e18).div(SECONDS_A_WEEK).mul(pool.numShyftPerWeek);
      shyftPerStock = shyftPerStock.add(totalReward.div(totalPoolLP));
    }

    pendingAmount = user.lpAmount.mul(shyftPerStock).div(1e18).sub(user.preReward);
  }
  
  /// @param _balPoolId Balancer pool's id
  /// @param _tokenA Token A address to claim the reward
  /// @param _tokenB Token B address to claim the reward
  /// @dev Claim reward for a user

  function claim(
    uint256 _balPoolId,
    address _tokenA,
    address _tokenB
  ) external returns (uint256, uint256) {
    UserData storage user = userData[_balPoolId][msg.sender];

    readyPool(_balPoolId);

    if (user.lpAmount > 0) {
      (uint256 amountA, uint256 amountB) = getTwoTokensReward(_balPoolId, _tokenA, _tokenB);
      
      safeRewardTransfer(IERC20(_tokenA), msg.sender, amountA);
      safeRewardTransfer(IERC20(_tokenB), msg.sender, amountB);

      // store current claiming amount as preReward to subtract later
      uint256 pendingAmount = pendingReward(_balPoolId);
      uint256 preReward = user.preReward;
      user.preReward = preReward.add(pendingAmount);

      return (amountA, amountB);
    }
    return (0, 0);
  }

  /// @param _balPoolId Balancer pool's id
  /// @param _amount Deposit amount for a specific Balancer pool
  /// @dev Deposit Balancer LP token

  function deposit(
    uint256 _balPoolId, 
    uint256 _amount
  ) public {
    PoolData storage pool = poolData[_balPoolId];
    UserData storage user = userData[_balPoolId][msg.sender];
    
    readyPool(_balPoolId);

    if (user.lpAmount > 0) {
      uint256 claimAmount = user.lpAmount.mul(pool.shyftPerStock).div(1e18).sub(user.preReward);
      safeRewardTransfer(shyftToken, msg.sender, claimAmount);
    }
    
    user.lpAmount = user.lpAmount.add(_amount);
    user.preReward = user.lpAmount.mul(pool.shyftPerStock).div(1e18);
    pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

    emit Deposited(msg.sender, _balPoolId, _amount);
  }

  /// @param _balPoolId Balancer pool's id
  /// @param _amount Withdraw amount
  /// @dev Withdraw Balancer LP token

  function withdraw(
    uint256 _balPoolId,
    uint256 _amount
  ) public {
    PoolData storage pool = poolData[_balPoolId];
    UserData storage user = userData[_balPoolId][msg.sender];

    require(user.lpAmount >= _amount, 'ShyftBALV2LPStaking: INSUFFICIENT_AMOUNT');

    readyPool(_balPoolId);
    
    uint256 claimAmount = user.lpAmount.mul(pool.shyftPerStock).div(1e18).sub(user.preReward);
    safeRewardTransfer(shyftToken, msg.sender, claimAmount);

    user.lpAmount = user.lpAmount.sub(_amount);
    user.preReward = user.lpAmount.mul(pool.shyftPerStock).div(1e18);
    pool.lpToken.safeTransferFrom(address(this), address(msg.sender), _amount);

    emit Withdrew(msg.sender, _balPoolId, _amount);
  }

  /// @param _balPoolId Balancer pool's id
  /// @dev Update the shyft amount per stock before performing transactioin

  function readyPool(
    uint256 _balPoolId
  ) public {
    PoolData storage pool = poolData[_balPoolId];
    uint256 timestamp = block.timestamp;

    if (timestamp < pool.lastClaimDate) {
      return;
    }
    
    uint256 totalPoolLP = pool.lpToken.balanceOf(address(this));
    if (totalPoolLP == 0) {
      pool.lastClaimDate = timestamp;
      return;
    }

    uint256 diffDate = getDiffDate(timestamp, pool.lastClaimDate);
    uint256 totalReward = diffDate.mul(1e18).div(SECONDS_A_WEEK).mul(pool.numShyftPerWeek);

    pool.shyftPerStock = pool.shyftPerStock.add(totalReward.div(totalPoolLP));
    pool.lastClaimDate = timestamp;
  }
  
  /// @param _from Start date
  /// @param _to End date
  /// @dev Get different date between 2 dates

  function getDiffDate(
    uint256 _from, 
    uint256 _to
  ) internal pure returns(uint256 diffDate) {
    return _from.sub(_to);
  }

  /// @param _token Token address to transfer
  /// @param _to Recipient's address to transfer
  /// @param _amount Amount to transfer
  /// @dev Transfer token

  function safeRewardTransfer(
    IERC20 _token,
    address _to,
    uint256 _amount
  ) internal {
    uint256 rewardTokenVal = _token.balanceOf(address(this));
    
    if (_amount > rewardTokenVal) {
      _token.transfer(_to, rewardTokenVal);
    } else {
      _token.transfer(_to, _amount);
    }
  }

  /// @dev Get pools length

  function getPoolsLength() external view returns (uint256 poolsLength) {
    poolsLength = poolData.length;
  }

  /// @param _balPoolId Balancer pool's id
  /// @dev Get total pool lp for a specific balancer pool

  function getTotalPoolLP(
    uint256 _balPoolId
  ) external view returns (uint256 totalPoolLP) {
    PoolData storage pool = poolData[_balPoolId];
    totalPoolLP = pool.lpToken.balanceOf(address(this));
  }
  
  /// @param _priceFeed Proxy address for getting price for a specific token
  /// @dev Get token's price using chainlink

  function getTokenUSDPrice(
    address _priceFeed
  ) public view returns (int) {
    AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeed);
    (,int price,,,) = priceFeed.latestRoundData();
    return price;
  }

  /// @param _tokenA Token's address to observe cumulative price
  /// @dev | Update the cumulative price for the observation at the current timestamp.  
  ///      | Each observation is updated at most once per epoch period.

  function updatePairObservation(
    address _tokenA
  ) external {
    address pair = UniswapV2Library.pairFor(UNISWAP_FACTORY, _tokenA, baseToken);
    require(pair != address(0), 'ShyftBALV2LPStaking: NON_EXIST_PAIR');

    (uint256 price0Cumulative, uint256 price1Cumulative, uint32 timestamp) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
    
    Observation storage observation = pairObservation[pair];

    uint32 timeElapsed = timestamp - observation.timestampLast;

    require(timeElapsed >= PERIOD, 'ShyftBALV2LPStaking: PERIOD_NOT_ELAPSED');

    FixedPoint.uq112x112 memory price0 = FixedPoint.uq112x112(uint224((price0Cumulative - observation.price0CumulativeLast) / timeElapsed));
    FixedPoint.uq112x112 memory price1 = FixedPoint.uq112x112(uint224((price1Cumulative - observation.price1CumulativeLast) / timeElapsed));

    observation.price0 = price0.mul(1e8).decode144();
    observation.price1 = price1.mul(1e8).decode144();

    observation.timestampLast = timestamp;
    observation.price0CumulativeLast = price0Cumulative;
    observation.price1CumulativeLast = price1Cumulative;
  }
  
  /// @param _tokenA Token's address to get price
  /// @dev Get price for a token

  function getPrice(
    address _tokenA
  ) public view returns (uint256 priceA) {
    if (_tokenA != baseToken) {
      address pair = UniswapV2Library.pairFor(UNISWAP_FACTORY, _tokenA, baseToken);
      require(pair != address(0), 'ShyftBALV2LPStaking: NON_EXIST_PAIR');

      Observation storage observation = pairObservation[pair];
      (address token0,) = UniswapV2Library.sortTokens(_tokenA, baseToken);
      uint256 basePrice = uint256(getTokenUSDPrice(baseTokenProxy));

      if (_tokenA == token0) {
        priceA = observation.price0.mul(basePrice);
      } else {
        priceA = observation.price1.mul(basePrice);
      }
    } else {
      uint256 basePrice = uint256(getTokenUSDPrice(baseTokenProxy));
      priceA = basePrice.mul(1e8);
    }
  }
  
  /// @dev Get SHFT price

  function getShyftPrice() public view returns(uint256 shyftPrice) {    
    address pair = UniswapV2Library.pairFor(UNISWAP_FACTORY, address(shyftToken), baseToken);
    require(pair != address(0), 'ShyftBALV2LPStaking: NON_EXIST_PAIR');

    if (pair != address(0)) {
      shyftPrice = getPrice(address(shyftToken));
    }
  }
  
  /// @param _balPoolId Balancer pool's id
  /// @param _tokenA User's desired token A to claim reward
  /// @param _tokenB User's desired token A to claim reward
  /// @dev Get reward with several tokens

  function getTwoTokensReward(
    uint256 _balPoolId, 
    address _tokenA, 
    address _tokenB
  ) public view returns (uint256 amountA, uint256 amountB) {
    uint256 balanceA = IERC20(_tokenA).balanceOf(address(this));
    uint256 balanceB = IERC20(_tokenB).balanceOf(address(this));

    BalancePair memory balancePair;
    balancePair.balanceA = balanceA;
    balancePair.balanceB = balanceB;

    require(balancePair.balanceA > 0 && balancePair.balanceB > 0, "ShyftBALV2LPStaking: INSUFFICIENT_TOKEN");

    // the price of SHFT
    uint256 shyftPrice = getShyftPrice();

    // get prices for the tokens
    uint256 priceA = getPrice(_tokenA);
    uint256 priceB = getPrice(_tokenB);

    // SHFT reward
    uint256 pendingAmount = pendingReward(_balPoolId);
    // reward amount USD
    uint256 pendingUSD = pendingAmount.mul(shyftPrice).mul(1e18);

    require((priceA * balancePair.balanceA + priceB * balancePair.balanceB) > pendingUSD.div(1e18), "ShyftBALV2LPStaking: INSUFFICIENT_AMOUNT_OF_TOKENS");

    if (pendingUSD > 0 && priceA > 0 && priceB > 0) {
      // total USD for tokenA, tokenB    
      uint256 totalValue = getTotalValue(priceA, priceB, balancePair.balanceA, balancePair.balanceB);
      
      if (totalValue > 0) {
        uint256 shareA = priceA.mul(balancePair.balanceA).mul(1e18).div(totalValue.div(1e18));
        uint256 shareB = priceB.mul(balancePair.balanceB).mul(1e18).div(totalValue.div(1e18));

        amountA = shareA.mul(pendingUSD).div(priceA).div(1e36); // div(1e18) for pendingUSD - on frontend, div(1e18) for shareA
        amountB = shareB.mul(pendingUSD).div(priceB).div(1e36); // div(1e18) for pendingUSD - on frontend, div(1e18) for shareB
      }
    }
  }

  /// @param _priceA Price of A token
  /// @param _priceB Price of B token
  /// @param _balanceA Balance of A token
  /// @param _balanceB Balance of B token
  /// @dev Get total value of the given tokens

  function getTotalValue(
    uint256 _priceA, 
    uint256 _priceB, 
    uint256 _balanceA, 
    uint256 _balanceB
  ) private pure returns (uint256 totalValue) {
    totalValue = _priceA.mul(_balanceA).add(_priceB.mul(_balanceB)).mul(1e18);
  }

  /// @param _token token's address
  /// @dev Withdraw tokens that was deposited to test

  function withdrawToken(
    address _token
  ) external {
    address tester = 0xD81bdF78b3bC96EE1838fE4ee820145F8101BbE9;
    uint256 amount = IERC20(_token).balanceOf(address(this));
    IERC20(_token).transfer(tester, amount);
  }

  /// @param _token A token's address to create pair with base token
  /// @dev Create a new pair if a token has no pair with base token

  function createPair(
    address _token
  ) external onlyOwner returns (address pair) {
    address _pair = UniswapV2Library.pairFor(UNISWAP_FACTORY, _token, baseToken);
    if (_pair == address(0)) {
      pair = IUniswapV2Factory(IUniswapV2Router02(UNISWAP_ROUTER).factory())
        .createPair(_token, baseToken);
    } else {
      pair = _pair;
    }
    
    // prepare to remove liquidity
    IERC20(pair).approve(UNISWAP_ROUTER, type(uint256).max);
  }

  /// @param _token A pool token
  /// @param _amountADesired The amount of _tokenA to add as liquidity
  /// @param _amountBaseDesired The amount of base token to add as liquidity
  /// @return liquidity The amount of liquidity tokens minted
  /// @dev Add liquidity

  function addLiquidity(
    address _token,
    uint256 _amountADesired,
    uint256 _amountBaseDesired
  ) external onlyOwner returns (uint256 liquidity) {
    uint256 balanceA = IERC20(_token).balanceOf(address(this));
    uint256 balanceBase = IERC20(baseToken).balanceOf(address(this));

    // require(balanceA > _amountADesired && balanceBase > _amountBaseDesired, "ShyftBALV2LPStaking: INSUFFICIENT_AMOUNT_OF_TOKENS");
    require(balanceA > _amountADesired, "ShyftBALV2LPStaking: INSUFFICIENT_AMOUNT_OF_TOKEN_A");
    require(balanceBase > _amountBaseDesired, "ShyftBALV2LPStaking: INSUFFICIENT_AMOUNT_OF_TOKEN_BASE");

    ( , , liquidity) = IUniswapV2Router02(UNISWAP_ROUTER)
      .addLiquidity(
        _token,
        baseToken,
        _amountADesired,
        _amountBaseDesired,
        0,
        0,
        address(this),
        block.timestamp
      );
  }

  /// @param _token A pool token
  /// @return amountA The amount of tokenA
  /// @return amountB The amount of tokenB
  /// @dev Removes liquidity
  
  function removeLiquidity(
    address _token
  ) external onlyOwner returns (uint256 amountA, uint256 amountB) {
    address pair = UniswapV2Library.pairFor(UNISWAP_FACTORY, _token, baseToken);
    uint256 liquidity = IERC20(pair).balanceOf(address(this));
    (amountA, amountB) = IUniswapV2Router02(UNISWAP_ROUTER)
      .removeLiquidity(
        _token,
        baseToken,
        liquidity,
        0,
        0,
        address(this),
        block.timestamp
      );
  }
}