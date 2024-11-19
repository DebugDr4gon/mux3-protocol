import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { createContract } from "../scripts/deployUtils"

describe("Mux3FacetBase", () => {
  let tester: any
  let user0: any

  before(async () => {
    user0 = (await ethers.getSigners())[0]
  })

  beforeEach(async () => {
    tester = await createContract("TestMux3FacetBase", [])
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
