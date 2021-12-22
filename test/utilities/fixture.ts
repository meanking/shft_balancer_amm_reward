import { BigNumber } from "ethers"
import { ethers } from "hardhat"

import { ShyftBALV2LPStaking, ERC20Mock } from "../../typechain"

export async function fixture() {
  const MockFactory                = await ethers.getContractFactory("ERC20Mock")
  const shyftBALV2LPStakingFactory = await ethers.getContractFactory("ShyftBALV2LPStaking")

  const shyftToken = (await MockFactory.deploy(BigNumber.from(2).pow(255))) as ERC20Mock
  const lpToken    = (await MockFactory.deploy(BigNumber.from(2).pow(255))) as ERC20Mock
  const baseToken  = (await MockFactory.deploy(BigNumber.from(2).pow(255))) as ERC20Mock
  const rewardTokenA = (await MockFactory.deploy(BigNumber.from(2).pow(255))) as ERC20Mock
  const rewardTokenB = (await MockFactory.deploy(BigNumber.from(2).pow(255))) as ERC20Mock

  const BASE_TOKEN_PROXY = "0x777A68032a88E5A84678A77Af2CD65A7b3c0775a"

  const currentBlockNumber = await ethers.provider.getBlockNumber()
  const currentTimestamp   = (await ethers.provider.getBlock(currentBlockNumber)).timestamp

  const shyftBALV2LPStaking = (await shyftBALV2LPStakingFactory.deploy(shyftToken.address, baseToken.address, BASE_TOKEN_PROXY, currentTimestamp)) as ShyftBALV2LPStaking
  return { shyftToken, lpToken, baseToken, rewardTokenA, rewardTokenB, shyftBALV2LPStaking }
}