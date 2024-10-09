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
    await core.createCollateralPool("TN1", "TS1", usdc.address, 6)
    const pool1Addr = (await core.listCollateralPool())[0]
    pool1 = (await ethers.getContractAt("CollateralPool", pool1Addr)) as CollateralPool
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
    await core.createCollateralPool("TN2", "TS2", arb.address, 18)
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
    await core.setMarketConfig(long1, ethers.utils.id("MM_MAX_INITIAL_LEVERAGE"), u2b(toWei("100")))

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
    await core.setMarketConfig(short1, ethers.utils.id("MM_MAX_INITIAL_LEVERAGE"), u2b(toWei("100")))

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

    // feeDistributor
    feeDistributor = (await createContract("MockFeeDistributor", [core.address])) as MockFeeDistributor
    await core.setConfig(ethers.utils.id("MC_FEE_DISTRIBUTOR"), a2b(feeDistributor.address))

    // role
    await orderBook.grantRole(ethers.utils.id("BROKER_ROLE"), broker.address)
    await core.grantRole(ethers.utils.id("ORDER_BOOK_ROLE"), orderBook.address)

    // price
    await core.setMockPrice(long1, toWei("1000"))
    await core.setMockPrice(short1, toWei("1000"))
    await core.setMockPrice(a2b(usdc.address), toWei("1"))
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
      await time.increaseTo(timestampOfTest + 86400 * 2 + 905)
      const tx1 = orderBook.connect(broker).fillLiquidityOrder(0, [])
      await expect(tx1)
        .to.emit(pool1, "AddLiquidity")
        .withArgs(
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
      expect(await pool1.liquidityBalance()).to.equal(toWei("999900"))
    }
    // open short, using usdc
    const positionId = encodePositionId(trader1.address, 0)
    await usdc.connect(trader1).transfer(orderBook.address, toUnit("1000", 6))
    {
      const args = {
        positionId,
        marketId: short1,
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
      const tx1 = await orderBook.connect(trader1).placePositionOrder(args, refCode)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 1, [
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
      expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6))
      expect(await pool1.liquidityBalance()).to.equal(toWei("999900")) // unchanged
      // fill
      await core.setMockPrice(short1, toWei("2000")) // TODO: use oracle builder
      const tx2 = orderBook.connect(broker).fillPositionOrder(1, [])
      await expect(tx2)
        .to.emit(core, "OpenPosition")
        .withArgs(
          trader1.address,
          positionId,
          short1,
          false, // isLong
          args.size,
          [toWei("1")], // allocations
          toWei("2000"), // trading price
          toWei("2000"), // new entry
          toWei("1"), // new size
          [usdc.address], // positionFeeAddress
          [toWei("2")], // positionFeeAmount
          [], // borrowingFeeAddress
          [] // borrowingFeeAmount
        )
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("102", 6)) // fee = 2000 * 1 * 0.1% = 2
      expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
      expect(await usdc.balanceOf(core.address)).to.equal(toUnit("998", 6)) // collateral - fee
      {
        const collaterals = await core.listAccountCollaterals(positionId)
        expect(collaterals.collateralAddresses[0]).to.equal(usdc.address)
        expect(collaterals.collateralAmounts[0]).to.equal(toWei("998")) // fee = 2
        const positions = await core.listAccountPositions(positionId)
        expect(positions.marketIds[0]).to.equal(short1)
        expect(positions.positions[0].size).to.equal(toWei("1"))
        expect(positions.positions[0].entryPrice).to.equal(toWei("2000"))
        expect(positions.positions[0].entryBorrowing).to.equal(toWei("0"))
      }
      expect(await pool1.liquidityBalance()).to.equal(toWei("999900")) // unchanged
      {
        const shortPools = await core.listMarketPools(short1)
        expect(shortPools[0].backedPool).to.equal(pool1.address)
        expect(shortPools[0].totalSize).to.equal(toWei("1"))
        expect(shortPools[0].unpaidBorrowingFeeUsd).to.equal(toWei("0"))
        const shortPoolState = await pool1.marketState(short1)
        expect(shortPoolState.isLong).to.equal(false)
        expect(shortPoolState.totalSize).to.equal(toWei("1"))
        expect(shortPoolState.averageEntryPrice).to.equal(toWei("2000"))
      }
    }
  })

  it("2 pool mini test: +liq, +trade", async () => {
    // +liq pool1
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
      await time.increaseTo(timestampOfTest + 86400 * 2 + 905)
      await orderBook.connect(broker).fillLiquidityOrder(0, [])
    }
    // +liq pool2
    await core.appendBackedPoolsToMarket(short1, [pool2.address])
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
      expect(pools.length).to.equal(2)
      expect(pools[0].backedPool).to.equal(pool1.address)
      expect(pools[1].backedPool).to.equal(pool2.address)
    }
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
      await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 905)
      const tx1 = orderBook.connect(broker).fillLiquidityOrder(1, [])
      await expect(tx1)
        .to.emit(pool2, "AddLiquidity")
        .withArgs(
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
      expect(await pool2.liquidityBalance()).to.equal(toWei("499950"))
    }
    // open short, using 2 usdc+arb
    const positionId = encodePositionId(trader1.address, 0)
    await usdc.connect(trader1).transfer(orderBook.address, toUnit("1000", 6))
    {
      const args = {
        positionId,
        marketId: short1,
        size: toWei("1"),
        flags: PositionOrderFlags.OpenPosition,
        limitPrice: toWei("1000"),
        tpPrice: "0",
        slPrice: "0",
        expiration: timestampOfTest + 86400 * 2 + 905 + 905 + 300,
        tpslExpiration: timestampOfTest + 86400 * 2 + 905 + 905 + 300,
        profitTokenId: 0,
        tpslProfitTokenId: 0,
        initialLeverage: toWei("100"),
        collateralToken: usdc.address,
        collateralAmount: toUnit("1000", 6),
        profitToken: zeroAddress,
        tpslProfitToken: zeroAddress,
      }
      const tx1 = await orderBook.connect(trader1).placePositionOrder(args, refCode)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 2, [
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
      expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6))
      expect(await pool1.liquidityBalance()).to.equal(toWei("999900")) // unchanged
      // fill
      await core.setMockPrice(short1, toWei("2000")) // TODO: use oracle builder
      const tx2 = orderBook.connect(broker).fillPositionOrder(2, [])
      await expect(tx2)
        .to.emit(core, "OpenPosition")
        .withArgs(
          trader1.address,
          positionId,
          short1,
          false, // isLong
          args.size,
          [toWei("1")], // allocations
          toWei("2000"), // trading price
          toWei("2000"), // new entry
          toWei("1"), // new size
          [usdc.address], // positionFeeAddress
          [toWei("2")], // positionFeeUsd
          [], // borrowingFeeAddress
          [] // borrowingFeeAmount
        )
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("102", 6)) // fee = 2000 * 1 * 0.1% = 2
      expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
      expect(await usdc.balanceOf(core.address)).to.equal(toUnit("998", 6)) // collateral - fee
      {
        const collaterals = await core.listAccountCollaterals(positionId)
        expect(collaterals.collateralAddresses[0]).to.equal(usdc.address)
        expect(collaterals.collateralAmounts[0]).to.equal(toWei("998")) // fee = 2
        const positions = await core.listAccountPositions(positionId)
        expect(positions.marketIds[0]).to.equal(short1)
        expect(positions.positions[0].size).to.equal(toWei("1"))
        expect(positions.positions[0].entryPrice).to.equal(toWei("2000"))
        expect(positions.positions[0].entryBorrowing).to.equal(toWei("0"))
      }
      expect(await pool1.liquidityBalance()).to.equal(toWei("999900")) // unchanged
      {
        const shortPools = await core.listMarketPools(short1)
        expect(shortPools[0].backedPool).to.equal(pool1.address)
        expect(shortPools[0].totalSize).to.equal(toWei("1"))
        expect(shortPools[0].unpaidBorrowingFeeUsd).to.equal(toWei("0"))
        expect(shortPools[1].backedPool).to.equal(pool2.address)
        expect(shortPools[1].totalSize).to.equal(toWei("0"))
        expect(shortPools[1].unpaidBorrowingFeeUsd).to.equal(toWei("0"))
        const shortPool1State = await pool1.marketState(short1)
        expect(shortPool1State.isLong).to.equal(false)
        expect(shortPool1State.totalSize).to.equal(toWei("1"))
        expect(shortPool1State.averageEntryPrice).to.equal(toWei("2000"))
        const shortPool2State = await pool2.marketState(short1)
        expect(shortPool2State.isLong).to.equal(false)
        expect(shortPool2State.totalSize).to.equal(toWei("0"))
        expect(shortPool2State.averageEntryPrice).to.equal(toWei("0"))
      }
    }
  })
})
