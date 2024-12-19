import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { createContract } from "../scripts/deployUtils"
import { TestMux3FacetBase } from "../typechain"

describe("Mux3FacetBase", () => {
  let tester: TestMux3FacetBase
  let user0: any

  before(async () => {
    user0 = (await ethers.getSigners())[0]
  })

  beforeEach(async () => {
    tester = (await createContract("TestMux3FacetBase", [])) as TestMux3FacetBase
    await tester.setup()
  })

  it("test_isPoolExist", async () => {
    await tester.test_isPoolExist()
  })

  it("test_isOracleProvider", async () => {
    await tester.test_isOracleProvider()
  })

  it("test_collateralToRaw", async () => {
    await tester.test_collateralToWad()
  })

  it("test_collateralToRaw", async () => {
    await tester.test_collateralToRaw()
  })
})
