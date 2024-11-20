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
  encodePoolMarketKey,
} from "../scripts/deployUtils"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import {
  CollateralPool,
  OrderBook,
  TestMux3,
  MockERC20,
  WETH9,
  MockMux3FeeDistributor,
  MockUniswapV3,
  Swapper,
  CollateralPoolEventEmitter,
} from "../typechain"
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
  let emitter: CollateralPoolEventEmitter
  let imp: CollateralPool
  let pool1: CollateralPool
  let pool2: CollateralPool
  let pool3: CollateralPool
  let orderBook: OrderBook
  let feeDistributor: MockMux3FeeDistributor

  let uniswap: MockUniswapV3

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
    emitter = (await createContract("CollateralPoolEventEmitter")) as CollateralPoolEventEmitter
    await emitter.initialize(core.address)
    imp = (await createContract("CollateralPool", [
      core.address,
      orderBook.address,
      weth.address,
      emitter.address,
    ])) as CollateralPool
    await core.setCollateralPoolImplementation(imp.address)

    // pool 1 (priority)
    await core.createCollateralPool("TN0", "TS0", usdc.address, 0)
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
    await core.createCollateralPool("TN1", "TS1", usdc.address, 1)
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
    await core.createCollateralPool("TN2", "TS2", usdc.address, 2)
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
    feeDistributor = (await createContract("MockMux3FeeDistributor", [core.address])) as MockMux3FeeDistributor
    await core.setConfig(ethers.utils.id("MC_FEE_DISTRIBUTOR"), a2b(feeDistributor.address))

    // role
    await orderBook.grantRole(ethers.utils.id("BROKER_ROLE"), broker.address)
    await core.grantRole(ethers.utils.id("ORDER_BOOK_ROLE"), orderBook.address)

    // price
    await core.setMockPrice(a2b(usdc.address), toWei("1"))
    await core.setMockPrice(a2b(btc.address), toWei("50000"))

    // swapper
    uniswap = (await createContract("MockUniswapV3", [
      usdc.address,
      weth.address,
      btc.address,
      zeroAddress,
    ])) as MockUniswapV3
    const swapper = (await createContract("Swapper", [])) as Swapper
    await swapper.initialize(weth.address, uniswap.address, uniswap.address)
    await core.setConfig(ethers.utils.id("MC_SWAPPER"), a2b(swapper.address))
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
      await time.increaseTo(timestampOfTest + 86400 * 2 + 930)
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
          expiration: timestampOfTest + 86400 * 2 + 930 + 300,
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
          expiration: timestampOfTest + 86400 * 2 + 930 + 86400 * 7 + 30,
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
          expiration: timestampOfTest + 86400 * 2 + 930 + 86400 * 7 + 30,
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

      describe("trader 2 long, pool1 full, pool2+3", () => {
        let positionId2 = ""
        beforeEach(async () => {
          // open long btc, using usdc
          positionId2 = encodePositionId(trader2.address, 0)
          await orderBook.connect(trader2).setInitialLeverage(positionId2, long1, toWei("100"))
          await usdc.connect(trader2).transfer(orderBook.address, toUnit("21000", 6))
          const args = {
            positionId: positionId2,
            marketId: long1,
            size: toWei("20"),
            flags: PositionOrderFlags.OpenPosition,
            limitPrice: toWei("50000"),
            expiration: timestampOfTest + 86400 * 2 + 930 + 300,
            lastConsumedToken: zeroAddress,
            collateralToken: usdc.address,
            collateralAmount: toUnit("21000", 6),
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
          await orderBook.connect(trader2).placePositionOrder(args, refCode)
          {
            const tx2 = await orderBook.connect(broker).fillPositionOrder(4)
            await expect(tx2)
              .to.emit(core, "OpenPosition")
              .withArgs(
                trader2.address,
                positionId2,
                long1,
                true, // isLong
                toWei("20"), // size
                toWei("50000"), // trading price
                [pool1.address],
                [toWei("4.9975"), toWei("7.5013"), toWei("7.5012")], // allocations
                [toWei("4.9975"), toWei("7.5013"), toWei("7.5012")], // new size
                [toWei("50000"), toWei("50000"), toWei("50000")], // new entry
                toWei("1000"), // positionFeeUsd = 50000 * 20 * 0.001 = 1000
                toWei("0"), // borrowingFeeUsd
                [usdc.address],
                [toWei("20000")] // 21000 - 1000
              )
          }
          {
            const collaterals = await core.listAccountCollaterals(positionId2)
            expect(collaterals[0].collateralAddress).to.equal(usdc.address)
            expect(collaterals[0].collateralAmount).to.equal(toWei("20000"))
            const positions = await core.listAccountPositions(positionId2)
            expect(positions[0].marketId).to.equal(long1)
            const activated = await core.listActivePositionIds(0, 10)
            expect(activated.totalLength).to.equal(2)
            expect(activated.positionIds[0]).to.equal(positionId)
            expect(activated.positionIds[1]).to.equal(positionId2)
          }
          {
            const state = await pool1.marketState(long1)
            expect(state.isLong).to.equal(true)
            expect(state.totalSize).to.equal(toWei("24.9975"))
            expect(state.averageEntryPrice).to.equal(toWei("50000"))
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            const state = await pool2.marketState(long1)
            expect(state.isLong).to.equal(true)
            expect(state.totalSize).to.equal(toWei("7.5013"))
            expect(state.averageEntryPrice).to.equal(toWei("50000"))
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            const state = await pool3.marketState(long1)
            expect(state.isLong).to.equal(true)
            expect(state.totalSize).to.equal(toWei("7.5012"))
            expect(state.averageEntryPrice).to.equal(toWei("50000"))
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            expect(await pool1.callStatic.getAumUsd()).to.equal(toWei("999900")) // unchanged
            expect(await pool2.callStatic.getAumUsd()).to.equal(toWei("999900")) // unchanged
            expect(await pool3.callStatic.getAumUsd()).to.equal(toWei("999900")) // unchanged
          }
        })

        describe("trader 1 closed, so that priority pool is not full", () => {
          beforeEach(async () => {
            // close all
            const args = {
              positionId,
              marketId: long1,
              size: toWei("20"),
              flags: PositionOrderFlags.WithdrawAllIfEmpty,
              limitPrice: toWei("50000"),
              expiration: timestampOfTest + 86400 * 2 + 930 + 86400 * 7 + 30,
              lastConsumedToken: usdc.address,
              collateralToken: zeroAddress,
              collateralAmount: toUnit("0", 6),
              withdrawUsd: toWei("0"),
              withdrawSwapToken: usdc.address,
              withdrawSwapSlippage: toWei("0.01"),
              tpPriceDiff: toWei("0"),
              slPriceDiff: toWei("0"),
              tpslExpiration: 0,
              tpslFlags: 0,
              tpslWithdrawSwapToken: zeroAddress,
              tpslWithdrawSwapSlippage: toWei("0"),
            }
            await orderBook.connect(trader1).placePositionOrder(args, refCode)
            {
              const tx2 = await orderBook.connect(broker).fillPositionOrder(5)
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
            {
              const activated = await core.listActivePositionIds(0, 10)
              expect(activated.totalLength).to.equal(1)
              expect(activated.positionIds[0]).to.equal(positionId2)
            }
            {
              const state = await pool1.marketState(long1)
              expect(state.isLong).to.equal(true)
              expect(state.totalSize).to.equal(toWei("4.9975"))
              expect(state.averageEntryPrice).to.equal(toWei("50000"))
              expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
            }
            {
              const state = await pool2.marketState(long1)
              expect(state.isLong).to.equal(true)
              expect(state.totalSize).to.equal(toWei("7.5013"))
              expect(state.averageEntryPrice).to.equal(toWei("50000"))
              expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
            }
            {
              const state = await pool3.marketState(long1)
              expect(state.isLong).to.equal(true)
              expect(state.totalSize).to.equal(toWei("7.5012"))
              expect(state.averageEntryPrice).to.equal(toWei("50000"))
              expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
            }
            {
              expect(await pool1.callStatic.getAumUsd()).to.equal(toWei("999900")) // unchanged
              expect(await pool2.callStatic.getAumUsd()).to.equal(toWei("999900")) // unchanged
              expect(await pool3.callStatic.getAumUsd()).to.equal(toWei("999900")) // unchanged
            }
          })

          it("reallocate pool2 -> pool1", async () => {
            await core.setMockPrice(a2b(btc.address), toWei("60000"))
            // fr1 0.10 + exp(6.36306 * 4.9975 * 60000 * 0.80 / 999900 - 6.58938) = 0.106327459192144774
            // fr2 0.10 + exp(6.36306 * 7.5013 * 60000 * 0.80 / 999900 - 6.58938) = 0.113595013440302005
            // fr3 0.10 + exp(6.36306 * 7.5012 * 60000 * 0.80 / 999900 - 6.58938) = 0.113594598176863461
            // acc1 0.106327459192144774 * 7 / 365 = 0.002039156751630173
            // acc2 0.113595013440302005 * 7 / 365 = 0.002178534504334559
            // acc2 0.113594598176863461 * 7 / 365 = 0.002178526540378203
            // borrowing 60000 * 4.9975 * 0.002039156751630173 + 60000 * 7.5013 * 0.002178534504334559 = 1591.951604618197019652
            await time.increaseTo(timestampOfTest + 86400 * 2 + 930 + 86400 * 7 + 30)
            await expect(
              orderBook
                .connect(trader2)
                .reallocate(positionId2, long1, pool2.address, pool1.address, toWei("7.5013"), usdc.address, false)
            ).to.be.revertedWith("AccessControl")
            const tx3 = await orderBook
              .connect(broker)
              .reallocate(positionId2, long1, pool2.address, pool1.address, toWei("7.5013"), usdc.address, false)
            // {
            //   for (const i of (await (await tx3).wait()).events!) {
            //     if (i.topics[0] === "0xd96b06dba5730e68d159471f627b117be995386df87ebe38f94d51fe476d5985") {
            //       console.log(emitter.interface.parseLog(i))
            //     }
            //   }
            // }
            await expect(tx3).to.emit(emitter, "UpdateMarketBorrowing").withArgs(
              pool1.address,
              long1,
              toWei("0.106327459192144774"), // apy
              toWei("0.002039156751630173") // acc
            )
            await expect(tx3).to.emit(emitter, "UpdateMarketBorrowing").withArgs(
              pool2.address,
              long1,
              toWei("0.113595013440302005"), // apy
              toWei("0.002178534504334559") // acc
            )
            await expect(tx3)
              .to.emit(core, "ReallocatePosition")
              .withArgs(
                trader2.address,
                positionId2,
                long1,
                true, // isLong
                pool2.address,
                pool1.address,
                toWei("7.5013"), // size
                toWei("60000"), // trading price
                [pool1.address, pool2.address, pool3.address],
                [toWei("12.4988"), toWei("0"), toWei("7.5012")], // newSizes 4.9975 + 7.5013
                [toWei("56001.616155150894485870"), toWei("0"), toWei("50000")], // newEntryPrices (50000 * 4.9975 + 60000 * 7.5013) / 12.4988
                [toWei("0"), toWei("75013"), toWei("0")], // poolPnlUsds (60000 - 50000) * 7.5013
                toWei("1591.951604618197019652"), // borrowingFeeUsd
                [usdc.address],
                [toWei("93421.048395381802980348")] // 20000 + 75013 - 1591.951604618197019652
              )
          })
        })
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
          expiration: timestampOfTest + 86400 * 2 + 930 + 300,
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
        {
          const collaterals = await core.listAccountCollaterals(positionId)
          expect(collaterals[0].collateralAddress).to.equal(usdc.address)
          expect(collaterals[0].collateralAmount).to.equal(toWei("20000"))
          const positions = await core.listAccountPositions(positionId)
          expect(positions[0].marketId).to.equal(long1)
          const activated = await core.listActivePositionIds(0, 10)
          expect(activated.totalLength).to.equal(1)
          expect(activated.positionIds[0]).to.equal(positionId)
        }
        {
          const state = await pool1.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("24.9975"))
          expect(state.averageEntryPrice).to.equal(toWei("50000"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool2.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("7.5013"))
          expect(state.averageEntryPrice).to.equal(toWei("50000"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool3.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("7.5012"))
          expect(state.averageEntryPrice).to.equal(toWei("50000"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          expect(await pool1.callStatic.getAumUsd()).to.equal(toWei("999900")) // unchanged
          expect(await pool2.callStatic.getAumUsd()).to.equal(toWei("999900")) // unchanged
          expect(await pool3.callStatic.getAumUsd()).to.equal(toWei("999900")) // unchanged
        }
      })

      it("close a little from 2+3", async () => {
        const args = {
          positionId,
          marketId: long1,
          size: toWei("3"),
          flags: PositionOrderFlags.WithdrawAllIfEmpty,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 930 + 86400 * 7 + 30,
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
          expiration: timestampOfTest + 86400 * 2 + 930 + 86400 * 7 + 30,
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
          expiration: timestampOfTest + 86400 * 2 + 930 + 86400 * 7 + 30,
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
