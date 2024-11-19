import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { createContract } from "../scripts/deployUtils"

describe("ConfigMap", () => {
  let tester: any
  let user0: any

  before(async () => {
    user0 = (await ethers.getSigners())[0]
  })

  beforeEach(async () => {
    tester = await createContract("TestConfigMap", [])
  })

  it("test_set", async () => {
    await tester.test_setUint256()
  })
})
