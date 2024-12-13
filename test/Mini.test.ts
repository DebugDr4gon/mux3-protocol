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
  CollateralPoolEventEmitter,
} from "../typechain"
import { time } from "@nomicfoundation/hardhat-network-helpers"

const a2b = (a) => {
  return a + "000000000000000000000000"
}
const u2b = (u) => {
  return ethers.utils.hexZeroPad(u.toTwos(256).toHexString(), 32)
}

describe("Mini", () => {
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
  let orderBook: OrderBook
  let feeDistributor: MockMux3FeeDistributor
  let emitter: CollateralPoolEventEmitter

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
    timestampOfTest = Math.ceil(timestampOfTest / 3600) * 3600 // move to the next hour

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
    await core.initialize(weth.address)
    await core.addCollateralToken(usdc.address, 6)
    await core.addCollateralToken(arb.address, 18)
    await core.addCollateralToken(btc.address, 8)
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
    await orderBook.setConfig(ethers.utils.id("MCO_MIN_LIQUIDITY_ORDER_USD"), u2b(toWei("0.1")))

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

    // pool 1
    await core.createCollateralPool("TN1", "TS1", usdc.address, 0)
    const pool1Addr = (await core.listCollateralPool())[0]
    pool1 = (await ethers.getContractAt("CollateralPool", pool1Addr)) as CollateralPool
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306")))
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938")))
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000")))
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", long1), u2b(toWei("0.80")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", long1), u2b(toWei("0.75")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", long1), u2b(toWei("0.70")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", short1), u2b(toWei("0.80")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", short1), u2b(toWei("0.75")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", short1), u2b(toWei("0.70")))

    // pool 2
    await core.createCollateralPool("TN2", "TS2", arb.address, 1)
    const pool2Addr = (await core.listCollateralPool())[1]
    pool2 = (await ethers.getContractAt("CollateralPool", pool2Addr)) as CollateralPool
    await core.setPoolConfig(pool2.address, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("3.46024")))
    await core.setPoolConfig(pool2.address, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-2.34434")))
    await core.setPoolConfig(pool2.address, ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000")))
    await core.setPoolConfig(pool2.address, ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001")))
    await core.setPoolConfig(pool2.address, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", long1), u2b(toWei("0.80")))
    await core.setPoolConfig(pool2.address, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", long1), u2b(toWei("0.75")))
    await core.setPoolConfig(pool2.address, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", long1), u2b(toWei("0.70")))
    await core.setPoolConfig(pool2.address, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", short1), u2b(toWei("0.80")))
    await core.setPoolConfig(pool2.address, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", short1), u2b(toWei("0.75")))
    await core.setPoolConfig(pool2.address, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", short1), u2b(toWei("0.70")))

    // markets only uses pool1
    await core.createMarket(
      long1,
      "Long1",
      true, // isLong
      [pool1.address]
    )
    await core.setMarketConfig(long1, ethers.utils.id("MM_POSITION_FEE_RATE"), u2b(toWei("0.001")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_INITIAL_MARGIN_RATE"), u2b(toWei("0.006")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_MAINTENANCE_MARGIN_RATE"), u2b(toWei("0.005")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.1")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_ORACLE_ID"), a2b(weth.address))

    await core.createMarket(
      short1,
      "Short1",
      false, // isLong
      [pool1.address]
    )
    await core.setMarketConfig(short1, ethers.utils.id("MM_POSITION_FEE_RATE"), u2b(toWei("0.001")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_INITIAL_MARGIN_RATE"), u2b(toWei("0.006")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_MAINTENANCE_MARGIN_RATE"), u2b(toWei("0.005")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.1")))
    await core.setMarketConfig(short1, ethers.utils.id("MM_ORACLE_ID"), a2b(weth.address))

    // feeDistributor
    feeDistributor = (await createContract("MockMux3FeeDistributor", [core.address])) as MockMux3FeeDistributor
    await core.setConfig(ethers.utils.id("MC_FEE_DISTRIBUTOR"), a2b(feeDistributor.address))

    // role
    await orderBook.grantRole(ethers.utils.id("BROKER_ROLE"), broker.address)
    await core.grantRole(ethers.utils.id("ORDER_BOOK_ROLE"), orderBook.address)

    // price
    await core.setMockPrice(a2b(usdc.address), toWei("1"))
    await core.setMockPrice(a2b(weth.address), toWei("1000"))
    await core.setMockPrice(a2b(arb.address), toWei("2"))
    await core.setMockPrice(a2b(btc.address), toWei("50000"))
  })

  it("1 pool mini test: +liq, +trade", async () => {
    // check the list
    {
      const pools = await core.listCollateralPool()
      expect(pools.length).to.equal(2)
      expect(pools[0]).to.equal(pool1.address)
      expect(pools[1]).to.equal(pool2.address)
    }
    {
      const markets = await core.listMarkets()
      expect(markets.length).to.equal(2)
      expect(markets[0]).to.equal(long1)
      expect(markets[1]).to.equal(short1)
    }
    {
      const pools = await core.listMarketPools(long1)
      expect(pools.length).to.equal(1)
      expect(pools[0].backedPool).to.equal(pool1.address)
    }
    {
      const pools = await core.listMarketPools(short1)
      expect(pools.length).to.equal(1)
      expect(pools[0].backedPool).to.equal(pool1.address)
    }
    // +liq usdc
    await usdc.connect(lp1).transfer(orderBook.address, toUnit("1000000", 6))
    {
      await time.increaseTo(timestampOfTest + 86400 * 2 + 0)
      const args = {
        poolAddress: pool1.address,
        rawAmount: toUnit("1000000", 6),
        isAdding: true,
        isUnwrapWeth: true,
      }
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(args)
      await expect(tx1)
        .to.emit(orderBook, "NewLiquidityOrder")
        .withArgs(lp1.address, 0, [pool1.address, args.rawAmount, args.isAdding])
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000000", 6))
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(true)
    }
    {
      await time.increaseTo(timestampOfTest + 86400 * 2 + 930)
      const tx1 = orderBook.connect(broker).fillLiquidityOrder(0)
      await expect(tx1)
        .to.emit(emitter, "AddLiquidity")
        .withArgs(
          pool1.address,
          lp1.address,
          usdc.address,
          toWei("1") /* collateralPrice */,
          toWei("100") /* feeCollateral */,
          toWei("1") /* lpPrice */,
          toWei("999900") /* share */
        )
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("100", 6)) // fee = 1000000 * 0.0001 = 100
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6))
      expect(await pool1.balanceOf(lp1.address)).to.equal(toWei("999900")) // (1000000 - fee) / 1
      expect(await pool1.balanceOf(orderBook.address)).to.equal(toWei("0"))
    }
    {
      const [poolTokens, poolBalances] = await pool1.liquidityBalances()
      expect(poolTokens[0]).to.equal(usdc.address)
      expect(poolBalances[0]).to.equal(toWei("999900"))
    }
    // open short, using usdc
    const positionId = encodePositionId(trader1.address, 0)
    await expect(orderBook.setInitialLeverage(positionId, short1, toWei("100"))).to.be.revertedWith("Not authorized")
    await orderBook.connect(trader1).setInitialLeverage(positionId, short1, toWei("100"))
    await usdc.connect(trader1).transfer(orderBook.address, toUnit("1000", 6))
    {
      const args = {
        positionId,
        marketId: short1,
        size: toWei("1"),
        flags: PositionOrderFlags.OpenPosition,
        limitPrice: toWei("1000"),
        expiration: timestampOfTest + 86400 * 2 + 930 + 300,
        lastConsumedToken: zeroAddress,
        collateralToken: usdc.address,
        collateralAmount: toUnit("1000", 6),
        withdrawUsd: toWei("0"),
        withdrawSwapToken: zeroAddress,
        withdrawSwapSlippage: toWei("0"),
        tpPriceDiff: toWei("0"),
        slPriceDiff: toWei("0"),
        tpslExpiration: timestampOfTest + 86400 * 2 + 930 + 300,
        tpslFlags: 0,
        tpslWithdrawSwapToken: zeroAddress,
        tpslWithdrawSwapSlippage: toWei("0"),
      }
      const tx1 = await orderBook.connect(trader1).placePositionOrder(args, refCode)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 1, [
          args.positionId,
          args.marketId,
          args.size,
          args.flags,
          args.limitPrice,
          args.expiration,
          args.lastConsumedToken,
          args.collateralToken,
          args.collateralAmount,
          args.withdrawUsd,
          args.withdrawSwapToken,
          args.withdrawSwapSlippage,
          args.tpPriceDiff,
          args.slPriceDiff,
          args.tpslExpiration,
          args.tpslFlags,
          args.tpslWithdrawSwapToken,
          args.tpslWithdrawSwapSlippage,
        ])
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000", 6))
      expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6))
      {
        const [poolTokens, poolBalances] = await pool1.liquidityBalances()
        expect(poolTokens[0]).to.equal(usdc.address)
        expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
      }
      // fill
      await core.setMockPrice(a2b(weth.address), toWei("2000"))
      const tx2 = orderBook.connect(broker).fillPositionOrder(1)
      await expect(tx2)
        .to.emit(core, "OpenPosition")
        .withArgs(
          trader1.address,
          positionId,
          short1,
          false, // isLong
          args.size,
          toWei("2000"), // trading price
          [pool1.address],
          [toWei("1")], // allocations
          [toWei("1")], // new size
          [toWei("2000")], // new entry
          toWei("2"), // positionFee
          toWei("0"), // borrowingFee
          [usdc.address],
          [toWei("998")]
        )
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("102", 6)) // fee = 2000 * 1 * 0.1% = 2
      expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
      expect(await usdc.balanceOf(core.address)).to.equal(toUnit("998", 6)) // collateral - fee
      {
        const collaterals = await core.listAccountCollaterals(positionId)
        expect(collaterals[0].collateralAddress).to.equal(usdc.address)
        expect(collaterals[0].collateralAmount).to.equal(toWei("998")) // fee = 2
        const positions = await core.listAccountPositions(positionId)
        expect(positions[0].marketId).to.equal(short1)
        expect(positions[0].pools[0].size).to.equal(toWei("1"))
        expect(positions[0].pools[0].entryPrice).to.equal(toWei("2000"))
        expect(positions[0].pools[0].entryBorrowing).to.equal(toWei("0"))
        const activated = await core.listActivePositionIds(0, 10)
        expect(activated.totalLength).to.equal(1)
        expect(activated.positionIds[0]).to.equal(positionId)
      }
      {
        const [poolTokens, poolBalances] = await pool1.liquidityBalances()
        expect(poolTokens[0]).to.equal(usdc.address)
        expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
      }
      {
        const shortPools = await core.listMarketPools(short1)
        expect(shortPools[0].backedPool).to.equal(pool1.address)
        const shortPoolState = await pool1.marketState(short1)
        expect(shortPoolState.isLong).to.equal(false)
        expect(shortPoolState.totalSize).to.equal(toWei("1"))
        expect(shortPoolState.averageEntryPrice).to.equal(toWei("2000"))
      }
      {
        const state = await pool1.marketState(short1)
        expect(state.isLong).to.equal(false)
        expect(state.totalSize).to.equal(toWei("1"))
        expect(state.averageEntryPrice).to.equal(toWei("2000"))
      }
    }
  })

  it("2 pool mini test: +liq, +trade, updateBorrowingFee", async () => {
    // +liq to pool1
    await usdc.connect(lp1).transfer(orderBook.address, toUnit("1000000", 6))
    {
      await time.increaseTo(timestampOfTest + 86400 * 2)
      const args = {
        poolAddress: pool1.address,
        rawAmount: toUnit("1000000", 6),
        isAdding: true,
        isUnwrapWeth: true,
      }
      await orderBook.connect(lp1).placeLiquidityOrder(args)
    }
    {
      await time.increaseTo(timestampOfTest + 86400 * 2 + 930)
      await orderBook.connect(broker).fillLiquidityOrder(0)
    }
    // append pool2 to market
    await core.appendBackedPoolsToMarket(short1, [pool2.address])
    {
      const pools = await core.listMarketPools(long1)
      expect(pools.length).to.equal(1)
      expect(pools[0].backedPool).to.equal(pool1.address)
    }
    {
      const pools = await core.listMarketPools(short1)
      expect(pools.length).to.equal(2)
      expect(pools[0].backedPool).to.equal(pool1.address)
      expect(pools[1].backedPool).to.equal(pool2.address)
    }
    // +liq to pool2
    await arb.connect(lp1).transfer(orderBook.address, toUnit("500000", 18))
    {
      const args = {
        poolAddress: pool2.address,
        rawAmount: toUnit("500000", 18),
        isAdding: true,
        isUnwrapWeth: true,
      }
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(args)
      await expect(tx1)
        .to.emit(orderBook, "NewLiquidityOrder")
        .withArgs(lp1.address, 1, [pool2.address, args.rawAmount, args.isAdding])
      expect(await arb.balanceOf(lp1.address)).to.equal(toUnit("500000", 18))
      expect(await arb.balanceOf(orderBook.address)).to.equal(toUnit("500000", 18))
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(true)
    }
    {
      await time.increaseTo(timestampOfTest + 86400 * 2 + 930 + 930)
      const tx1 = orderBook.connect(broker).fillLiquidityOrder(1)
      await expect(tx1)
        .to.emit(emitter, "AddLiquidity")
        .withArgs(
          pool2.address,
          lp1.address,
          arb.address,
          toWei("2") /* collateralPrice */,
          toWei("50") /* feeCollateral */,
          toWei("1") /* lpPrice */,
          toWei("999900") /* share */
        )
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(false)
      expect(await arb.balanceOf(lp1.address)).to.equal(toUnit("500000", 18))
      expect(await arb.balanceOf(feeDistributor.address)).to.equal(toUnit("50", 18)) // fee = 500000 * 0.0001
      expect(await arb.balanceOf(orderBook.address)).to.equal(toUnit("0", 18))
      expect(await arb.balanceOf(pool2.address)).to.equal(toUnit("499950", 18))
      expect(await pool2.balanceOf(lp1.address)).to.equal(toWei("999900")) // (1000000 - fee) / 1
      expect(await pool2.balanceOf(orderBook.address)).to.equal(toWei("0"))
    }
    {
      const [poolTokens, poolBalances] = await pool2.liquidityBalances()
      expect(poolTokens[1]).to.equal(arb.address)
      expect(poolBalances[1]).to.equal(toWei("499950"))
    }
    // open short, using 2 usdc+arb
    const positionId = encodePositionId(trader1.address, 0)
    await orderBook.connect(trader1).setInitialLeverage(positionId, short1, toWei("100"))
    await usdc.connect(trader1).transfer(orderBook.address, toUnit("1000", 6))
    {
      const args = {
        positionId,
        marketId: short1,
        size: toWei("1"),
        flags: PositionOrderFlags.OpenPosition,
        limitPrice: toWei("1000"),
        expiration: timestampOfTest + 86400 * 2 + 930 + 930 + 300,
        lastConsumedToken: zeroAddress,
        collateralToken: usdc.address,
        collateralAmount: toUnit("1000", 6),
        withdrawUsd: toWei("0"),
        withdrawSwapToken: zeroAddress,
        withdrawSwapSlippage: toWei("0"),
        tpPriceDiff: toWei("0"),
        slPriceDiff: toWei("0"),
        tpslExpiration: timestampOfTest + 86400 * 2 + 930 + 930 + 300,
        tpslFlags: 0,
        tpslWithdrawSwapToken: zeroAddress,
        tpslWithdrawSwapSlippage: toWei("0"),
      }
      const tx1 = await orderBook.connect(trader1).placePositionOrder(args, refCode)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 2, [
          args.positionId,
          args.marketId,
          args.size,
          args.flags,
          args.limitPrice,
          args.expiration,
          args.lastConsumedToken,
          args.collateralToken,
          args.collateralAmount,
          args.withdrawUsd,
          args.withdrawSwapToken,
          args.withdrawSwapSlippage,
          args.tpPriceDiff,
          args.slPriceDiff,
          args.tpslExpiration,
          args.tpslFlags,
          args.tpslWithdrawSwapToken,
          args.tpslWithdrawSwapSlippage,
        ])
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000", 6))
      expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6))
      {
        const [poolTokens, poolBalances] = await pool1.liquidityBalances()
        expect(poolTokens[0]).to.equal(usdc.address)
        expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
      }
      // fill
      await core.setMockPrice(a2b(weth.address), toWei("2000"))
      const tx2 = orderBook.connect(broker).fillPositionOrder(2)
      await expect(tx2)
        .to.emit(core, "OpenPosition")
        .withArgs(
          trader1.address,
          positionId,
          short1,
          false, // isLong
          args.size,
          toWei("2000"), // trading price
          [pool1.address],
          [toWei("1")], // allocations
          [toWei("1")], // new size
          [toWei("2000")], // new entry
          toWei("2"), // positionFeeUsd
          toWei("0"), // borrowingFeeUsd
          [usdc.address],
          [toWei("998")]
        )
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("102", 6)) // fee = 2000 * 1 * 0.1% = 2
      expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
      expect(await usdc.balanceOf(core.address)).to.equal(toUnit("998", 6)) // collateral - fee
      {
        const collaterals = await core.listAccountCollaterals(positionId)
        expect(collaterals[0].collateralAddress).to.equal(usdc.address)
        expect(collaterals[0].collateralAmount).to.equal(toWei("998")) // fee = 2
        const positions = await core.listAccountPositions(positionId)
        expect(positions[0].marketId).to.equal(short1)
        expect(positions[0].pools[0].poolAddress).to.equal(pool1.address)
        expect(positions[0].pools[0].size).to.equal(toWei("1"))
        expect(positions[0].pools[0].entryPrice).to.equal(toWei("2000"))
        expect(positions[0].pools[0].entryBorrowing).to.equal(toWei("0"))
        expect(positions[0].pools[1].poolAddress).to.equal(pool2.address)
        expect(positions[0].pools[1].size).to.equal(toWei("0"))
        expect(positions[0].pools[1].entryPrice).to.equal(toWei("0"))
        expect(positions[0].pools[1].entryBorrowing).to.equal(toWei("0"))
        const activated = await core.listActivePositionIds(0, 10)
        expect(activated.totalLength).to.equal(1)
        expect(activated.positionIds[0]).to.equal(positionId)
      }
      {
        const [poolTokens, poolBalances] = await pool1.liquidityBalances()
        expect(poolTokens[0]).to.equal(usdc.address)
        expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
      }
      {
        const state = await pool1.marketState(short1)
        expect(state.isLong).to.equal(false)
        expect(state.totalSize).to.equal(toWei("1"))
        expect(state.averageEntryPrice).to.equal(toWei("2000"))
      }
      {
        const state = await pool2.marketState(short1)
        expect(state.isLong).to.equal(false)
        expect(state.totalSize).to.equal(toWei("0"))
        expect(state.averageEntryPrice).to.equal(toWei("0"))
      }
    }
    {
      await time.increaseTo(timestampOfTest + 86400 * 2 + 930 + 930 + 3600)
      await expect(core.updateBorrowingFee(positionId, short1, zeroAddress, false)).to.revertedWith("AccessControl")
      await orderBook.connect(broker).updateBorrowingFee(positionId, short1, zeroAddress, false)
      {
        const collaterals = await core.listAccountCollaterals(positionId)
        expect(collaterals[0].collateralAddress).to.equal(usdc.address)
        expect(collaterals[0].collateralAmount).to.equal(toWei("997.976851835005198000"))
      }
    }
  })
})
