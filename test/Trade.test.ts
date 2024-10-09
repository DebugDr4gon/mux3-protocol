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
  encodePoolMarketKey,
} from "../scripts/deployUtils"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { CollateralPool, OrderBook, TestMux3, MockERC20, WETH9, MockFeeDistributor } from "../typechain"
import { time } from "@nomicfoundation/hardhat-network-helpers"

const a2b = (a) => {
  return a + "000000000000000000000000"
}
const u2b = (u) => {
  return ethers.utils.hexZeroPad(u.toTwos(256).toHexString(), 32)
}

describe("Trade (normal pools)", () => {
  const refCode = toBytes32("")
  const long1 = toBytes32("LongBTC")
  const short1 = toBytes32("ShortBTC")

  let usdc: MockERC20
  let arb: MockERC20
  let btc: MockERC20
  let weth: WETH9

  let admin: SignerWithAddress
  let broker: SignerWithAddress
  let lp1: SignerWithAddress
  let trader1: SignerWithAddress

  let core: TestMux3
  let imp: CollateralPool
  let pool1: CollateralPool
  let pool2: CollateralPool
  let pool3: CollateralPool
  let orderBook: OrderBook
  let feeDistributor: MockFeeDistributor

  let timestampOfTest: number

  before(async () => {
    const accounts = await ethers.getSigners()
    admin = accounts[0]
    broker = accounts[1]
    lp1 = accounts[2]
    trader1 = accounts[3]
    weth = (await createContract("WETH9", [])) as WETH9
  })

  beforeEach(async () => {
    timestampOfTest = await time.latest()

    // token
    usdc = (await createContract("MockERC20", ["USDC", "USDC", 6])) as MockERC20
    arb = (await createContract("MockERC20", ["ARB", "ARB", 18])) as MockERC20
    btc = (await createContract("MockERC20", ["BTC", "BTC", 8])) as MockERC20
    await usdc.mint(lp1.address, toUnit("1000000", 6))
    await usdc.mint(trader1.address, toUnit("100000", 6))
    await arb.mint(lp1.address, toUnit("1000000", 18))
    await arb.mint(trader1.address, toUnit("100000", 18))
    await btc.mint(lp1.address, toUnit("1000000", 8))
    await btc.mint(trader1.address, toUnit("100000", 8))

    // core
    core = (await createContract("TestMux3", [])) as TestMux3
    imp = (await createContract("CollateralPool", [])) as CollateralPool
    await core.initialize()
    await core.setCollateralPoolImplementation(imp.address)
    await core.addCollateralToken(usdc.address, 6)
    await core.addCollateralToken(arb.address, 18)
    await core.addCollateralToken(btc.address, 8)
    await core.setCollateralTokenStatus(usdc.address, true)
    await core.setCollateralTokenStatus(arb.address, true)
    await core.setCollateralTokenStatus(btc.address, true)
    await core.setConfig(ethers.utils.id("MC_BORROWING_BASE_APY"), u2b(toWei("0.10")))
    await core.setConfig(ethers.utils.id("MC_BORROWING_INTERVAL"), u2b(ethers.BigNumber.from(3600)))

    // pool 1
    await core.createCollateralPool("TN0", "TS0", usdc.address, 6)
    const poolAddr = (await core.listCollateralPool())[0]
    pool1 = (await ethers.getContractAt("CollateralPool", poolAddr)) as CollateralPool
    await pool1.setConfig(ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306")))
    await pool1.setConfig(ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938")))
    await pool1.setConfig(ethers.utils.id("MCP_IS_HIGH_PRIORITY"), u2b(toWei("0")))
    await pool1.setConfig(ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000")))
    await pool1.setConfig(ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001")))
    await pool1.setConfig(encodePoolMarketKey("MCP_ADL_RESERVE_RATE", long1), u2b(toWei("0.80")))
    await pool1.setConfig(encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", long1), u2b(toWei("0.75")))
    await pool1.setConfig(encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", long1), u2b(toWei("0.70")))
    await pool1.setConfig(encodePoolMarketKey("MCP_ADL_RESERVE_RATE", short1), u2b(toWei("0.80")))
    await pool1.setConfig(encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", short1), u2b(toWei("0.75")))
    await pool1.setConfig(encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", short1), u2b(toWei("0.70")))

    // pool 2
    await core.createCollateralPool("TN1", "TS1", usdc.address, 6)
    const pool2Addr = (await core.listCollateralPool())[1]
    pool2 = (await ethers.getContractAt("CollateralPool", pool2Addr)) as CollateralPool
    await pool2.setConfig(ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("3.46024")))
    await pool2.setConfig(ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-2.34434")))
    await pool2.setConfig(ethers.utils.id("MCP_IS_HIGH_PRIORITY"), u2b(toWei("0")))
    await pool2.setConfig(ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000")))
    await pool2.setConfig(ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001")))
    await pool2.setConfig(encodePoolMarketKey("MCP_ADL_RESERVE_RATE", long1), u2b(toWei("0.80")))
    await pool2.setConfig(encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", long1), u2b(toWei("0.75")))
    await pool2.setConfig(encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", long1), u2b(toWei("0.70")))
    await pool2.setConfig(encodePoolMarketKey("MCP_ADL_RESERVE_RATE", short1), u2b(toWei("0.80")))
    await pool2.setConfig(encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", short1), u2b(toWei("0.75")))
    await pool2.setConfig(encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", short1), u2b(toWei("0.70")))

    // pool 3
    await core.createCollateralPool("TN2", "TS2", btc.address, 8)
    const pool3Addr = (await core.listCollateralPool())[2]
    pool3 = (await ethers.getContractAt("CollateralPool", pool3Addr)) as CollateralPool
    await pool3.setConfig(ethers.utils.id("MCP_BORROWING_BASE_APY"), u2b(toWei("0.10")))
    await pool3.setConfig(ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("1.92131")))
    await pool3.setConfig(ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-2.91416")))
    await pool3.setConfig(ethers.utils.id("MCP_IS_HIGH_PRIORITY"), u2b(toWei("0")))
    await pool3.setConfig(ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000")))
    await pool3.setConfig(ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001")))
    await pool3.setConfig(encodePoolMarketKey("MCP_ADL_RESERVE_RATE", long1), u2b(toWei("0.80")))
    await pool3.setConfig(encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", long1), u2b(toWei("0.75")))
    await pool3.setConfig(encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", long1), u2b(toWei("0.70")))
    await pool3.setConfig(encodePoolMarketKey("MCP_ADL_RESERVE_RATE", short1), u2b(toWei("0.80")))
    await pool3.setConfig(encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", short1), u2b(toWei("0.75")))
    await pool3.setConfig(encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", short1), u2b(toWei("0.70")))

    // market 1 - uses 3 pools
    await core.createMarket(
      long1,
      "Long1",
      true, // isLong
      [pool1.address, pool2.address, pool3.address]
    )
    await core.setMarketConfig(long1, ethers.utils.id("MM_POSITION_FEE_RATE"), u2b(toWei("0.001")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_INITIAL_MARGIN_RATE"), u2b(toWei("0.006")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_MAINTENANCE_MARGIN_RATE"), u2b(toWei("0.005")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.1")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_MAX_INITIAL_LEVERAGE"), u2b(toWei("100")))

    await core.createMarket(
      short1,
      "Short1",
      false, // isLong
      [pool1.address, pool2.address, pool3.address]
    )
    await core.setMarketConfig(short1, ethers.utils.id("MM_POSITION_FEE_RATE"), u2b(toWei("0.001")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_INITIAL_MARGIN_RATE"), u2b(toWei("0.006")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_MAINTENANCE_MARGIN_RATE"), u2b(toWei("0.005")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.1")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_MAX_INITIAL_LEVERAGE"), u2b(toWei("100")))

    const libOrderBook = await createContract("LibOrderBook")
    orderBook = (await createContract("OrderBook", [], {
      "contracts/libraries/LibOrderBook.sol:LibOrderBook": libOrderBook,
    })) as OrderBook
    await orderBook.initialize(core.address, weth.address)
    await orderBook.setConfig(ethers.utils.id("MCO_LIQUIDITY_LOCK_PERIOD"), u2b(ethers.BigNumber.from(60 * 15)))
    await orderBook.setConfig(ethers.utils.id("MCO_MARKET_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(60 * 2)))
    await orderBook.setConfig(ethers.utils.id("MCO_LIMIT_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(86400 * 30)))
    await orderBook.setConfig(ethers.utils.id("MCO_CANCEL_COOL_DOWN"), u2b(ethers.BigNumber.from(5)))

    // feeDistributor
    feeDistributor = (await createContract("MockFeeDistributor", [core.address])) as MockFeeDistributor
    await core.setConfig(ethers.utils.id("MC_FEE_DISTRIBUTOR"), a2b(feeDistributor.address))

    // role
    await orderBook.grantRole(ethers.utils.id("BROKER_ROLE"), broker.address)
    await core.grantRole(ethers.utils.id("ORDER_BOOK_ROLE"), orderBook.address)

    // price
    await core.setMockPrice(long1, toWei("50000"))
    await core.setMockPrice(short1, toWei("50000"))
    await core.setMockPrice(a2b(usdc.address), toWei("1"))
    await core.setMockPrice(a2b(arb.address), toWei("2"))
    await core.setMockPrice(a2b(btc.address), toWei("50000"))
  })

  it("deposit 2 tokens, withdraw 2 collaterals when position = 0", async () => {
    const positionId = encodePositionId(trader1.address, 0)
    await usdc.connect(trader1).transfer(orderBook.address, toUnit("1000", 6))
    await arb.connect(trader1).transfer(orderBook.address, toUnit("500", 18))
    {
      await expect(
        orderBook.connect(trader1).depositCollateral(positionId, usdc.address, toUnit("0", 6))
      ).to.revertedWith("zero collateral")
      const tx1 = await orderBook.connect(trader1).depositCollateral(positionId, usdc.address, toUnit("1000", 6))
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(core.address)).to.equal(toUnit("1000", 6))
      const collaterals = await core.listAccountCollaterals(positionId)
      expect(collaterals.collateralAddresses[0]).to.equal(usdc.address)
      expect(collaterals.collateralAmounts[0]).to.equal(toWei("1000"))
      const positions = await core.listAccountPositions(positionId)
      expect(positions.marketIds.length).to.equal(0)
      expect(positions.positions.length).to.equal(0)
    }
    {
      const tx1 = await orderBook.connect(trader1).depositCollateral(positionId, arb.address, toUnit("500", 18))
      expect(await arb.balanceOf(trader1.address)).to.equal(toUnit("99500", 18))
      expect(await arb.balanceOf(orderBook.address)).to.equal(toUnit("0", 18))
      expect(await arb.balanceOf(core.address)).to.equal(toUnit("500", 18))
      const collaterals = await core.listAccountCollaterals(positionId)
      expect(collaterals.collateralAddresses[0]).to.equal(usdc.address)
      expect(collaterals.collateralAmounts[0]).to.equal(toWei("1000"))
      expect(collaterals.collateralAddresses[1]).to.equal(arb.address)
      expect(collaterals.collateralAmounts[1]).to.equal(toWei("500"))
      const positions = await core.listAccountPositions(positionId)
      expect(positions.marketIds.length).to.equal(0)
      expect(positions.positions.length).to.equal(0)
    }
    {
      await expect(orderBook.connect(lp1).withdrawAllCollateral(positionId)).to.revertedWith("not authorized")
      await orderBook.connect(trader1).withdrawAllCollateral(positionId)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("100000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(core.address)).to.equal(toUnit("0", 6))
      expect(await arb.balanceOf(trader1.address)).to.equal(toUnit("100000", 18))
      expect(await arb.balanceOf(orderBook.address)).to.equal(toUnit("0", 18))
      expect(await arb.balanceOf(core.address)).to.equal(toUnit("0", 18))
      const collaterals = await core.listAccountCollaterals(positionId)
      expect(collaterals.collateralAddresses.length).to.equal(0)
      const positions = await core.listAccountPositions(positionId)
      expect(positions.marketIds.length).to.equal(0)
      expect(positions.positions.length).to.equal(0)
    }
  })

  describe("add some liquidity and test more", () => {
    beforeEach(async () => {
      await time.increaseTo(timestampOfTest + 86400 * 2)
      await usdc.connect(lp1).transfer(orderBook.address, toUnit("1000000", 6))
      {
        const args = {
          poolAddress: pool1.address,
          rawAmount: toUnit("1000000", 6),
          isAdding: true,
          isUnwrapWeth: false,
        }
        await orderBook.connect(lp1).placeLiquidityOrder(args)
        expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      }
      await usdc.mint(lp1.address, toUnit("1000000", 6))
      await usdc.connect(lp1).transfer(orderBook.address, toUnit("1000000", 6))
      {
        const args = {
          poolAddress: pool2.address,
          rawAmount: toUnit("1000000", 6),
          isAdding: true,
          isUnwrapWeth: false,
        }
        await orderBook.connect(lp1).placeLiquidityOrder(args)
        expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      }
      await btc.connect(lp1).transfer(orderBook.address, toUnit("20", 8))
      {
        const args = { poolAddress: pool3.address, rawAmount: toUnit("20", 8), isAdding: true, isUnwrapWeth: false }
        await orderBook.connect(lp1).placeLiquidityOrder(args)
        expect(await btc.balanceOf(lp1.address)).to.equal(toUnit("999980", 8))
      }
      await time.increaseTo(timestampOfTest + 86400 * 2 + 905)
      {
        await orderBook.connect(broker).fillLiquidityOrder(0, [])
        expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("100", 6)) // fee = 1000000 * 0.01% = 100
        expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6))
        expect(await pool1.liquidityBalance()).to.equal(toWei("999900")) // 1000000 - fee
      }
      expect(await pool1.balanceOf(lp1.address)).to.equal(toWei("999900"))
      expect(await pool1.totalSupply()).to.equal(toWei("999900"))
      expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("999900"))
      {
        await orderBook.connect(broker).fillLiquidityOrder(1, [])
        expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("200", 6)) // fee = 1000000 * 0.01% = 100
        expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6))
        expect(await pool2.liquidityBalance()).to.equal(toWei("999900")) // 1000000 - fee
      }
      expect(await pool2.balanceOf(lp1.address)).to.equal(toWei("999900"))
      expect(await pool2.totalSupply()).to.equal(toWei("999900"))
      expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("999900"))
      {
        await orderBook.connect(broker).fillLiquidityOrder(2, [])
        expect(await btc.balanceOf(feeDistributor.address)).to.equal(toUnit("0.002", 8)) // fee = 20 * 0.01% = 0.002
        expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8))
        expect(await pool3.liquidityBalance()).to.equal(toWei("19.998")) // 20 - fee
      }
      expect(await pool3.balanceOf(lp1.address)).to.equal(toWei("999900"))
      expect(await pool3.totalSupply()).to.equal(toWei("999900"))
      expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("999900"))
      {
        const marketInfo1 = await core.marketState(long1)
        expect(marketInfo1.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        const marketInfo2 = await core.marketState(short1)
        expect(marketInfo2.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
      }
    })

    // it("remove liquidity", async () => {
    //   {
    //     const args = { poolAddress: pool3.address, rawAmount: toWei("100"), isAdding: false, isUnwrapWeth: false }
    //     await expect(orderBook.connect(lp1).placeLiquidityOrder({ ...args, rawAmount: toWei("0") })).to.revertedWith(
    //       "zero amount"
    //     )
    //     await pool3.connect(lp1).transfer(orderBook.address, toWei("100"))
    //     const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(args)
    //     await expect(tx1)
    //       .to.emit(orderBook, "NewLiquidityOrder")
    //       .withArgs(lp1.address, 3, [args.poolAddress, args.rawAmount, args.isAdding])
    //     expect(await pool3.balanceOf(lp1.address)).to.equal(toWei("999800")) // 999900 - 100
    //     expect(await pool3.balanceOf(orderBook.address)).to.equal(toWei("100"))
    //   }
    //   expect(await btc.balanceOf(lp1.address)).to.equal(toUnit("999980", 8)) // unchanged
    //   expect(await pool3.totalSupply()).to.equal(toWei("999900")) // unchanged
    //   expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("999900")) // unchanged
    //   await core.setMockPrice(a2b(btc.address), toWei("40000"))
    //   expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("799920")) // aum = 19.998 * 40000 = 799920, nav = 799920 / 999900 = 0.8
    //   {
    //     await expect(orderBook.connect(broker).fillLiquidityOrder(3, [])).to.revertedWith("lock period")
    //     await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 905)
    //     const tx1 = await orderBook.connect(broker).fillLiquidityOrder(3, []) // return 100 * nav / 40000 = 0.002, fee = * 0.01% = 0.0000002
    //     expect(await btc.balanceOf(lp1.address)).to.equal(toUnit("999980.0019998", 8)) // 999980 + 0.002 - fee
    //     expect(await btc.balanceOf(feeDistributor.address)).to.equal(toUnit("0.0020002", 8)) // +fee
    //     expect(await btc.balanceOf(orderBook.address)).to.equal(toUnit("0", 8))
    //     expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.996", 8)) // 19.998 - 100 * nav / 40000
    //     expect(await pool3.balanceOf(lp1.address)).to.equal(toWei("999800")) // unchanged
    //     expect(await pool3.balanceOf(orderBook.address)).to.equal(toWei("0"))
    //     expect(await pool3.liquidityBalance()).to.equal(toWei("19.996")) // 19.998 - 100 * nav / 40000
    //   }
    //   expect(await pool3.totalSupply()).to.equal(toWei("999800")) // 999900 - 100
    //   expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("799840")) // 19.996 * 40000
    // })

    // it("open long: exceeds initial leverage", async () => {
    //   const positionId = encodePositionId(trader1.address, 0)
    //   await usdc.connect(trader1).transfer(orderBook.address, toUnit("1000", 6))
    //   {
    //     const args = {
    //       positionId,
    //       marketId: long1,
    //       size: toWei("1"),
    //       flags: PositionOrderFlags.OpenPosition,
    //       limitPrice: toWei("50000"),
    //       tpPrice: "0",
    //       slPrice: "0",
    //       expiration: timestampOfTest + 86400 * 2 + 905 + 300,
    //       tpslExpiration: timestampOfTest + 86400 * 2 + 905 + 300,
    //       profitTokenId: 0,
    //       tpslProfitTokenId: 0,
    //       initialLeverage: toWei("10"),
    //       collateralToken: usdc.address,
    //       collateralAmount: toUnit("1000", 6),
    //       profitToken: zeroAddress,
    //       tpslProfitToken: zeroAddress,
    //     }
    //     await orderBook.connect(trader1).placePositionOrder(args, refCode)
    //     await expect(orderBook.connect(broker).fillPositionOrder(3, [])).to.revertedWith("UnsafePositionAccount")
    //   }
    // })

    // it("open long: limit price unmatched", async () => {
    //   const positionId = encodePositionId(trader1.address, 0)
    //   await usdc.connect(trader1).transfer(orderBook.address, toUnit("1000", 6))
    //   {
    //     const args = {
    //       positionId,
    //       marketId: long1,
    //       size: toWei("1"),
    //       flags: PositionOrderFlags.OpenPosition,
    //       limitPrice: toWei("50000"),
    //       tpPrice: "0",
    //       slPrice: "0",
    //       expiration: timestampOfTest + 86400 * 2 + 905 + 300,
    //       tpslExpiration: timestampOfTest + 86400 * 2 + 905 + 300,
    //       profitTokenId: 0,
    //       tpslProfitTokenId: 0,
    //       initialLeverage: toWei("100"),
    //       collateralToken: usdc.address,
    //       collateralAmount: toUnit("1000", 6),
    //       profitToken: zeroAddress,
    //       tpslProfitToken: zeroAddress,
    //     }
    //     await core.setMockPrice(long1, toWei("50001"))
    //     await orderBook.connect(trader1).placePositionOrder(args, refCode)
    //     await expect(orderBook.connect(broker).fillPositionOrder(3, [])).to.revertedWith("limitPrice")
    //   }
    // })

    // it("open short: limit price unmatched", async () => {
    //   const positionId = encodePositionId(trader1.address, 0)
    //   await usdc.connect(trader1).transfer(orderBook.address, toUnit("1000", 6))
    //   {
    //     const args = {
    //       positionId,
    //       marketId: short1,
    //       size: toWei("1"),
    //       flags: PositionOrderFlags.OpenPosition,
    //       limitPrice: toWei("50000"),
    //       tpPrice: "0",
    //       slPrice: "0",
    //       expiration: timestampOfTest + 86400 * 2 + 905 + 300,
    //       tpslExpiration: timestampOfTest + 86400 * 2 + 905 + 300,
    //       profitTokenId: 0,
    //       tpslProfitTokenId: 0,
    //       initialLeverage: toWei("100"),
    //       collateralToken: usdc.address,
    //       collateralAmount: toUnit("1000", 6),
    //       profitToken: zeroAddress,
    //       tpslProfitToken: zeroAddress,
    //     }
    //     await core.setMockPrice(short1, toWei("49999"))
    //     await orderBook.connect(trader1).placePositionOrder(args, refCode)
    //     await expect(orderBook.connect(broker).fillPositionOrder(3, [])).to.revertedWith("limitPrice")
    //   }
    // })

    describe("long a little and test more", () => {
      let positionId = ""
      beforeEach(async () => {
        // open long btc, using usdc
        positionId = encodePositionId(trader1.address, 0)
        await usdc.connect(trader1).transfer(orderBook.address, toUnit("10000", 6))
        const args = {
          positionId,
          marketId: long1,
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("50000"),
          tpPrice: "0",
          slPrice: "0",
          expiration: timestampOfTest + 86400 * 2 + 905 + 300,
          tpslExpiration: timestampOfTest + 86400 * 2 + 905 + 300,
          profitTokenId: 0,
          tpslProfitTokenId: 0,
          initialLeverage: toWei("100"),
          collateralToken: usdc.address,
          collateralAmount: toUnit("10000", 6),
          profitToken: zeroAddress,
          tpslProfitToken: zeroAddress,
        }
        {
          await orderBook.connect(trader1).placePositionOrder(args, refCode)
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // - 10000
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("200", 6)) // unchanged
          expect(await usdc.balanceOf(core.address)).to.equal(toUnit("0", 6)) // unchanged
          expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
          expect(await pool1.liquidityBalance()).to.equal(toWei("999900")) // 1000000 - fee
        }
        {
          // fee = 50000 * 1 * 0.1% = 50
          await orderBook.connect(broker).fillPositionOrder(3, [])
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("250", 6)) // + 50
          expect(await usdc.balanceOf(core.address)).to.equal(toUnit("9950", 6)) // + collateral - fee = 0 + 10000 - 50
          expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
          {
            const marketInfo1 = await core.marketState(long1)
            expect(marketInfo1.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
            const marketInfo2 = await core.marketState(short1)
            expect(marketInfo2.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          expect(await pool1.liquidityBalance()).to.equal(toWei("999900")) // unchanged
          {
            const collaterals = await core.listAccountCollaterals(positionId)
            expect(collaterals.collateralAddresses[0]).to.equal(usdc.address)
            expect(collaterals.collateralAmounts[0]).to.equal(toWei("9950")) // collateral - fee = 10000 - 50
            const positions = await core.listAccountPositions(positionId)
            expect(positions.marketIds[0]).to.equal(long1)
            expect(positions.positions[0].size).to.equal(toWei("1"))
            expect(positions.positions[0].entryPrice).to.equal(toWei("50000"))
            expect(positions.positions[0].entryBorrowing).to.equal(toWei("0"))
          }
          {
            const collateralsAndPositions = await core.listAccountCollateralsAndPositionsOf(trader1.address)
            expect(collateralsAndPositions.length).to.equal(1)
            expect(collateralsAndPositions[0].positionId).to.equal(positionId)
            expect(collateralsAndPositions[0].collateralAddresses[0]).to.equal(usdc.address)
            expect(collateralsAndPositions[0].collateralAmounts[0]).to.equal(toWei("9950"))
            expect(collateralsAndPositions[0].positions[0].size).to.equal(toWei("1"))
            expect(collateralsAndPositions[0].positions[0].entryPrice).to.equal(toWei("50000"))
            expect(collateralsAndPositions[0].positions[0].entryBorrowing).to.equal(toWei("0"))
          }
          {
            const longPools = await core.listMarketPools(long1)
            expect(longPools[0].backedPool).to.equal(pool1.address)
            expect(longPools[0].totalSize).to.equal(toWei("1"))
            expect(longPools[0].unpaidBorrowingFeeUsd).to.equal(toWei("0"))
            expect(longPools[1].backedPool).to.equal(pool2.address)
            expect(longPools[1].totalSize).to.equal(toWei("0"))
            expect(longPools[1].unpaidBorrowingFeeUsd).to.equal(toWei("0"))
            expect(longPools[2].backedPool).to.equal(pool3.address)
            expect(longPools[2].totalSize).to.equal(toWei("0"))
            expect(longPools[2].unpaidBorrowingFeeUsd).to.equal(toWei("0"))
            const longPoolState = await pool1.marketState(long1)
            expect(longPoolState.isLong).to.equal(true)
            expect(longPoolState.totalSize).to.equal(toWei("1"))
            expect(longPoolState.averageEntryPrice).to.equal(toWei("50000"))
          }
        }
      })

      it("long again, allocate 2 pools", async () => {
        const positionId = encodePositionId(trader1.address, 0)
        await usdc.mint(orderBook.address, toUnit("100000", 6))
        const args = {
          positionId,
          marketId: long1,
          size: toWei("20"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("50000"),
          tpPrice: "0",
          slPrice: "0",
          expiration: timestampOfTest + 86400 * 2 + 905 + 300,
          tpslExpiration: timestampOfTest + 86400 * 2 + 905 + 300,
          profitTokenId: 0,
          tpslProfitTokenId: 0,
          initialLeverage: toWei("100"),
          collateralToken: usdc.address,
          collateralAmount: toUnit("100000", 6),
          profitToken: zeroAddress,
          tpslProfitToken: zeroAddress,
        }
        {
          await orderBook.connect(trader1).placePositionOrder(args, refCode)
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // - 10000
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("250", 6)) // unchanged
          expect(await usdc.balanceOf(core.address)).to.equal(toUnit("9950", 6)) // unchanged
          expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
          expect(await pool1.liquidityBalance()).to.equal(toWei("999900")) // 1000000 - fee
        }
        {
          // fee = 50000 * 20 * 0.1% = 1000
          await orderBook.connect(broker).fillPositionOrder(4, [])
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("1250", 6)) // + 1000
          expect(await usdc.balanceOf(core.address)).to.equal(toUnit("108950", 6)) // + collateral - fee = 9950 + 100000 - 1000
          expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
          {
            const marketInfo1 = await core.marketState(long1)
            expect(marketInfo1.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
            const marketInfo2 = await core.marketState(short1)
            expect(marketInfo2.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          expect(await pool1.liquidityBalance()).to.equal(toWei("999900")) // unchanged
          {
            const collaterals = await core.listAccountCollaterals(positionId)
            expect(collaterals.collateralAddresses[0]).to.equal(usdc.address)
            expect(collaterals.collateralAmounts[0]).to.equal(toWei("108950")) // collateral - fee = 9950 + 100000 - 1000
            const positions = await core.listAccountPositions(positionId)
            expect(positions.marketIds[0]).to.equal(long1)
            expect(positions.positions[0].size).to.equal(toWei("21"))
            expect(positions.positions[0].entryPrice).to.equal(toWei("50000"))
            expect(positions.positions[0].entryBorrowing).to.equal(toWei("0"))
          }
          {
            const collateralsAndPositions = await core.listAccountCollateralsAndPositionsOf(trader1.address)
            expect(collateralsAndPositions.length).to.equal(1)
            expect(collateralsAndPositions[0].positionId).to.equal(positionId)
            expect(collateralsAndPositions[0].collateralAddresses[0]).to.equal(usdc.address)
            expect(collateralsAndPositions[0].collateralAmounts[0]).to.equal(toWei("108950"))
            expect(collateralsAndPositions[0].positions[0].size).to.equal(toWei("21"))
            expect(collateralsAndPositions[0].positions[0].entryPrice).to.equal(toWei("50000"))
            expect(collateralsAndPositions[0].positions[0].entryBorrowing).to.equal(toWei("0"))
          }
          {
            expect(await pool1.estimatedAumUsd()).to.equal(toWei("1000000"))
          }
          {
            const longPools = await core.listMarketPools(long1)
            expect(longPools[0].backedPool).to.equal(pool1.address)
            expect(longPools[0].totalSize).to.equal(toWei("1"))
            expect(longPools[0].unpaidBorrowingFeeUsd).to.equal(toWei("0"))
            expect(longPools[1].backedPool).to.equal(pool2.address)
            expect(longPools[1].totalSize).to.equal(toWei("0"))
            expect(longPools[1].unpaidBorrowingFeeUsd).to.equal(toWei("0"))
            expect(longPools[2].backedPool).to.equal(pool3.address)
            expect(longPools[2].totalSize).to.equal(toWei("0"))
            expect(longPools[2].unpaidBorrowingFeeUsd).to.equal(toWei("0"))
            const longPoolState = await pool1.marketState(long1)
            expect(longPoolState.isLong).to.equal(true)
            expect(longPoolState.totalSize).to.equal(toWei("1"))
            expect(longPoolState.averageEntryPrice).to.equal(toWei("50000"))
          }
        }
      })

      it("normal profit", async () => {})
      it("normal loss", async () => {})

      // it("TODO: long capped pnl", async () => {
      //     // mlp price should handle capped pnl
      //     // entry value = 2000 * 2 = 4000, maxProfit = 50% = 2000
      //     // assume mark price = 2001
      //     expect(await mlp.totalSupply()).to.equal(toWei("999900"))
      //     expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("3501"), toWei("1")])).to.equal(
      //       toWei("0.997999799979997999")
      //     ) // aum = 999900 - upnl(2000)
      //     // close long, profit in usdc, partial withdraw
      //     const args4 = {
      //       subAccountId: longAccountId,
      //       collateral: toUnit("0", 6),
      //       size: toWei("1"),
      //       price: toWei("3501"),
      //       tpPrice: "0",
      //       slPrice: "0",
      //       expiration: timestampOfTest + 86400 * 4 + 800,
      //       tpslExpiration: timestampOfTest + 86400 * 4 + 800,
      //       profitTokenId: 0,
      //       tpslProfitTokenId: 0,
      //       flags: 0,
      //     }
      //     {
      //       await orderBook.connect(trader1).placePositionOrder(args4, refCode)
      //       expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
      //       expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // unchanged
      //       expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
      //     }
      //     {
      //       // closing entry value = 2000 * 1 = 2000, maxProfit = 50% = 1000
      //       const tx1 = await orderBook
      //         .connect(broker)
      //         .fillPositionOrder(2, toWei("1"), toWei("3501"), [toWei("1"), toWei("3502"), toWei("1")])
      //       await expect(tx1)
      //         .to.emit(pool, "ClosePosition")
      //         .withArgs(
      //           trader1.address,
      //           1, // asset id
      //           [
      //             args4.subAccountId,
      //             0, // collateral id
      //             0, // profit asset id
      //             true, // isLong
      //             args4.size,
      //             toWei("3501"), // trading price
      //             toWei("3502"), // asset price
      //             toWei("1"), // collateral price
      //             toWei("1"), // profit asset price
      //             toWei("0"), // fundingFeeUsd
      //             toWei("3.501"), // pos fee = 3501 * 1 * 0.1%
      //             true, // hasProfit
      //             toWei("1000"), // pnlUsd
      //             toWei("1.0"), // remainPosition
      //             toWei("9996"), // remainCollateral = unchanged, because pnl was sent
      //           ]
      //         )
      //       expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90996.499", 6)) // + withdraw + pnl - fee = 90000 + 0 + 1000 - 3.501
      //       expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("107.501", 6)) // + fee
      //       expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1008896", 6)) // - pnl - withdraw = 1009896 - 1000 - 0
      //       const subAccount = await pool.getSubAccount(longAccountId)
      //       expect(subAccount.collateral).to.equal(toWei("9996")) // 9996 - withdraw
      //       expect(subAccount.size).to.equal(toWei("1"))
      //       expect(subAccount.entryPrice).to.equal(toWei("2000")) // unchanged
      //       expect(subAccount.entryFunding).to.equal(toWei("0.000027397260273972")) // unchanged
      //       const collateralInfo = await pool.getAssetStorageV2(0)
      //       expect(collateralInfo.spotLiquidity).to.equal(toWei("998900")) // 999900 - pnl
      //       const assetInfo = await pool.getAssetStorageV2(1)
      //       expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      //       expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      //       expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      //       expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
      //     }
      //   })
      //   it("ADL a long position", async () => {
      //     // trigger exit = 3800, trigger roe = (3800 - 2000) / 2000 = 90%
      //     // closing entry value = 2000 * 2 = 4000, maxProfit = 50% = 2000
      //     // pnl = (3501 - 2000) * 2 = 3002 > maxProfit
      //     const args4 = {
      //       subAccountId: longAccountId,
      //       size: toWei("2"),
      //       price: toWei("3500"),
      //       profitTokenId: 0,
      //     }
      //     {
      //       await expect(
      //         orderBook.connect(trader1).fillAdlOrder(args4, toWei("3501"), [toWei("1"), toWei("3799"), toWei("1")])
      //       ).to.revertedWith("AccessControl")
      //       await expect(
      //         orderBook.connect(broker).fillAdlOrder(args4, toWei("3501"), [toWei("1"), toWei("3799"), toWei("1")])
      //       ).to.revertedWith("DLA")
      //       const tx1 = orderBook
      //         .connect(broker)
      //         .fillAdlOrder(args4, toWei("3501"), [toWei("1"), toWei("3800"), toWei("1")])
      //       await expect(tx1)
      //         .to.emit(pool, "ClosePosition")
      //         .withArgs(
      //           trader1.address,
      //           1, // asset id
      //           [
      //             args4.subAccountId,
      //             0, // collateral id
      //             0, // profit asset id
      //             true, // isLong
      //             toWei("2"), // amount
      //             toWei("3501"), // trading price
      //             toWei("3800"), // asset price
      //             toWei("1"), // collateral price
      //             toWei("1"), // profit asset price
      //             toWei("0"), // fundingFeeUsd
      //             toWei("7.002"), // pos fee = 3501 * 2 * 0.1%
      //             true, // hasProfit
      //             toWei("2000"), // pnlUsd
      //             toWei("0"), // remainPosition
      //             toWei("9996"), // remainCollateral = unchanged, because pnl was sent
      //           ]
      //         )
      //       expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("101988.998", 6)) // + withdraw + pnl - fee = 90000 + 9996 + 2000 - 7.002
      //       expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("111.002", 6)) // + fee
      //       expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("997900", 6)) // - pnl - withdraw = 1009896 - 2000 - 9996
      //       const subAccount = await pool.getSubAccount(longAccountId)
      //       expect(subAccount.collateral).to.equal(toWei("0"))
      //       expect(subAccount.size).to.equal(toWei("0"))
      //       expect(subAccount.entryPrice).to.equal(toWei("0"))
      //       expect(subAccount.entryFunding).to.equal(toWei("0"))
      //       const collateralInfo = await pool.getAssetStorageV2(0)
      //       expect(collateralInfo.spotLiquidity).to.equal(toWei("997900")) // = pool balance
      //       const assetInfo = await pool.getAssetStorageV2(1)
      //       expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      //       expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      //       expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      //       expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      //     }
      //   })
      //   it("withdraw collateral", async () => {
      //     // update funding
      //     // funding = skew / alpha * beta = $4000 / 20000 * apy 20% = apy 4%, borrowing = apy 1%
      //     await time.increaseTo(timestampOfTest + 86400 * 2 + 86400)
      //     // withdraw
      //     {
      //       await expect(
      //         orderBook
      //           .connect(trader1)
      //           .placeWithdrawalOrder({
      //             subAccountId: longAccountId,
      //             rawAmount: toUnit("0", 6),
      //             profitTokenId: 0,
      //             isProfit: false,
      //           })
      //       ).to.revertedWith("A=0")
      //       await expect(
      //         orderBook
      //           .connect(trader1)
      //           .placeWithdrawalOrder({
      //             subAccountId: longAccountId,
      //             rawAmount: toUnit("1", 6),
      //             profitTokenId: 0,
      //             isProfit: false,
      //           })
      //       )
      //         .to.emit(orderBook, "NewWithdrawalOrder")
      //         .withArgs(trader1.address, 2, [longAccountId, toUnit("1", 6), 0, false])
      //       expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
      //       expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // unchanged
      //       expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6)) // unchanged
      //       expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
      //       const collateralInfo = await pool.getAssetStorageV2(0)
      //       expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // unchanged
      //     }
      //     {
      //       // longCumulativeFunding, 0.000027397260273972 + 0.05 * 1 / 365 = 0.000164383561643835013698630136986
      //       // fundingFee = 2000 * 2 * 0.05 * 1 / 365 = 0.547945205479452054794520547945
      //       // pnl = (2100 - 2000) * 2 = 200
      //       await expect(
      //         orderBook.connect(trader1).fillWithdrawalOrder(2, [toWei("1"), toWei("2100"), toWei("1")])
      //       ).to.revertedWith("AccessControl")
      //       await orderBook.connect(broker).fillWithdrawalOrder(2, [toWei("1"), toWei("2100"), toWei("1")])
      //       const assetInfo = await pool.getAssetStorageV2(1)
      //       expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      //       expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      //       expect(assetInfo.totalLongPosition).to.equal(toWei("2"))
      //       expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
      //       expect(assetInfo.longCumulativeFunding).to.equal(toWei("0.000164383561643834"))
      //       expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90001", 6)) // +withdraw = +1
      //       expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104.547945", 6)) // + fee = 104 + 0.547945205479452054794520547945
      //       expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      //       expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009894.452055", 6)) // -withdraw - fee = 1009896 - 1 - 0.547945205479452054794520547945
      //       const subAccount = await pool.getSubAccount(longAccountId)
      //       expect(subAccount.collateral).to.equal(toWei("9994.452054794520552000")) // 9996 - fundingFee - withdraw
      //       expect(subAccount.size).to.equal(toWei("2"))
      //       expect(subAccount.entryPrice).to.equal(toWei("2000")) // unchanged
      //       expect(subAccount.entryFunding).to.equal(toWei("0.000164383561643834")) // update to new
      //       const collateralInfo = await pool.getAssetStorageV2(0)
      //       expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // unchanged
      //     }
      //   })
      //   describe("add liquidity on token 2", () => {
      //     beforeEach(async () => {
      //       // +liq usdt
      //       await usdt.connect(lp1).transfer(orderBook.address, toUnit("1000000", 6))
      //       {
      //         const args = { assetId: 2, rawAmount: toUnit("1000000", 6), isAdding: true }
      //         await orderBook.connect(lp1).placeLiquidityOrder(args)
      //       }
      //       {
      //         await time.increaseTo(timestampOfTest + 86400 * 2 + 660)
      //         await expect(
      //           orderBook.connect(broker).fillLiquidityOrder(2, [toWei("1"), toWei("2000"), toWei("1")])
      //         ).to.revertedWith("LCP")
      //         {
      //           const { keys, values } = getPoolConfigs([
      //             { k: LIQUIDITY_CAP_USD_KEY, v: toWei("2000000"), old: toWei("0") },
      //           ])
      //           await pool.setPoolParameters(keys, values, [])
      //         }
      //         await orderBook.connect(broker).fillLiquidityOrder(2, [toWei("1"), toWei("2000"), toWei("1")])
      //         expect(await usdt.balanceOf(feeDistributor.address)).to.equal(toUnit("100", 6)) // fee = 1000000 * 0.01% = 100
      //         expect(await usdt.balanceOf(pool.address)).to.equal(toUnit("999900", 6))
      //         const collateralInfo = await pool.getAssetStorageV2(0)
      //         expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // unchanged
      //         const collateral2Info = await pool.getAssetStorageV2(2)
      //         expect(collateral2Info.spotLiquidity).to.equal(toWei("999900")) // 1000000 - fee
      //         const assetInfo = await pool.getAssetStorageV2(1)
      //         expect(assetInfo.longCumulativeFunding).to.equal(toWei("0.000027397260273972"))
      //         expect(assetInfo.shortCumulativeFunding).to.equal(toWei("0.000027397260273972"))
      //       }
      //       expect(await mlp.totalSupply()).to.equal(toWei("1999800")) // 999900 + 999900
      //       expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("2000"), toWei("1")])).to.equal(toWei("1")) // aum = 1999800
      //     })
      //     it("take profit from token 2, but token 2 can not afford funding", async () => {
      //       // close long, profit in usdt, partial withdraw
      //       const args4 = {
      //         subAccountId: longAccountId,
      //         collateral: toUnit("0", 6),
      //         size: toWei("1"),
      //         price: toWei("2000.1"),
      //         tpPrice: "0",
      //         slPrice: "0",
      //         expiration: timestampOfTest + 86400 * 4 + 800,
      //         tpslExpiration: timestampOfTest + 86400 * 4 + 800,
      //         profitTokenId: 2, // notice here
      //         tpslProfitTokenId: 0,
      //         flags: 0,
      //       }
      //       {
      //         await orderBook.connect(trader1).placePositionOrder(args4, refCode)
      //         expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
      //         expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // unchanged
      //         expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
      //       }
      //       // update funding
      //       // funding = skew / alpha * beta = $4000 / 20000 * apy 20% = apy 4%, borrowing = apy 1%
      //       await time.increaseTo(timestampOfTest + 86400 * 2 + 86400)
      //       {
      //         // longCumulativeFunding, 0.000027397260273972 + 0.05 * 1 / 365 = 0.000164383561643835013698630136986
      //         // fundingFee = 2000 * 2 * 0.05 * 1 / 365 = 0.547945205479452054794520547945
      //         // pnl = (2000.1 - 2000) * 1 = 0.1
      //         const tx1 = await orderBook
      //           .connect(broker)
      //           .fillPositionOrder(3, toWei("1"), toWei("2000.1"), [toWei("1"), toWei("2000"), toWei("1")])
      //         await expect(tx1)
      //           .to.emit(pool, "ClosePosition")
      //           .withArgs(
      //             trader1.address,
      //             1, // asset id
      //             [
      //               args4.subAccountId,
      //               0, // collateral id
      //               2, // profit asset id
      //               true, // isLong
      //               args4.size,
      //               toWei("2000.1"), // trading price
      //               toWei("2000"), // asset price
      //               toWei("1"), // collateral price
      //               toWei("1"), // profit asset price
      //               toWei("0.547945205479448000"), // fundingFeeUsd
      //               toWei("2.548045205479448000"), // 2000.1 * 1 * 0.1% + 0.547945205479452054794520547945, where 0.1 is usdt
      //               true, // hasProfit
      //               toWei("0.1"), // pnlUsd
      //               toWei("1.0"), // remainPosition
      //               toWei("9993.551954794520552000"), // remainCollateral = original - (fee - pnl) = 9996 - (2.548045205479448000 - 0.1)
      //             ]
      //           )
      //         expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged because profit can not afford fees
      //         expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("106.448045", 6)) // + fee = 104 + 2.548045205479448000 - 0.1 is usdt
      //         expect(await usdt.balanceOf(feeDistributor.address)).to.equal(toUnit("100.1", 6)) // profit = 100 + 0.1
      //         expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009893.551955", 6)) // - withdraw - (fee - 0.1) = 1009896 - (2.548045205479448000 - 0.1)
      //         expect(await usdt.balanceOf(pool.address)).to.equal(toUnit("999899.9", 6)) // - pnl = 999900 - 0.1
      //         const subAccount = await pool.getSubAccount(longAccountId)
      //         expect(subAccount.collateral).to.equal(toWei("9993.55195479452055200")) // 9996 - withdraw - (fee - 0.1) = 9996 - (2.548045205479448000 - 0.1)
      //         expect(subAccount.size).to.equal(toWei("1"))
      //         expect(subAccount.entryPrice).to.equal(toWei("2000")) // unchanged
      //         expect(subAccount.entryFunding).to.equal(toWei("0.000164383561643834")) // unchanged
      //         const collateralInfo = await pool.getAssetStorageV2(0)
      //         expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // unchanged
      //         const collateral2Info = await pool.getAssetStorageV2(2)
      //         expect(collateral2Info.spotLiquidity).to.equal(toWei("999899.9")) // - pnl
      //         const assetInfo = await pool.getAssetStorageV2(1)
      //         expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      //         expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      //         expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
      //         expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
      //       }
      //     })
      //   })
    }) // long a little and test more

    describe("TODO: short a little and test more", () => {
      let shortAccountId = ""
      beforeEach(async () => {
        //     shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
        //     // open short xxx, using usdc
        //     await usdc.connect(trader1).transfer(orderBook.address, toUnit("10000", 6))
        //     const args2 = {
        //       subAccountId: shortAccountId,
        //       collateral: toUnit("10000", 6),
        //       size: toWei("2"),
        //       price: toWei("2000"),
        //       tpPrice: "0",
        //       slPrice: "0",
        //       expiration: timestampOfTest + 86400 * 2 + 800,
        //       tpslExpiration: timestampOfTest + 86400 * 2 + 800,
        //       profitTokenId: 0,
        //       tpslProfitTokenId: 0,
        //       flags: PositionOrderFlags.OpenPosition,
        //     }
        //     {
        //       await orderBook.connect(trader1).placePositionOrder(args2, refCode)
        //       expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // - 10000
        //       expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("100", 6)) // unchanged
        //       expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999900", 6)) // unchanged
        //       const collateralInfo = await pool.getAssetStorageV2(0)
        //       expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // unchanged
        //     }
        //     {
        //       await orderBook
        //         .connect(broker)
        //         .fillPositionOrder(1, toWei("2"), toWei("2000"), [toWei("1"), toWei("2000"), toWei("1")])
        //       expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
        //       expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // + 4
        //       expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // + collateral - fee = 999900 + 10000 - 4
        //       const subAccount = await pool.getSubAccount(shortAccountId)
        //       expect(subAccount.collateral).to.equal(toWei("9996")) // fee = 4
        //       expect(subAccount.size).to.equal(toWei("2"))
        //       expect(subAccount.entryPrice).to.equal(toWei("2000"))
        //       expect(subAccount.entryFunding).to.equal(toWei("0.000027397260273972"))
        //       const collateralInfo = await pool.getAssetStorageV2(0)
        //       expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // unchanged
        //       const assetInfo = await pool.getAssetStorageV2(1)
        //       expect(assetInfo.totalShortPosition).to.equal(toWei("2"))
        //       expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
        //       expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
        //       expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
        //     }
      })
      //   it("short capped pnl", async () => {
      //     // mlp price should handle capped pnl
      //     // entry value = 2000 * 2 = 4000, maxProfit = 50% = 2000
      //     // assume mark price = 999
      //     expect(await mlp.totalSupply()).to.equal(toWei("999900"))
      //     expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("999"), toWei("1")])).to.equal(
      //       toWei("0.997999799979997999")
      //     ) // aum = 999900 - upnl(2000)
      //     // close long, profit in usdc, partial withdraw
      //     const args4 = {
      //       subAccountId: shortAccountId,
      //       collateral: toUnit("0", 6),
      //       size: toWei("1"),
      //       price: toWei("999"),
      //       tpPrice: "0",
      //       slPrice: "0",
      //       expiration: timestampOfTest + 86400 * 4 + 800,
      //       tpslExpiration: timestampOfTest + 86400 * 4 + 800,
      //       profitTokenId: 0,
      //       tpslProfitTokenId: 0,
      //       flags: 0,
      //     }
      //     {
      //       await orderBook.connect(trader1).placePositionOrder(args4, refCode)
      //       expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
      //       expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // unchanged
      //       expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
      //     }
      //     {
      //       // closing entry value = 2000 * 1 = 2000, maxProfit = 50% = 1000
      //       const tx1 = await orderBook
      //         .connect(broker)
      //         .fillPositionOrder(2, toWei("1"), toWei("999"), [toWei("1"), toWei("998"), toWei("1")])
      //       await expect(tx1)
      //         .to.emit(pool, "ClosePosition")
      //         .withArgs(
      //           trader1.address,
      //           1, // asset id
      //           [
      //             args4.subAccountId,
      //             0, // collateral id
      //             0, // profit asset id
      //             false, // isLong
      //             args4.size,
      //             toWei("999"), // trading price
      //             toWei("998"), // asset price
      //             toWei("1"), // collateral price
      //             toWei("1"), // profit asset price
      //             toWei("0"), // fundingFeeUsd
      //             toWei("0.999"), // pos fee = 999 * 1 * 0.1%
      //             true, // hasProfit
      //             toWei("1000"), // pnlUsd
      //             toWei("1.0"), // remainPosition
      //             toWei("9996"), // remainCollateral = unchanged, because pnl was sent
      //           ]
      //         )
      //       expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90999.001", 6)) // + withdraw + pnl - fee = 90000 + 0 + 1000 - 0.999
      //       expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104.999", 6)) // + fee
      //       expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1008896", 6)) // - pnl - withdraw = 1009896 - 1000 - 0
      //       const subAccount = await pool.getSubAccount(shortAccountId)
      //       expect(subAccount.collateral).to.equal(toWei("9996")) // 9996 - withdraw
      //       expect(subAccount.size).to.equal(toWei("1"))
      //       expect(subAccount.entryPrice).to.equal(toWei("2000")) // unchanged
      //       expect(subAccount.entryFunding).to.equal(toWei("0.000027397260273972")) // unchanged
      //       const collateralInfo = await pool.getAssetStorageV2(0)
      //       expect(collateralInfo.spotLiquidity).to.equal(toWei("998900")) // 999900 - pnl
      //       const assetInfo = await pool.getAssetStorageV2(1)
      //       expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      //       expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      //       expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      //       expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      //     }
      //   })
      //   it("liquidate because of funding", async () => {
      //     // skew = (2 - 0) * 2000 = $4000, pnl = 0
      //     // funding = skew / alpha * beta = $4000 / 20000 * apy 20% = apy 4%, borrowing = apy 1%
      //     // mm = 2000 * 2 * 0.05 = 200 (MM unsafe)
      //     // liquidate time = 48 years + 357 days + 17 hours
      //     // funding/borrowing = 2000 * 2 * 0.05 * (48 + 357/365 + 17/24/365) = 9796.00
      //     // collateral = 9996 - 0 - 9796.00 = 199.99 < 200
      //     //
      //     // update funding to 1 hour before liquidate
      //     {
      //       await time.increaseTo(timestampOfTest + 86400 * 2 + 48 * 365 * 86400 + 357 * 86400 + 16 * 3600)
      //       const tx1 = await orderBook.connect(broker).updateFundingState()
      //       await expect(tx1).to.emit(pool, "UpdateFundingRate").withArgs(
      //         1, // tokenId
      //         false, // isPositiveFundingRate
      //         rate("0.04"), // newFundingRateApy
      //         rate("0.01"), // newBorrowingRateApy
      //         toWei("0.489826484018264839"), // longCumulativeFunding, 0.000027397260273972 + 0.01 * (48 + 357/365 + 16/24/365)
      //         toWei("2.449022831050228309") // shortCumulativeFunding, 0.000027397260273972 + 0.05 * (48 + 357/365 + 16/24/365)
      //       )
      //       const assetInfo = await pool.getAssetStorageV2(1)
      //       expect(assetInfo.longCumulativeFunding).to.equal(toWei("0.489826484018264839"))
      //       expect(assetInfo.shortCumulativeFunding).to.equal(toWei("2.449022831050228309"))
      //       expect(assetInfo.totalShortPosition).to.equal(toWei("2"))
      //       expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      //       expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      //       expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      //     }
      //     await expect(
      //       orderBook.connect(broker).liquidate(shortAccountId, 0, toWei("2000"), [toWei("1"), toWei("2000"), toWei("1")])
      //     ).to.revertedWith("MMS")
      //     // update funding
      //     {
      //       await time.increaseTo(timestampOfTest + 86400 * 2 + 48 * 365 * 86400 + 357 * 86400 + 17 * 3600)
      //       const tx1 = await orderBook.connect(broker).updateFundingState()
      //       await expect(tx1).to.emit(pool, "UpdateFundingRate").withArgs(
      //         1, // tokenId
      //         false, // isPositiveFundingRate
      //         rate("0.04"), // newFundingRateApy
      //         rate("0.01"), // newBorrowingRateApy
      //         toWei("0.489827625570776254"), // longCumulativeFunding, 0.000027397260273972 + 0.01 * (48 + 357/365 + 17/24/365)
      //         toWei("2.449028538812785386") // shortCumulativeFunding, 0.000027397260273972 + 0.05 * (48 + 357/365 + 17/24/365)
      //       )
      //       const assetInfo = await pool.getAssetStorageV2(1)
      //       expect(assetInfo.longCumulativeFunding).to.equal(toWei("0.489827625570776254"))
      //       expect(assetInfo.shortCumulativeFunding).to.equal(toWei("2.449028538812785386"))
      //       expect(assetInfo.totalShortPosition).to.equal(toWei("2"))
      //       expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      //       expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      //       expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      //     }
      //     {
      //       await expect(
      //         orderBook
      //           .connect(broker)
      //           .liquidate(shortAccountId, 0, toWei("2000"), [toWei("1"), toWei("2000"), toWei("1")])
      //       )
      //         .to.emit(pool, "Liquidate")
      //         .withArgs(trader1.address, 1, [
      //           shortAccountId,
      //           0, // collateralId
      //           0, // profitAssetId
      //           false, // isLong
      //           toWei("2"), // amount
      //           toWei("2000"), // tradingPrice
      //           toWei("2000"), // assetPrice
      //           toWei("1"), // collateralPrice
      //           toWei("1"), // profitAssetPrice
      //           toWei("9796.004566210045656"), // fundingFeeUsd =  2000 * 2 * 0.05 * (48 + 357/365 + 17/24/365)
      //           toWei("9804.004566210045656000"), // feeUsd = 2000 * 2 * (0.002 + 0.05 * (48 + 357/365 + 17/24/365))
      //           false, // hasProfit
      //           toWei("0"), // pnlUsd. (2000 - 2000) * 2
      //           toWei("191.995433789954344000"), // remainCollateral. 9996 + pnl - fee
      //         ])
      //       expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90191.995433", 6)) // 90000 + remainCollateral
      //       expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      //       expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999900.000001", 6)) // 1009896 - fee - remainCollateral = original liquidity (because collateral can afford)
      //       const subAccount = await pool.getSubAccount(shortAccountId)
      //       expect(subAccount.collateral).to.equal(toWei("0"))
      //       expect(subAccount.size).to.equal(toWei("0"))
      //       expect(subAccount.entryPrice).to.equal(toWei("0"))
      //       expect(subAccount.entryFunding).to.equal(toWei("0"))
      //       const collateralInfo = await pool.getAssetStorageV2(0)
      //       expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // = pool balance
      //       const assetInfo = await pool.getAssetStorageV2(1)
      //       expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      //       expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      //       expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      //       expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      //     }
      //   })
      //   it("0 < fee < margin < MM. liquidate short", async () => {
      //     // liquidate time = 48 years + 357 days + 17 hours
      //     // funding/borrowing = 0
      //     // collateral = 9996 + (2000 - 6664.8) * 2 - 0 = 666.40
      //     // mm = 6664.8 * 2 * 0.05 = 666.48
      //     await expect(
      //       orderBook
      //         .connect(broker)
      //         .liquidate(shortAccountId, 0, toWei("6665"), [toWei("1"), toWei("6664.7"), toWei("1")])
      //     ).to.revertedWith("MMS")
      //     await expect(
      //       orderBook
      //         .connect(broker)
      //         .liquidate(shortAccountId, 0, toWei("6665"), [toWei("1"), toWei("6664.8"), toWei("1")])
      //     )
      //       .to.emit(pool, "Liquidate")
      //       .withArgs(trader1.address, 1, [
      //         shortAccountId,
      //         0, // collateralId
      //         0, // profitAssetId
      //         false, // isLong
      //         toWei("2"), // amount
      //         toWei("6665"), // tradingPrice
      //         toWei("6664.8"), // assetPrice
      //         toWei("1"), // collateralPrice
      //         toWei("1"), // profitAssetPrice
      //         toWei("0"), // fundingFeeUsd
      //         toWei("26.66"), // feeUsd = 6665 * 2 * 0.002 = 26.66
      //         false, // hasProfit
      //         toWei("9330"), // pnlUsd. (2000 - 6665) * 2
      //         toWei("639.34"), // remainCollateral. 9996 + pnl - fee
      //       ])
      //     expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90639.34", 6)) // 90000 + remainCollateral
      //     expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      //     expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009230", 6)) // 1009896 - fee - remainCollateral
      //     const subAccount = await pool.getSubAccount(shortAccountId)
      //     expect(subAccount.collateral).to.equal(toWei("0"))
      //     expect(subAccount.size).to.equal(toWei("0"))
      //     expect(subAccount.entryPrice).to.equal(toWei("0"))
      //     expect(subAccount.entryFunding).to.equal(toWei("0"))
      //     const collateralInfo = await pool.getAssetStorageV2(0)
      //     expect(collateralInfo.spotLiquidity).to.equal(toWei("1009230")) // = pool balance
      //     const assetInfo = await pool.getAssetStorageV2(1)
      //     expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      //     expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      //     expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      //     expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      //   })
      //   it("0 < margin < fee < MM. liquidate short", async () => {
      //     // collateral + pnl = 9996 + (2000 - 6993) * 2 = 10 < fee
      //     await expect(
      //       orderBook
      //         .connect(broker)
      //         .liquidate(shortAccountId, 0, toWei("6993"), [toWei("1"), toWei("6664.8"), toWei("1")])
      //     )
      //       .to.emit(pool, "Liquidate")
      //       .withArgs(trader1.address, 1, [
      //         shortAccountId,
      //         0, // collateralId
      //         0, // profitAssetId
      //         false, // isLong
      //         toWei("2"), // amount
      //         toWei("6993"), // tradingPrice
      //         toWei("6664.8"), // assetPrice
      //         toWei("1"), // collateralPrice
      //         toWei("1"), // profitAssetPrice
      //         toWei("0"), // fundingFeeUsd
      //         toWei("10"), // feeUsd = 6993 * 2 * 0.002 = 27.972, but capped by remain collateral
      //         false, // hasProfit
      //         toWei("9986"), // pnlUsd. (2000 - 6665) * 2
      //         toWei("0"), // remainCollateral
      //       ])
      //     expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
      //     expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      //     expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009886", 6)) // 1009896 - fee - remainCollateral
      //     const subAccount = await pool.getSubAccount(shortAccountId)
      //     expect(subAccount.collateral).to.equal(toWei("0"))
      //     expect(subAccount.size).to.equal(toWei("0"))
      //     expect(subAccount.entryPrice).to.equal(toWei("0"))
      //     expect(subAccount.entryFunding).to.equal(toWei("0"))
      //     const collateralInfo = await pool.getAssetStorageV2(0)
      //     expect(collateralInfo.spotLiquidity).to.equal(toWei("1009886")) // = pool balance
      //     const assetInfo = await pool.getAssetStorageV2(1)
      //     expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      //     expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      //     expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      //     expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      //   })
      //   it("margin < 0. liquidate short", async () => {
      //     // collateral + pnl = 9996 + (2000 - 7000) * 2 = -4 < 0
      //     await expect(
      //       orderBook
      //         .connect(broker)
      //         .liquidate(shortAccountId, 0, toWei("7000"), [toWei("1"), toWei("6664.8"), toWei("1")])
      //     )
      //       .to.emit(pool, "Liquidate")
      //       .withArgs(trader1.address, 1, [
      //         shortAccountId,
      //         0, // collateralId
      //         0, // profitAssetId
      //         false, // isLong
      //         toWei("2"), // amount
      //         toWei("7000"), // tradingPrice
      //         toWei("6664.8"), // assetPrice
      //         toWei("1"), // collateralPrice
      //         toWei("1"), // profitAssetPrice
      //         toWei("0"), // fundingFeeUsd
      //         toWei("0"), // feeUsd
      //         false, // hasProfit
      //         toWei("9996"), // pnlUsd. all of collateral
      //         toWei("0"), // remainCollateral
      //       ])
      //     expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
      //     expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      //     expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
      //     const subAccount = await pool.getSubAccount(shortAccountId)
      //     expect(subAccount.collateral).to.equal(toWei("0"))
      //     expect(subAccount.size).to.equal(toWei("0"))
      //     expect(subAccount.entryPrice).to.equal(toWei("0"))
      //     expect(subAccount.entryFunding).to.equal(toWei("0"))
      //     const collateralInfo = await pool.getAssetStorageV2(0)
      //     expect(collateralInfo.spotLiquidity).to.equal(toWei("1009896")) // = pool balance
      //     const assetInfo = await pool.getAssetStorageV2(1)
      //     expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      //     expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      //     expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      //     expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      //   })
      //   describe("add chainlink", () => {
      //     let mockChainlink: MockChainlink
      //     beforeEach(async () => {
      //       mockChainlink = (await createContract("MockChainlink")) as MockChainlink
      //       await mockChainlink.setAnswer(toChainlink("1.0"))
      //       {
      //         const { keys, values, currentValues } = getPoolConfigs([
      //           { k: REFERENCE_ORACLE_KEY, v: mockChainlink.address, old: "0" },
      //           { k: REFERENCE_DEVIATION_KEY, v: rate("0"), old: "0" },
      //           { k: REFERENCE_ORACLE_TYPE_KEY, v: ReferenceOracleType.Chainlink, old: "0" },
      //         ])
      //         await pool.setAssetParameters(0, keys, values, currentValues)
      //       }
      //     })
      //     it("strict stable price dampener. ignore broker price", async () => {
      //       await mockChainlink.setAnswer(toChainlink("0.999"))
      //       // mlp price should handle capped pnl
      //       // entry value = 2000 * 2 = 4000, maxProfit = 50% = 2000
      //       // assume mark price = 999
      //       expect(await mlp.totalSupply()).to.equal(toWei("999900"))
      //       expect(await pool.callStatic.getMlpPrice([toWei("0.99"), toWei("999"), toWei("0.99")])).to.equal(
      //         toWei("0.997999799979997999")
      //       ) // aum = 999900 - upnl(2000)
      //       // close long, profit in usdc, partial withdraw
      //       const args4 = {
      //         subAccountId: shortAccountId,
      //         collateral: toUnit("0", 6),
      //         size: toWei("1"),
      //         price: toWei("999"),
      //         tpPrice: "0",
      //         slPrice: "0",
      //         expiration: timestampOfTest + 86400 * 4 + 800,
      //         tpslExpiration: timestampOfTest + 86400 * 4 + 800,
      //         profitTokenId: 0,
      //         tpslProfitTokenId: 0,
      //         flags: 0,
      //       }
      //       {
      //         await orderBook.connect(trader1).placePositionOrder(args4, refCode)
      //         expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
      //         expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // unchanged
      //         expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
      //       }
      //       {
      //         // closing entry value = 2000 * 1 = 2000, maxProfit = 50% = 1000
      //         const tx1 = await orderBook
      //           .connect(broker)
      //           .fillPositionOrder(2, toWei("1"), toWei("999"), [toWei("0.99"), toWei("998"), toWei("0.99")])
      //         await expect(tx1)
      //           .to.emit(pool, "ClosePosition")
      //           .withArgs(
      //             trader1.address,
      //             1, // asset id
      //             [
      //               args4.subAccountId,
      //               0, // collateral id
      //               0, // profit asset id
      //               false, // isLong
      //               args4.size,
      //               toWei("999"), // trading price
      //               toWei("998"), // asset price
      //               toWei("1"), // collateral price. important!
      //               toWei("1"), // profit asset price
      //               toWei("0"), // fundingFeeUsd
      //               toWei("0.999"), // pos fee = 999 * 1 * 0.1%
      //               true, // hasProfit
      //               toWei("1000"), // pnlUsd
      //               toWei("1.0"), // remainPosition
      //               toWei("9996"), // remainCollateral = unchanged, because pnl was sent
      //             ]
      //           )
      //         expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90999.001", 6)) // + withdraw + pnl - fee = 90000 + 0 + 1000 - 0.999
      //         expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104.999", 6)) // + fee
      //         expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1008896", 6)) // - pnl - withdraw = 1009896 - 1000 - 0
      //         const subAccount = await pool.getSubAccount(shortAccountId)
      //         expect(subAccount.collateral).to.equal(toWei("9996")) // 9996 - withdraw
      //         expect(subAccount.size).to.equal(toWei("1"))
      //         expect(subAccount.entryPrice).to.equal(toWei("2000")) // unchanged
      //         expect(subAccount.entryFunding).to.equal(toWei("0.000027397260273972")) // unchanged
      //         const collateralInfo = await pool.getAssetStorageV2(0)
      //         expect(collateralInfo.spotLiquidity).to.equal(toWei("998900")) // 999900 - pnl
      //         const assetInfo = await pool.getAssetStorageV2(1)
      //         expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      //         expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      //         expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      //         expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      //       }
      //     })
      //     it("strict stable price dampener. use broker price", async () => {
      //       await mockChainlink.setAnswer(toChainlink("0.99"))
      //       // mlp price should handle capped pnl
      //       // entry value = 2000 * 2 = 4000, maxProfit = 50% = 2000
      //       // assume mark price = 999
      //       expect(await mlp.totalSupply()).to.equal(toWei("999900"))
      //       expect(await pool.callStatic.getMlpPrice([toWei("0.99"), toWei("999"), toWei("0.99")])).to.equal(
      //         toWei("0.987999799979997999")
      //       ) // aum = 999900 * 0.99 - upnl(2000)
      //       // close long, profit in usdc, partial withdraw
      //       const args4 = {
      //         subAccountId: shortAccountId,
      //         collateral: toUnit("0", 6),
      //         size: toWei("1"),
      //         price: toWei("999"),
      //         tpPrice: "0",
      //         slPrice: "0",
      //         expiration: timestampOfTest + 86400 * 4 + 800,
      //         tpslExpiration: timestampOfTest + 86400 * 4 + 800,
      //         profitTokenId: 0,
      //         tpslProfitTokenId: 0,
      //         flags: 0,
      //       }
      //       {
      //         await orderBook.connect(trader1).placePositionOrder(args4, refCode)
      //         expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
      //         expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // unchanged
      //         expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
      //       }
      //       {
      //         // closing entry value = 2000 * 1 = 2000, maxProfit = 50% = 1000
      //         const tx1 = await orderBook
      //           .connect(broker)
      //           .fillPositionOrder(2, toWei("1"), toWei("999"), [toWei("0.999"), toWei("998"), toWei("0.999")])
      //         await expect(tx1)
      //           .to.emit(pool, "ClosePosition")
      //           .withArgs(
      //             trader1.address,
      //             1, // asset id
      //             [
      //               args4.subAccountId,
      //               0, // collateral id
      //               0, // profit asset id
      //               false, // isLong
      //               args4.size,
      //               toWei("999"), // trading price
      //               toWei("998"), // asset price
      //               toWei("0.99"), // collateral price. important!
      //               toWei("0.99"), // profit asset price
      //               toWei("0"), // fundingFeeUsd
      //               toWei("0.999"), // pos fee = 999 * 1 * 0.1%
      //               true, // hasProfit
      //               toWei("1000"), // pnlUsd
      //               toWei("1.0"), // remainPosition
      //               toWei("9996"), // remainCollateral = unchanged, because pnl was sent
      //             ]
      //           )
      //         expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("91009.091919", 6)) // + withdraw + pnl/collateralPrice - fee/collateralPrice = 90000 + 0 + 1000/0.99 - 0.999/0.99
      //         expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("105.009090", 6)) // + fee/collateralPrice = 0.999 / 0.99
      //         expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1008885.898991", 6)) // - pnl - withdraw = 1009896 - 1000/0.99 - 0
      //         const subAccount = await pool.getSubAccount(shortAccountId)
      //         expect(subAccount.collateral).to.equal(toWei("9996")) // 9996 - withdraw
      //         expect(subAccount.size).to.equal(toWei("1"))
      //         expect(subAccount.entryPrice).to.equal(toWei("2000")) // unchanged
      //         expect(subAccount.entryFunding).to.equal(toWei("0.000027397260273972")) // unchanged
      //         const collateralInfo = await pool.getAssetStorageV2(0)
      //         expect(collateralInfo.spotLiquidity).to.equal(toWei("998889.898989898989898990")) // 999900 - pnl = 999900 - 1000/0.99
      //         const assetInfo = await pool.getAssetStorageV2(1)
      //         expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      //         expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      //         expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      //         expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      //       }
      //     })
      //   })
    }) // short a little and test more

    // it("TODO: remove liquidity cause reserved > spotLiquidity", async () => {
    //   {
    //     const collateralInfo = await pool.getAssetStorageV2(0)
    //     expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // 1000000 - fee
    //   }
    //   // open long xxx, using usdc
    //   const longAccountId = assembleSubAccountId(trader1.address, 0, 1, true)
    //   await usdc.connect(trader1).transfer(orderBook.address, toUnit("100000", 6))
    //   const args2 = {
    //     subAccountId: longAccountId,
    //     collateral: toUnit("100000", 6),
    //     size: toWei("900000"),
    //     price: toWei("1"),
    //     tpPrice: "0",
    //     slPrice: "0",
    //     expiration: timestampOfTest + 86400 * 2 + 800,
    //     tpslExpiration: timestampOfTest + 86400 * 2 + 800,
    //     profitTokenId: 0,
    //     tpslProfitTokenId: 0,
    //     flags: PositionOrderFlags.OpenPosition,
    //   }
    //   await orderBook.connect(trader1).placePositionOrder(args2, refCode)
    //   await orderBook
    //     .connect(broker)
    //     .fillPositionOrder(1, toWei("900000"), toWei("1"), [toWei("1"), toWei("1"), toWei("1")])
    //   expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1"), toWei("1")])).to.equal(toWei("1"))
    //   // reserve 900,000 * 80%, liquidity 999,900, can remove 279,900
    //   {
    //     await mlp.connect(lp1).transfer(orderBook.address, toWei("279901"))
    //     const args = { assetId: 0, rawAmount: toWei("279901"), isAdding: false }
    //     await time.increaseTo(timestampOfTest + 86400 * 2 + 500)
    //     await orderBook.connect(lp1).placeLiquidityOrder(args)
    //     await time.increaseTo(timestampOfTest + 86400 * 2 + 500 + 1800)
    //     await expect(
    //       orderBook.connect(broker).fillLiquidityOrder(2, [toWei("1"), toWei("1"), toWei("1")])
    //     ).to.revertedWith("RSV")
    //     await orderBook.connect(lp1).cancelOrder(2)
    //   }
    //   {
    //     await mlp.connect(lp1).transfer(orderBook.address, toWei("279900"))
    //     const args = { assetId: 0, rawAmount: toWei("279900"), isAdding: false }
    //     await orderBook.connect(lp1).placeLiquidityOrder(args)
    //     await time.increaseTo(timestampOfTest + 86400 * 2 + 500 + 1800 + 1800)
    //     await orderBook.connect(broker).fillLiquidityOrder(3, [toWei("1"), toWei("1"), toWei("1")])
    //   }
    // })
    // it("TODO: tp/sl strategy", async () => {
    //   // open long, tp/sl strategy takes effect when fill
    //   const longAccountId = assembleSubAccountId(trader1.address, 0, 1, true)
    //   await usdc.connect(trader1).transfer(orderBook.address, toUnit("10000", 6))
    //   const args2 = {
    //     subAccountId: longAccountId,
    //     collateral: toUnit("10000", 6),
    //     size: toWei("2"),
    //     price: toWei("2000"),
    //     tpPrice: toWei("2200"),
    //     slPrice: toWei("1800"),
    //     expiration: timestampOfTest + 86400 * 2 + 800,
    //     tpslExpiration: timestampOfTest + 86400 * 2 + 1000,
    //     profitTokenId: 0,
    //     tpslProfitTokenId: 2,
    //     flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder + PositionOrderFlags.TpSlStrategy,
    //   }
    //   await orderBook.connect(trader1).placePositionOrder(args2, refCode)
    //   const tx2 = await orderBook
    //     .connect(broker)
    //     .fillPositionOrder(1, toWei("2"), toWei("2000"), [toWei("1"), toWei("2000"), toWei("1")])
    //   await expect(tx2)
    //     .to.emit(orderBook, "NewPositionOrder")
    //     .withArgs(trader1.address, 2, [
    //       args2.subAccountId,
    //       toWei("0"), // collateral
    //       args2.size,
    //       toWei("2200"), // price
    //       toWei("0"), // tpPrice
    //       toWei("0"), // slPrice
    //       timestampOfTest + 86400 * 2 + 1000, // expiration
    //       0, // tpslExpiration
    //       2, // profitTokenId
    //       0, // tpslProfitTokenId
    //       PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.ShouldReachMinProfit,
    //     ])
    //   await expect(tx2)
    //     .to.emit(orderBook, "NewPositionOrder")
    //     .withArgs(trader1.address, 3, [
    //       args2.subAccountId,
    //       toWei("0"), // collateral
    //       args2.size,
    //       toWei("1800"), // price
    //       toWei("0"), // tpPrice
    //       toWei("0"), // slPrice
    //       timestampOfTest + 86400 * 2 + 1000, // expiration
    //       0, // tpslExpiration
    //       2, // profitTokenId
    //       0, // tpslProfitTokenId
    //       PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.TriggerOrder,
    //     ])
    //   // close tp+sl
    //   const args3 = {
    //     subAccountId: longAccountId,
    //     collateral: toUnit("12345", 6),
    //     size: toWei("2"),
    //     price: toWei("2000"),
    //     tpPrice: toWei("2200"),
    //     slPrice: toWei("1800"),
    //     expiration: timestampOfTest + 86400 * 2 + 800,
    //     tpslExpiration: timestampOfTest + 86400 * 2 + 1000,
    //     profitTokenId: 0,
    //     tpslProfitTokenId: 2,
    //     flags: PositionOrderFlags.TpSlStrategy,
    //   }
    //   await expect(orderBook.connect(trader1).placePositionOrder(args3, refCode)).to.revertedWith("C!0")
    //   args3.collateral = toUnit("0", 6)
    //   const tx3 = await orderBook.connect(trader1).placePositionOrder(args3, refCode)
    //   await expect(tx3)
    //     .to.emit(orderBook, "NewPositionOrder")
    //     .withArgs(trader1.address, 4, [
    //       args2.subAccountId,
    //       toWei("0"), // collateral
    //       args2.size,
    //       toWei("2200"), // price
    //       toWei("0"), // tpPrice
    //       toWei("0"), // slPrice
    //       timestampOfTest + 86400 * 2 + 1000, // expiration
    //       0, // tpslExpiration
    //       2, // profitTokenId
    //       0, // tpslProfitTokenId
    //       PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.ShouldReachMinProfit,
    //     ])
    //   await expect(tx3)
    //     .to.emit(orderBook, "NewPositionOrder")
    //     .withArgs(trader1.address, 5, [
    //       args2.subAccountId,
    //       toWei("0"), // collateral
    //       args2.size,
    //       toWei("1800"), // price
    //       toWei("0"), // tpPrice
    //       toWei("0"), // slPrice
    //       timestampOfTest + 86400 * 2 + 1000, // expiration
    //       0, // tpslExpiration
    //       2, // profitTokenId
    //       0, // tpslProfitTokenId
    //       PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.TriggerOrder,
    //     ])
    // })
  }) // add some liquidity and test more

  // it("TODO: trade collateral must be stable", async () => {
  //   // // open short xxx, using xxx
  //   // const shortAccountId = assembleSubAccountId(trader1.address, 1, 1, false)
  //   // const args = {
  //   //   subAccountId: shortAccountId,
  //   //   collateral: toUnit("1", 18),
  //   //   size: toWei("1"),
  //   //   price: toWei("1000"),
  //   //   tpPrice: "0",
  //   //   slPrice: "0",
  //   //   expiration: timestampOfTest + 86400 * 2 + 800,
  //   //   tpslExpiration: timestampOfTest + 86400 * 2 + 800,
  //   //   profitTokenId: 0,
  //   //   tpslProfitTokenId: 0,
  //   //   flags: PositionOrderFlags.OpenPosition,
  //   // }
  //   // await xxx.connect(trader1).transfer(orderBook.address, toUnit("1", 18))
  //   // await expect(orderBook.connect(trader1).placePositionOrder(args, refCode)).to.revertedWith("FLG")
  // })

  // it("TODO: open position cause reserved > spotLiquidity", async () => {
  //   // // open long xxx, using usdc
  //   // const longAccountId = assembleSubAccountId(trader1.address, 0, 1, true)
  //   // await usdc.connect(trader1).transfer(orderBook.address, toUnit("10000", 6))
  //   // const args2 = {
  //   //   subAccountId: longAccountId,
  //   //   collateral: toUnit("10000", 6),
  //   //   size: toWei("1"),
  //   //   price: toWei("1"),
  //   //   tpPrice: "0",
  //   //   slPrice: "0",
  //   //   expiration: timestampOfTest + 86400 * 2 + 800,
  //   //   tpslExpiration: timestampOfTest + 86400 * 2 + 800,
  //   //   profitTokenId: 0,
  //   //   tpslProfitTokenId: 0,
  //   //   flags: PositionOrderFlags.OpenPosition,
  //   // }
  //   // await orderBook.connect(trader1).placePositionOrder(args2, refCode)
  //   // await expect(
  //   //   orderBook.connect(broker).fillPositionOrder(0, toWei("1"), toWei("1"), [toWei("1"), toWei("1"), toWei("1")])
  //   // ).to.revertedWith("RSV")
  // })

  // it("TODO: stop loss", async () => {})
  // it("TODO: tp/sl strategy - open long", async () => {})
  // it("TODO: tp/sl strategy - open short", async () => {})
  // it("TODO: tp/sl strategy - close long", async () => {})
  // it("TODO: tp/sl strategy - liquidate long", async () => {})
})
