const hh = require("hardhat")

async function main() {
  const ShyftBALV2LPStaking = await hh.ethers.getContractFactory("ShyftBALV2LPStaking")
  // Deploy params: 
  //   arg1: Shyft token address
  //   arg2: Base token address to get price of a token
  //         | DAI token address
  //         |     Mainnet :0x6B175474E89094C44Da98b954EedeAC495271d0F
  //         |     Kovan   :0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa
  //         |     Rinkeby :0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735
  //   arg3: A proxy to get price of the base token
  //         | Chainlink DAI Proxy
  //         |     Mainnet :0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9
  //         |     Kovan   :0x777A68032a88E5A84678A77Af2CD65A7b3c0775a
  //         |     Rinkeby :0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF
  //   arg4: Contract start date timestamp
  const BALV2Staking = await ShyftBALV2LPStaking.deploy(
    "0xb17C88bDA07D28B3838E0c1dE6a30eAfBCF52D85", 
    "0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa", 
    "0x777A68032a88E5A84678A77Af2CD65A7b3c0775a", 
    1627201708
  )

  console.log("ShyftBALV2LPStaking was deployed to :: ", BALV2Staking.address, " successfully.");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });