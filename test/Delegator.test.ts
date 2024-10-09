import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import {
  toWei,
  createContract,
  PositionOrderFlags,
  toBytes32,
  encodePositionId,
  toUnit,
  zeroAddress,
} from "../scripts/deployUtils"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { CollateralPool, OrderBook, TestMux3, MockERC20, Delegator, WETH9 } from "../typechain"
import { time } from "@nomicfoundation/hardhat-network-helpers"

const a2b = (a) => {
  return a + "000000000000000000000000"
}
const u2b = (u) => {
  return ethers.utils.hexZeroPad(u.toTwos(256).toHexString(), 32)
}

describe("Delegator", () => {
  const refCode = toBytes32("")
  const long1 = toBytes32("LongBTC")

  let usdc: MockERC20
  let weth: WETH9

  let admin: SignerWithAddress
  let trader1: SignerWithAddress
  let trader2: SignerWithAddress
  let trader3: SignerWithAddress

  let core: TestMux3
  let imp: CollateralPool
  let pool1: CollateralPool
  let orderBook: OrderBook
  let delegator: Delegator

  let timestampOfTest: number

  before(async () => {
    const accounts = await ethers.getSigners()
    admin = accounts[0]
    trader1 = accounts[1]
    trader2 = accounts[2]
    trader3 = accounts[3]
    weth = (await createContract("WETH9", [])) as WETH9
  })

  beforeEach(async () => {
    timestampOfTest = await time.latest()

    // token
    usdc = (await createContract("MockERC20", ["USDC", "USDC", 6])) as MockERC20
    await usdc.mint(trader1.address, toUnit("100000", 6))

    // core
    core = (await createContract("TestMux3", [])) as TestMux3
    imp = (await createContract("CollateralPool", [])) as CollateralPool
    await core.initialize()
    await core.setCollateralPoolImplementation(imp.address)
    await core.addCollateralToken(usdc.address, 6)
    await core.setCollateralTokenStatus(usdc.address, true)

    // pool 1
    await core.createCollateralPool("TN1", "TS1", usdc.address, 6)
    const pool1Addr = (await core.listCollateralPool())[0]
    pool1 = (await ethers.getContractAt("CollateralPool", pool1Addr)) as CollateralPool

    // markets only uses pool1
    await core.createMarket(
      long1,
      "Long1",
      true, // isLong
      [pool1.address]
    )
    await core.setMarketConfig(long1, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.1")))

    // orderBook
    const libOrderBook = await createContract("LibOrderBook")
    orderBook = (await createContract("OrderBook", [], {
      "contracts/libraries/LibOrderBook.sol:LibOrderBook": libOrderBook,
    })) as OrderBook
    await orderBook.initialize(core.address, weth.address)

    // delegator
    delegator = (await createContract("Delegator", [])) as Delegator
    await delegator.initialize(orderBook.address)

    // role
    await orderBook.grantRole(ethers.utils.id("DELEGATOR_ROLE"), delegator.address)
    await core.grantRole(ethers.utils.id("ORDER_BOOK_ROLE"), orderBook.address)

    // prices
    await core.setMockPrice(long1, toWei("1000"))
    await core.setMockPrice(a2b(usdc.address), toWei("1"))
  })

  it("place, cancel", async () => {
    // set delegate
    const balance1 = await ethers.provider.getBalance(trader2.address)
    await delegator.connect(trader1).delegate(trader2.address, 0, { value: toWei("1") })
    const balance2 = await ethers.provider.getBalance(trader2.address)
    expect(balance2.sub(balance1)).to.equal(toWei("1"))

    // open short, using usdc
    const positionId = encodePositionId(trader1.address, 0)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    const args = {
      positionId,
      marketId: long1,
      size: toWei("1"),
      flags: PositionOrderFlags.OpenPosition,
      limitPrice: toWei("1000"),
      tpPrice: "0",
      slPrice: "0",
      expiration: timestampOfTest + 86400 * 2 + 905 + 300,
      tpslExpiration: timestampOfTest + 86400 * 2 + 905 + 300,
      profitTokenId: 0,
      tpslProfitTokenId: 0,
      initialLeverage: toWei("100"),
      collateralToken: usdc.address,
      collateralAmount: toUnit("1000", 6),
      profitToken: zeroAddress,
      tpslProfitToken: zeroAddress,
    }
    {
      await expect(delegator.connect(trader3).placePositionOrder(args, refCode)).to.revertedWith("not delegated")
      await expect(delegator.connect(trader2).placePositionOrder(args, refCode)).to.revertedWith("no action count")
      await delegator.connect(trader1).delegate(trader2.address, 100)
      const tx1 = await delegator
        .connect(trader2)
        .multicall([
          (await delegator.populateTransaction.transferToken(usdc.address, toUnit("1000", 6))).data!,
          (await delegator.populateTransaction.placePositionOrder(args, refCode)).data!,
        ])
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 0, [
          args.marketId,
          args.positionId,
          args.size,
          args.flags,
          args.limitPrice,
          args.tpPrice,
          args.slPrice,
          args.expiration,
          args.tpslExpiration,
          args.profitToken,
          args.tpslProfitToken,
          args.collateralToken,
          args.collateralAmount,
          args.initialLeverage,
        ])
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000", 6))
    }
    // cancel
    {
      await expect(delegator.connect(trader3).cancelOrder(0)).to.revertedWith("not delegated")
      await delegator.connect(trader2).delegate(trader3.address, 100)
      await expect(delegator.connect(trader3).cancelOrder(0)).to.revertedWith("not authorized")
      await expect(delegator.connect(trader2).cancelOrder(1)).to.revertedWith("order not exists")
      await delegator.connect(trader2).cancelOrder(0)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("100000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
    }
  })
})
