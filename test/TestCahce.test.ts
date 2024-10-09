import { ethers, network } from "hardhat"
import { expect } from "chai"
import { toWei, toUnit, fromUnit, fromWei, createContract, zeroAddress, encodePositionId } from "../scripts/deployUtils"

const U = ethers.utils
const B = ethers.BigNumber

describe("TestCache", () => {
  let user0

  let cache

  const a2b = (a) => {
    return a + "000000000000000000000000"
  }
  const u2b = (u) => {
    return ethers.utils.hexZeroPad(u.toTwos(256).toHexString(), 32)
  }

  beforeEach(async () => {
    cache = await createContract("TestCache", [])
  })

  it("cache", async () => {
    console.log((await (await cache.do1(1)).wait()).gasUsed)
    console.log((await (await cache.do2(1)).wait()).gasUsed)
    console.log((await (await cache.do3(1)).wait()).gasUsed)
  })
})
