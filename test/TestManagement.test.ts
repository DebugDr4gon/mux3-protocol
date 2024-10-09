import { ethers } from "hardhat"
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

describe("TestFacetManagement", () => {
  let tester: any
  let user0: any

  before(async () => {
    user0 = (await ethers.getSigners())[0]
  })

  beforeEach(async () => {
    tester = await createContract("TestFacetManagement", [])
    await tester.setup()
  })

  it("test_CollateralManager_retrieveDecimals", async () => {
    await tester.test_CollateralManager_retrieveDecimals()
  })

  it("test_CollateralManager_addCollateralToken", async () => {
    await tester.test_CollateralManager_addCollateralToken()
  })

  it("test_MarketManager_createMarket", async () => {
    await tester.test_MarketManager_createMarket()
  })

  it("test_MarketManager_setMarketConfig", async () => {
    await tester.test_MarketManager_setMarketConfig()
  })

  it("test_errors", async () => {
    await expect(tester.addCollateralToken(ethers.constants.AddressZero, 18)).to.be.revertedWith("InvalidAddress")
    await expect(tester.addCollateralToken(await tester.d6(), 18)).to.be.revertedWith("UnmatchedDecimals")

    await tester.addCollateralToken(await tester.d6(), 6)
    await expect(tester.addCollateralToken(await tester.d6(), 6)).to.be.revertedWith("CollateralAlreadyExists")
  })
})
