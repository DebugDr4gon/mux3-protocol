import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { createContract } from "../scripts/deployUtils"
import { TestConfigMap } from "../typechain"

describe("ConfigMap", () => {
  let tester: TestConfigMap
  let user0: any

  before(async () => {
    user0 = (await ethers.getSigners())[0]
  })

  beforeEach(async () => {
    tester = (await createContract("TestConfigMap", [])) as TestConfigMap
  })

  it("test_set", async () => {
    await tester.test_setUint256()
  })
})
