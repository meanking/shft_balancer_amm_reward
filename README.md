# AMMRewardBalancerContract
Balancer AMM reward system

1. Calculating AMM reward for balance LP token staking
2. Getting tokens' amount for the reward claiming

## Using Software

NodeJS, Hardhat

- Node v12.18.0
- Hardhat 2.3.3
- Solidity - 0.8.0 (solc-js)

## Deploy Contract

```sh
npx hardhat run scripts/deploy.js --network [network_name]
```

## Verify Contract

```sh
npx hardhat verify --network [network_name] [contract_address] [argument1(SHFT-V2 address)] [argument2(current timestamp)]
```

## Using hardhat console

```sh
npx hardhat node
npx hardhat run --network localhost scripts/deploy.js
npx hardhat console --network localhost
```

## Testing process

```sh
npx hardhat test
```

## Metamask read/write:

https://kovan.etherscan.io/address/0x8fE8FE4233bF3F5F2433E58a669A5FEDB979C84B#code

## Base token to calculate the price of a token

```sh
DAI token address
  | Mainnet :0x6B175474E89094C44Da98b954EedeAC495271d0F
  | Kovan   :0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa
  | Rinkeby :0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735
```

## A proxy of a base token to get the price using chainlink

```sh
Chainlink DAI Proxy
  | Mainnet :0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9
  | Kovan   :0x777A68032a88E5A84678A77Af2CD65A7b3c0775a
  | Rinkeby :0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF
```