import { ethers } from "hardhat"
import { createContract } from "../scripts/deployUtils"

describe("Cache", () => {
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
