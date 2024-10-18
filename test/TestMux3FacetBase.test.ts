import { ethers, network } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import {
  toWei,
  createContract,
  OrderType,
  PositionOrderFlags,
  toBytes32,
  encodePositionId,
  toUnit,
  zeroAddress,
} from "../scripts/deployUtils"

describe("TestMux3FacetBase", () => {
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

  it("test_isAuthorized", async () => {
    await tester.test_isAuthorized()
  })

  it("test_collateralToRaw", async () => {
    await tester.test_collateralToWad()
  })

  it("test_collateralToRaw", async () => {
    await tester.test_collateralToRaw()
  })
})
