import { ethers, network } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { createContract } from "../scripts/deployUtils"

describe("LibTypeCast.test", () => {
  let tester: any
  let user0: any

  before(async () => {
    user0 = await ethers.getSigner(0)
  })

  beforeEach(async () => {
    tester = await createContract("TestLibTypeCast", [])
    await tester.setup()
  })

  after(async () => {
    // await network.provider.request({
    //   method: "hardhat_reset",
    //   params: [],
    // })
  })

  it("test_typeCast", async () => {
    await tester.test_typeCast()
  })

  it("test_typeCast_errors", async () => {
    await expect(tester.test_typeCast_uintUnderFlow()).to.be.revertedWith("UNDERFLOW")
    await expect(tester.test_typeCast_invalidBoolean()).to.be.revertedWith("INVALID")
    await expect(tester.test_typeCast_uint64Overflow()).to.be.revertedWith("OVERFLOW")
    await expect(tester.test_typeCast_uint96Overflow()).to.be.revertedWith("OVERFLOW")
    await expect(tester.test_typeCast_int256Overflow()).to.be.revertedWith("OVERFLOW")
  })
})
