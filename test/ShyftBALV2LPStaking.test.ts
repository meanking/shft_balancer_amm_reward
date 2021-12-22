import { expect } from "chai"
import { ethers, waffle, network } from "hardhat"
import { ShyftBALV2LPStaking, ERC20Mock } from "../typechain"
import { fixture } from "./utilities/fixture"

const fixtureLoader = waffle.createFixtureLoader

describe("Shyft BALV2LP Staking", () => {
  // wallets
  const [alice, bob, wallet] = waffle.provider.getWallets()

  let shyftToken: ERC20Mock
  let lpToken: ERC20Mock
  let baseToken: ERC20Mock
  let rewardTokenA: ERC20Mock
  let rewardTokenB: ERC20Mock
  let shyftBALV2LPStaking: ShyftBALV2LPStaking
  let loadFixture: ReturnType<typeof fixtureLoader>

  const goAhead = async (seconds: Number) => {
    await network.provider.send("evm_increaseTime", [seconds])
    await network.provider.send("evm_mine")
  }

  // Number of shyft token for a week
  const numShyftPerWeek = 70

  before("Load fixture", async () => {
    // load fixture to use contracts
    loadFixture = fixtureLoader([wallet])
  })
  
  beforeEach("Deploy contracts", async () => {
    ({ shyftToken, lpToken, baseToken, rewardTokenA, rewardTokenB, shyftBALV2LPStaking } = await loadFixture(fixture))

    // add a new pool
    await shyftBALV2LPStaking.addPool(lpToken.address, numShyftPerWeek)

    // mint 100, 500 tokens to each alice and bob for lpToken 
    // (they will be used to deposit to shyftBALV2LPStaking)
    await lpToken.mint(alice.address, ethers.utils.parseEther('1000'))
    await lpToken.mint(bob.address, ethers.utils.parseEther('5000'))

    // mint 1000 tokens to wallet for shyftToken, rewardTokenA, rewardTokenB
    await shyftToken.mint(wallet.address, ethers.utils.parseEther('10000'))
    await baseToken.mint(wallet.address, ethers.utils.parseEther('30000'))
    await rewardTokenA.mint(wallet.address, ethers.utils.parseEther('10000'))
    await rewardTokenB.mint(wallet.address, ethers.utils.parseEther('10000'))

    // approve tokens to transfer
    await shyftToken.approve(shyftBALV2LPStaking.address, ethers.utils.parseEther('10000'))
    await baseToken.approve(shyftBALV2LPStaking.address, ethers.utils.parseEther('30000'))
    await rewardTokenA.approve(shyftBALV2LPStaking.address, ethers.utils.parseEther('10000'))
    await rewardTokenB.approve(shyftBALV2LPStaking.address, ethers.utils.parseEther('10000'))

    // pre fund shyft token to shyftBALV2LPStaking
    await shyftBALV2LPStaking.preFund(shyftToken.address, ethers.utils.parseEther('10000'))
    await shyftBALV2LPStaking.preFund(baseToken.address, ethers.utils.parseEther('30000'))
    await shyftBALV2LPStaking.preFund(rewardTokenA.address, ethers.utils.parseEther('10000'))
    await shyftBALV2LPStaking.preFund(rewardTokenB.address, ethers.utils.parseEther('10000'))

    // approve
    await lpToken.connect(alice).approve(shyftBALV2LPStaking.address, ethers.utils.parseEther('100'))
    await lpToken.connect(bob).approve(shyftBALV2LPStaking.address, ethers.utils.parseEther('500'))

    // deposit
    await shyftBALV2LPStaking.connect(alice).deposit(0, 100)
    goAhead(172800) // 2 days
    await shyftBALV2LPStaking.connect(bob).deposit(0, 500)

    expect(await lpToken.balanceOf(shyftBALV2LPStaking.address)).to.equal(600)
    goAhead(432000) // 5 days
  })

  it("Reward calculation", async () => {
    expect(await shyftBALV2LPStaking.connect(alice).pendingReward(0)).to.equal(28)
    expect(await shyftBALV2LPStaking.connect(bob).pendingReward(0)).to.equal(41)
  })

  it("Tokens' amount calculation for reward claiming", async () => {
    await shyftBALV2LPStaking.addLiquidity(shyftToken.address, ethers.utils.parseEther('250'), ethers.utils.parseEther('250'))
    await shyftBALV2LPStaking.addLiquidity(rewardTokenA.address, ethers.utils.parseEther('500'), ethers.utils.parseEther('250'))
    await shyftBALV2LPStaking.addLiquidity(rewardTokenB.address, ethers.utils.parseEther('1000'), ethers.utils.parseEther('250'))

    await shyftBALV2LPStaking.updatePairObservation(shyftToken.address)
    await shyftBALV2LPStaking.updatePairObservation(rewardTokenA.address)
    await shyftBALV2LPStaking.updatePairObservation(rewardTokenB.address)
    goAhead(60)

    await shyftBALV2LPStaking.updatePairObservation(shyftToken.address)
    await shyftBALV2LPStaking.updatePairObservation(rewardTokenA.address)
    await shyftBALV2LPStaking.updatePairObservation(rewardTokenB.address)

    const { amountA: aliceAmountA, amountB: aliceAmountB } = await shyftBALV2LPStaking.connect(alice).getTwoTokensReward(0, rewardTokenA.address, rewardTokenB.address)
    const { amountA: bobAmountA, amountB: bobAmountB } = await shyftBALV2LPStaking.connect(bob).getTwoTokensReward(0, rewardTokenA.address, rewardTokenB.address)
    
    expect(ethers.utils.formatEther(aliceAmountA)).to.equal('0.000000000000000037') // rewardTokenA 37 for alice
    expect(ethers.utils.formatEther(aliceAmountB)).to.equal('0.000000000000000035') // rewardTokenB 35 for alice
    expect(ethers.utils.formatEther(bobAmountA)).to.equal('0.000000000000000055') // rewardTokenA 55 for bob
    expect(ethers.utils.formatEther(bobAmountB)).to.equal('0.000000000000000052') // rewardTokenB 52 for bob
  })
})