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

describe("Priority pool", () => {
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
  let trader2: SignerWithAddress

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
    trader2 = accounts[4]
    weth = (await createContract("WETH9", [])) as WETH9
  })

  beforeEach(async () => {
    timestampOfTest = await time.latest()
    timestampOfTest = Math.ceil(timestampOfTest / 3600) * 3600 // move to the next hour

    // token
    usdc = (await createContract("MockERC20", ["USDC", "USDC", 6])) as MockERC20
    btc = (await createContract("MockERC20", ["BTC", "BTC", 8])) as MockERC20
    await usdc.mint(lp1.address, toUnit("1000000", 6))
    await usdc.mint(trader1.address, toUnit("100000", 6))
    await usdc.mint(trader2.address, toUnit("100000", 6))

    // core
    core = (await createContract("TestMux3", [])) as TestMux3
    await core.initialize(weth.address)
    await core.addCollateralToken(usdc.address, 6)
    await core.setCollateralTokenStatus(usdc.address, true)
    await core.setConfig(ethers.utils.id("MC_BORROWING_BASE_APY"), u2b(toWei("0.10")))
    await core.setConfig(ethers.utils.id("MC_BORROWING_INTERVAL"), u2b(ethers.BigNumber.from(3600)))

    // orderBook
    const libOrderBook = await createContract("LibOrderBook")
    orderBook = (await createContract("OrderBook", [], {
      "contracts/libraries/LibOrderBook.sol:LibOrderBook": libOrderBook,
    })) as OrderBook
    await orderBook.initialize(core.address, weth.address)
    await orderBook.setConfig(ethers.utils.id("MCO_LIQUIDITY_LOCK_PERIOD"), u2b(ethers.BigNumber.from(60 * 15)))
    await orderBook.setConfig(ethers.utils.id("MCO_MARKET_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(60 * 2)))
    await orderBook.setConfig(ethers.utils.id("MCO_LIMIT_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(86400 * 30)))
    await orderBook.setConfig(ethers.utils.id("MCO_CANCEL_COOL_DOWN"), u2b(ethers.BigNumber.from(5)))

    // collateral pool
    imp = (await createContract("CollateralPool", [core.address, orderBook.address, weth.address])) as CollateralPool
    await core.setCollateralPoolImplementation(imp.address)

    // pool 1 (priority)
    await core.createCollateralPool("TN0", "TS0", usdc.address)
    const poolAddr = (await core.listCollateralPool())[0]
    pool1 = (await ethers.getContractAt("CollateralPool", poolAddr)) as CollateralPool
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306")))
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938")))
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_IS_HIGH_PRIORITY"), u2b(ethers.BigNumber.from(1)))
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000")))
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", long1), u2b(toWei("0.80")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", long1), u2b(toWei("0.75")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", long1), u2b(toWei("0.70")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", short1), u2b(toWei("0.80")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", short1), u2b(toWei("0.75")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", short1), u2b(toWei("0.70")))

    // pool 2
    await core.createCollateralPool("TN1", "TS1", usdc.address)
    const pool2Addr = (await core.listCollateralPool())[1]
    pool2 = (await ethers.getContractAt("CollateralPool", pool2Addr)) as CollateralPool
    await core.setPoolConfig(pool2.address, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306")))
    await core.setPoolConfig(pool2.address, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938")))
    await core.setPoolConfig(pool2.address, ethers.utils.id("MCP_IS_HIGH_PRIORITY"), u2b(ethers.BigNumber.from(0)))
    await core.setPoolConfig(pool2.address, ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000")))
    await core.setPoolConfig(pool2.address, ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001")))
    await core.setPoolConfig(pool2.address, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", long1), u2b(toWei("0.80")))
    await core.setPoolConfig(pool2.address, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", long1), u2b(toWei("0.75")))
    await core.setPoolConfig(pool2.address, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", long1), u2b(toWei("0.70")))
    await core.setPoolConfig(pool2.address, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", short1), u2b(toWei("0.80")))
    await core.setPoolConfig(pool2.address, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", short1), u2b(toWei("0.75")))
    await core.setPoolConfig(pool2.address, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", short1), u2b(toWei("0.70")))

    // pool 3
    await core.createCollateralPool("TN2", "TS2", usdc.address)
    const pool3Addr = (await core.listCollateralPool())[2]
    pool3 = (await ethers.getContractAt("CollateralPool", pool3Addr)) as CollateralPool
    await core.setPoolConfig(pool3.address, ethers.utils.id("MCP_BORROWING_BASE_APY"), u2b(toWei("0.10")))
    await core.setPoolConfig(pool3.address, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306")))
    await core.setPoolConfig(pool3.address, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938")))
    await core.setPoolConfig(pool3.address, ethers.utils.id("MCP_IS_HIGH_PRIORITY"), u2b(ethers.BigNumber.from(0)))
    await core.setPoolConfig(pool3.address, ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000")))
    await core.setPoolConfig(pool3.address, ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001")))
    await core.setPoolConfig(pool3.address, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", long1), u2b(toWei("0.80")))
    await core.setPoolConfig(pool3.address, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", long1), u2b(toWei("0.75")))
    await core.setPoolConfig(pool3.address, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", long1), u2b(toWei("0.70")))
    await core.setPoolConfig(pool3.address, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", short1), u2b(toWei("0.80")))
    await core.setPoolConfig(pool3.address, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", short1), u2b(toWei("0.75")))
    await core.setPoolConfig(pool3.address, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", short1), u2b(toWei("0.70")))

    // market 1 - uses 3 pools
    await core.createMarket(
      long1,
      "Long1",
      true, // isLong
      [pool1.address, pool2.address, pool3.address]
    )
    await core.setMarketConfig(long1, ethers.utils.id("MM_POSITION_FEE_RATE"), u2b(toWei("0.001")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_LIQUIDATION_FEE_RATE"), u2b(toWei("0.002")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_INITIAL_MARGIN_RATE"), u2b(toWei("0.006")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_MAINTENANCE_MARGIN_RATE"), u2b(toWei("0.005")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.0001")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_ORACLE_ID"), a2b(btc.address))

    await core.createMarket(
      short1,
      "Short1",
      false, // isLong
      [pool2.address, pool3.address]
    )
    await core.setMarketConfig(short1, ethers.utils.id("MM_POSITION_FEE_RATE"), u2b(toWei("0.001")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_LIQUIDATION_FEE_RATE"), u2b(toWei("0.002")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_INITIAL_MARGIN_RATE"), u2b(toWei("0.006")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_MAINTENANCE_MARGIN_RATE"), u2b(toWei("0.005")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.0001")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_ORACLE_ID"), a2b(btc.address))

    // feeDistributor
    feeDistributor = (await createContract("MockFeeDistributor", [core.address])) as MockFeeDistributor
    await core.setConfig(ethers.utils.id("MC_FEE_DISTRIBUTOR"), a2b(feeDistributor.address))

    // role
    await orderBook.grantRole(ethers.utils.id("BROKER_ROLE"), broker.address)
    await core.grantRole(ethers.utils.id("ORDER_BOOK_ROLE"), orderBook.address)

    // price
    await core.setMockPrice(a2b(usdc.address), toWei("1"))
    await core.setMockPrice(a2b(btc.address), toWei("50000"))
  })

  describe("add liquidity to 3 pools and test more", () => {
    beforeEach(async () => {
      await time.increaseTo(timestampOfTest + 86400 * 2)
      await usdc.mint(orderBook.address, toUnit("1000000", 6))
      {
        const args = {
          poolAddress: pool1.address,
          rawAmount: toUnit("1000000", 6),
          isAdding: true,
          isUnwrapWeth: false,
        }
        await orderBook.connect(lp1).placeLiquidityOrder(args)
      }
      await usdc.mint(orderBook.address, toUnit("1000000", 6))
      {
        const args = {
          poolAddress: pool2.address,
          rawAmount: toUnit("1000000", 6),
          isAdding: true,
          isUnwrapWeth: false,
        }
        await orderBook.connect(lp1).placeLiquidityOrder(args)
      }
      await usdc.mint(orderBook.address, toUnit("1000000", 6))
      {
        const args = {
          poolAddress: pool3.address,
          rawAmount: toUnit("1000000", 6),
          isAdding: true,
          isUnwrapWeth: false,
        }
        await orderBook.connect(lp1).placeLiquidityOrder(args)
      }
      await time.increaseTo(timestampOfTest + 86400 * 2 + 905)
      {
        await orderBook.connect(broker).fillLiquidityOrder(0)
        await orderBook.connect(broker).fillLiquidityOrder(1)
        await orderBook.connect(broker).fillLiquidityOrder(2)
        expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("300", 6)) // fee = 3000000 * 0.01% = 300
        expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6))
        expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6))
        expect(await usdc.balanceOf(pool3.address)).to.equal(toUnit("999900", 6))
      }
      {
        const [poolTokens, poolBalances] = await pool1.liquidityBalances()
        expect(poolTokens[0]).to.equal(usdc.address)
        expect(poolBalances[0]).to.equal(toWei("999900")) // 1000000 - fee
      }
      {
        const [poolTokens, poolBalances] = await pool2.liquidityBalances()
        expect(poolTokens[0]).to.equal(usdc.address)
        expect(poolBalances[0]).to.equal(toWei("999900")) // 1000000 - fee
      }
      {
        const [poolTokens, poolBalances] = await pool3.liquidityBalances()
        expect(poolTokens[0]).to.equal(usdc.address)
        expect(poolBalances[0]).to.equal(toWei("999900")) // 1000000 - fee
      }
    })

    describe("long 1, always use pool1", () => {
      let positionId = ""
      beforeEach(async () => {
        // open long btc, using usdc
        positionId = encodePositionId(trader1.address, 0)
        await orderBook.connect(trader1).setInitialLeverage(positionId, long1, toWei("100"))
        await usdc.connect(trader1).transfer(orderBook.address, toUnit("11000", 6))
        const args = {
          positionId,
          marketId: long1,
          size: toWei("20"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 300,
          lastConsumedToken: zeroAddress,
          collateralToken: usdc.address,
          collateralAmount: toUnit("11000", 6),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: 0,
          tpPriceDiff: 0,
          slPriceDiff: 0,
          tpslExpiration: 0,
          tpslFlags: 0,
          tpslWithdrawSwapToken: zeroAddress,
          tpslWithdrawSwapSlippage: 0,
        }
        await orderBook.connect(trader1).placePositionOrder(args, refCode)
        {
          const tx2 = await orderBook.connect(broker).fillPositionOrder(3)
          await expect(tx2)
            .to.emit(core, "OpenPosition")
            .withArgs(
              trader1.address,
              positionId,
              long1,
              true, // isLong
              toWei("20"), // size
              toWei("50000"), // trading price
              [pool1.address],
              [toWei("20"), toWei("0"), toWei("0")], // allocations
              [toWei("20"), toWei("0"), toWei("0")], // new size
              [toWei("50000"), toWei("0"), toWei("0")], // new entry
              toWei("1000"), // positionFeeUsd = 50000 * 20 * 0.001 = 1000
              toWei("0"), // borrowingFeeUsd
              [usdc.address],
              [toWei("10000")] // 11000 - 1000
            )
        }
      })

      it("close half", async () => {
        const args = {
          positionId,
          marketId: long1,
          size: toWei("10"),
          flags: PositionOrderFlags.WithdrawAllIfEmpty,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 86400 * 7 + 30,
          lastConsumedToken: zeroAddress,
          collateralToken: zeroAddress,
          collateralAmount: toUnit("0", 6),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("0"),
          slPriceDiff: toWei("0"),
          tpslExpiration: 0,
          tpslFlags: 0,
          tpslWithdrawSwapToken: zeroAddress,
          tpslWithdrawSwapSlippage: toWei("0"),
        }
        await orderBook.connect(trader1).placePositionOrder(args, refCode)
        {
          const tx2 = await orderBook.connect(broker).fillPositionOrder(4)
          await expect(tx2)
            .to.emit(core, "ClosePosition")
            .withArgs(
              trader1.address,
              positionId,
              long1,
              true, // isLong
              toWei("10"), // size
              toWei("50000"), // tradingPrice
              [pool1.address, pool2.address, pool3.address], // backedPools
              [toWei("10"), toWei("0"), toWei("0")], // allocations
              [toWei("10"), toWei("0"), toWei("0")], // newSizes
              [toWei("50000"), toWei("0"), toWei("0")], // newEntryPrices
              [toWei("0"), toWei("0"), toWei("0")], // poolPnlUsds
              toWei("500"), // positionFeeUsd = 50000 * 10 * 0.001
              toWei("0"), // borrowingFeeUsd
              [usdc.address],
              [toWei("9500")] // collateral + pnl - fee = 10000 - 500
            )
        }
      })

      it("close all", async () => {
        const args = {
          positionId,
          marketId: long1,
          size: toWei("20"),
          flags: PositionOrderFlags.WithdrawAllIfEmpty,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 86400 * 7 + 30,
          lastConsumedToken: zeroAddress,
          collateralToken: zeroAddress,
          collateralAmount: toUnit("0", 6),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("0"),
          slPriceDiff: toWei("0"),
          tpslExpiration: 0,
          tpslFlags: 0,
          tpslWithdrawSwapToken: zeroAddress,
          tpslWithdrawSwapSlippage: toWei("0"),
        }
        await orderBook.connect(trader1).placePositionOrder(args, refCode)
        {
          const tx2 = await orderBook.connect(broker).fillPositionOrder(4)
          await expect(tx2)
            .to.emit(core, "ClosePosition")
            .withArgs(
              trader1.address,
              positionId,
              long1,
              true, // isLong
              toWei("20"), // size
              toWei("50000"), // tradingPrice
              [pool1.address, pool2.address, pool3.address], // backedPools
              [toWei("20"), toWei("0"), toWei("0")], // allocations
              [toWei("0"), toWei("0"), toWei("0")], // newSizes
              [toWei("0"), toWei("0"), toWei("0")], // newEntryPrices
              [toWei("0"), toWei("0"), toWei("0")], // poolPnlUsds
              toWei("1000"), // positionFeeUsd = 50000 * 20 * 0.001
              toWei("0"), // borrowingFeeUsd
              [usdc.address],
              [toWei("9000")] // collateral + pnl - fee = 10000 - 1000
            )
        }
      })
    })

    describe("long 2, pool1 full, pool2+3", () => {
      let positionId = ""

      beforeEach(async () => {
        // open long btc, using usdc
        positionId = encodePositionId(trader1.address, 0)
        await orderBook.connect(trader1).setInitialLeverage(positionId, long1, toWei("100"))
        await usdc.connect(trader1).transfer(orderBook.address, toUnit("22000", 6))
        const args = {
          positionId,
          marketId: long1,
          size: toWei("40"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 300,
          lastConsumedToken: zeroAddress,
          collateralToken: usdc.address,
          collateralAmount: toUnit("22000", 6),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("0"),
          slPriceDiff: toWei("0"),
          tpslExpiration: 0,
          tpslFlags: 0,
          tpslWithdrawSwapToken: zeroAddress,
          tpslWithdrawSwapSlippage: toWei("0"),
        }
        await orderBook.connect(trader1).placePositionOrder(args, refCode)
        {
          const tx2 = await orderBook.connect(broker).fillPositionOrder(3)
          await expect(tx2)
            .to.emit(core, "OpenPosition")
            .withArgs(
              trader1.address,
              positionId,
              long1,
              true, // isLong
              toWei("40"), // size
              toWei("50000"), // trading price
              [pool1.address],
              [toWei("24.9975"), toWei("7.5013"), toWei("7.5012")], // allocations
              [toWei("24.9975"), toWei("7.5013"), toWei("7.5012")], // new size
              [toWei("50000"), toWei("50000"), toWei("50000")], // new entry
              toWei("2000"), // positionFeeUsd = 50000 * 40 * 0.001 = 2000
              toWei("0"), // borrowingFeeUsd
              [usdc.address],
              [toWei("20000")] // 22000 - 2000
            )
        }
      })

      it("close a little from 2+3", async () => {
        const args = {
          positionId,
          marketId: long1,
          size: toWei("3"),
          flags: PositionOrderFlags.WithdrawAllIfEmpty,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 86400 * 7 + 30,
          lastConsumedToken: zeroAddress,
          collateralToken: zeroAddress,
          collateralAmount: toUnit("0", 6),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("0"),
          slPriceDiff: toWei("0"),
          tpslExpiration: 0,
          tpslFlags: 0,
          tpslWithdrawSwapToken: zeroAddress,
          tpslWithdrawSwapSlippage: toWei("0"),
        }
        await orderBook.connect(trader1).placePositionOrder(args, refCode)
        {
          const tx2 = await orderBook.connect(broker).fillPositionOrder(4)
          await expect(tx2)
            .to.emit(core, "ClosePosition")
            .withArgs(
              trader1.address,
              positionId,
              long1,
              true, // isLong
              toWei("3"), // size
              toWei("50000"), // tradingPrice
              [pool1.address, pool2.address, pool3.address], // backedPools
              [toWei("0"), toWei("1.5"), toWei("1.5")], // allocations
              [toWei("24.9975"), toWei("6.0013"), toWei("6.0012")], // newSizes
              [toWei("50000"), toWei("50000"), toWei("50000")], // newEntryPrices
              [toWei("0"), toWei("0"), toWei("0")], // poolPnlUsds
              toWei("150"), // positionFeeUsd = 50000 * 3 * 0.001
              toWei("0"), // borrowingFeeUsd
              [usdc.address],
              [toWei("19850")] // collateral + pnl - fee = 20000 - 150
            )
        }
      })

      it("close from 1+2+3", async () => {
        const args = {
          positionId,
          marketId: long1,
          size: toWei("20"),
          flags: PositionOrderFlags.WithdrawAllIfEmpty,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 86400 * 7 + 30,
          lastConsumedToken: zeroAddress,
          collateralToken: zeroAddress,
          collateralAmount: toUnit("0", 6),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("0"),
          slPriceDiff: toWei("0"),
          tpslExpiration: 0,
          tpslFlags: 0,
          tpslWithdrawSwapToken: zeroAddress,
          tpslWithdrawSwapSlippage: toWei("0"),
        }
        await orderBook.connect(trader1).placePositionOrder(args, refCode)
        {
          const tx2 = await orderBook.connect(broker).fillPositionOrder(4)
          await expect(tx2)
            .to.emit(core, "ClosePosition")
            .withArgs(
              trader1.address,
              positionId,
              long1,
              true, // isLong
              toWei("20"), // size
              toWei("50000"), // tradingPrice
              [pool1.address, pool2.address, pool3.address], // backedPools
              [toWei("4.9975"), toWei("7.5013"), toWei("7.5012")], // allocations
              [toWei("20"), toWei("0"), toWei("0")], // newSizes
              [toWei("50000"), toWei("0"), toWei("0")], // newEntryPrices
              [toWei("0"), toWei("0"), toWei("0")], // poolPnlUsds
              toWei("1000"), // positionFeeUsd = 50000 * 20 * 0.001
              toWei("0"), // borrowingFeeUsd
              [usdc.address],
              [toWei("19000")] // collateral + pnl - fee = 20000 - 1000
            )
        }
      })

      it("close all", async () => {
        const args = {
          positionId,
          marketId: long1,
          size: toWei("40"),
          flags: PositionOrderFlags.WithdrawAllIfEmpty,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 86400 * 7 + 30,
          lastConsumedToken: zeroAddress,
          collateralToken: zeroAddress,
          collateralAmount: toUnit("0", 6),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("0"),
          slPriceDiff: toWei("0"),
          tpslExpiration: 0,
          tpslFlags: 0,
          tpslWithdrawSwapToken: zeroAddress,
          tpslWithdrawSwapSlippage: toWei("0"),
        }
        await orderBook.connect(trader1).placePositionOrder(args, refCode)
        {
          const tx2 = await orderBook.connect(broker).fillPositionOrder(4)
          await expect(tx2)
            .to.emit(core, "ClosePosition")
            .withArgs(
              trader1.address,
              positionId,
              long1,
              true, // isLong
              toWei("40"), // size
              toWei("50000"), // tradingPrice
              [pool1.address, pool2.address, pool3.address], // backedPools
              [toWei("24.9975"), toWei("7.5013"), toWei("7.5012")], // allocations
              [toWei("0"), toWei("0"), toWei("0")], // newSizes
              [toWei("0"), toWei("0"), toWei("0")], // newEntryPrices
              [toWei("0"), toWei("0"), toWei("0")], // poolPnlUsds
              toWei("2000"), // positionFeeUsd = 50000 * 40 * 0.001
              toWei("0"), // borrowingFeeUsd
              [usdc.address],
              [toWei("18000")] // collateral + pnl - fee = 20000 - 2000
            )
        }
      })
    })
  }) // add some liquidity and test more
})
