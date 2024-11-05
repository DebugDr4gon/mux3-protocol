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

describe("Trade", () => {
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
    arb = (await createContract("MockERC20", ["ARB", "ARB", 18])) as MockERC20
    btc = (await createContract("MockERC20", ["BTC", "BTC", 8])) as MockERC20
    await usdc.mint(lp1.address, toUnit("1000000", 6))
    await usdc.mint(trader1.address, toUnit("100000", 6))
    await usdc.mint(trader2.address, toUnit("100000", 6))
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
    await core.setCollateralTokenStatus(usdc.address, true)
    await core.setCollateralTokenStatus(arb.address, true)
    await core.setCollateralTokenStatus(btc.address, true)
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

    // pool 1
    await core.createCollateralPool("TN0", "TS0", usdc.address)
    const poolAddr = (await core.listCollateralPool())[0]
    pool1 = (await ethers.getContractAt("CollateralPool", poolAddr)) as CollateralPool
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("10")))
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-7")))
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_IS_HIGH_PRIORITY"), u2b(ethers.BigNumber.from(0)))
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
    await core.setPoolConfig(pool2.address, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6")))
    await core.setPoolConfig(pool2.address, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6")))
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
    await core.createCollateralPool("TN2", "TS2", btc.address)
    const pool3Addr = (await core.listCollateralPool())[2]
    pool3 = (await ethers.getContractAt("CollateralPool", pool3Addr)) as CollateralPool
    await core.setPoolConfig(pool3.address, ethers.utils.id("MCP_BORROWING_BASE_APY"), u2b(toWei("0.10")))
    await core.setPoolConfig(pool3.address, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("2.2")))
    await core.setPoolConfig(pool3.address, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-3")))
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
      ).to.revertedWith("Zero collateral")
      const tx1 = await orderBook.connect(trader1).depositCollateral(positionId, usdc.address, toUnit("1000", 6))
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(core.address)).to.equal(toUnit("1000", 6))
      const collaterals = await core.listAccountCollaterals(positionId)
      expect(collaterals[0].collateralAddress).to.equal(usdc.address)
      expect(collaterals[0].collateralAmount).to.equal(toWei("1000"))
      const positions = await core.listAccountPositions(positionId)
      expect(positions.length).to.equal(0)
    }
    {
      const tx1 = await orderBook.connect(trader1).depositCollateral(positionId, arb.address, toUnit("500", 18))
      expect(await arb.balanceOf(trader1.address)).to.equal(toUnit("99500", 18))
      expect(await arb.balanceOf(orderBook.address)).to.equal(toUnit("0", 18))
      expect(await arb.balanceOf(core.address)).to.equal(toUnit("500", 18))
      const collaterals = await core.listAccountCollaterals(positionId)
      expect(collaterals[0].collateralAddress).to.equal(usdc.address)
      expect(collaterals[0].collateralAmount).to.equal(toWei("1000"))
      expect(collaterals[1].collateralAddress).to.equal(arb.address)
      expect(collaterals[1].collateralAmount).to.equal(toWei("500"))
      const positions = await core.listAccountPositions(positionId)
      expect(positions.length).to.equal(0)
    }
    {
      const args = {
        positionId,
        isUnwrapWeth: false,
        withdrawSwapToken: zeroAddress,
        withdrawSwapSlippage: toWei("0"),
      }
      await expect(orderBook.connect(lp1).withdrawAllCollateral(args)).to.revertedWith("Not authorized")
      await orderBook.connect(trader1).withdrawAllCollateral(args)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("100000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(core.address)).to.equal(toUnit("0", 6))
      expect(await arb.balanceOf(trader1.address)).to.equal(toUnit("100000", 18))
      expect(await arb.balanceOf(orderBook.address)).to.equal(toUnit("0", 18))
      expect(await arb.balanceOf(core.address)).to.equal(toUnit("0", 18))
      const collaterals = await core.listAccountCollaterals(positionId)
      expect(collaterals.length).to.equal(0)
      const positions = await core.listAccountPositions(positionId)
      expect(positions.length).to.equal(0)
    }
  })

  describe("add liquidity to 3 pools and test more", () => {
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
        await orderBook.connect(broker).fillLiquidityOrder(0)
        expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("100", 6)) // fee = 1000000 * 0.01% = 100
        expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6))
      }
      {
        const [poolTokens, poolBalances] = await pool1.liquidityBalances()
        expect(poolTokens[0]).to.equal(usdc.address)
        expect(poolBalances[0]).to.equal(toWei("999900")) // 1000000 - fee
      }
      expect(await pool1.balanceOf(lp1.address)).to.equal(toWei("999900"))
      expect(await pool1.totalSupply()).to.equal(toWei("999900"))
      expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("999900"))
      {
        await orderBook.connect(broker).fillLiquidityOrder(1)
        expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("200", 6)) // fee = 1000000 * 0.01% = 100
        expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6))
      }
      {
        const [poolTokens, poolBalances] = await pool2.liquidityBalances()
        expect(poolTokens[0]).to.equal(usdc.address)
        expect(poolBalances[0]).to.equal(toWei("999900")) // 1000000 - fee
      }
      expect(await pool2.balanceOf(lp1.address)).to.equal(toWei("999900"))
      expect(await pool2.totalSupply()).to.equal(toWei("999900"))
      expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("999900"))
      {
        await orderBook.connect(broker).fillLiquidityOrder(2)
        expect(await btc.balanceOf(feeDistributor.address)).to.equal(toUnit("0.002", 8)) // fee = 20 * 0.01% = 0.002
        expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8))
      }
      {
        const [poolTokens, poolBalances] = await pool3.liquidityBalances()
        expect(poolTokens[2]).to.equal(btc.address)
        expect(poolBalances[2]).to.equal(toWei("19.998")) // 20 - fee
      }
      expect(await pool3.balanceOf(lp1.address)).to.equal(toWei("999900"))
      expect(await pool3.totalSupply()).to.equal(toWei("999900"))
      expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("999900"))
      {
        const state = await pool1.marketState(long1)
        expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
      }
      {
        const state = await pool1.marketState(short1)
        expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
      }
    })

    it("remove liquidity", async () => {
      {
        const args = { poolAddress: pool3.address, rawAmount: toWei("100"), isAdding: false, isUnwrapWeth: false }
        await expect(orderBook.connect(lp1).placeLiquidityOrder({ ...args, rawAmount: toWei("0") })).to.revertedWith(
          "Zero amount"
        )
        await pool3.connect(lp1).transfer(orderBook.address, toWei("100"))
        const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(args)
        await expect(tx1)
          .to.emit(orderBook, "NewLiquidityOrder")
          .withArgs(lp1.address, 3, [args.poolAddress, args.rawAmount, args.isAdding])
        expect(await pool3.balanceOf(lp1.address)).to.equal(toWei("999800")) // 999900 - 100
        expect(await pool3.balanceOf(orderBook.address)).to.equal(toWei("100"))
      }
      expect(await btc.balanceOf(lp1.address)).to.equal(toUnit("999980", 8)) // unchanged
      expect(await pool3.totalSupply()).to.equal(toWei("999900")) // unchanged
      expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("999900")) // unchanged
      await core.setMockPrice(a2b(btc.address), toWei("40000"))
      expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("799920")) // aum = 19.998 * 40000 = 799920, nav = 799920 / 999900 = 0.8
      {
        await expect(orderBook.connect(broker).fillLiquidityOrder(3)).to.revertedWith("lock period")
        await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 905)
        const tx1 = await orderBook.connect(broker).fillLiquidityOrder(3) // return 100 * nav / 40000 = 0.002, fee = * 0.01% = 0.0000002
        expect(await btc.balanceOf(lp1.address)).to.equal(toUnit("999980.0019998", 8)) // 999980 + 0.002 - fee
        expect(await btc.balanceOf(feeDistributor.address)).to.equal(toUnit("0.0020002", 8)) // +fee
        expect(await btc.balanceOf(orderBook.address)).to.equal(toUnit("0", 8))
        expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.996", 8)) // 19.998 - 100 * nav / 40000
        expect(await pool3.balanceOf(lp1.address)).to.equal(toWei("999800")) // unchanged
        expect(await pool3.balanceOf(orderBook.address)).to.equal(toWei("0"))
      }
      {
        const [poolTokens, poolBalances] = await pool3.liquidityBalances()
        expect(poolTokens[2]).to.equal(btc.address)
        expect(poolBalances[2]).to.equal(toWei("19.996")) // 19.998 - 100 * nav / 40000
      }
      expect(await pool3.totalSupply()).to.equal(toWei("999800")) // 999900 - 100
      expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("799840")) // 19.996 * 40000
    })

    it("open long: should set trader im before fill a position order", async () => {
      const positionId = encodePositionId(trader1.address, 0)
      await usdc.connect(trader1).transfer(orderBook.address, toUnit("10000", 6))
      {
        const args = {
          positionId,
          marketId: long1,
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 300,
          lastConsumedToken: zeroAddress,
          collateralToken: usdc.address,
          collateralAmount: toUnit("10000", 6),
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
        await expect(orderBook.connect(broker).fillPositionOrder(3)).to.revertedWith("EssentialConfigNotSet")
      }
    })

    it("open long: exceeds initial leverage", async () => {
      const positionId = encodePositionId(trader1.address, 0)
      await orderBook.connect(trader1).setInitialLeverage(positionId, long1, toWei("10"))
      await usdc.connect(trader1).transfer(orderBook.address, toUnit("1000", 6))
      {
        const args = {
          positionId,
          marketId: long1,
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 300,
          lastConsumedToken: zeroAddress,
          collateralToken: usdc.address,
          collateralAmount: toUnit("1000", 6),
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
        await expect(orderBook.connect(broker).fillPositionOrder(3)).to.revertedWith("UnsafePositionAccount")
      }
    })

    it("open long: limit price unmatched", async () => {
      const positionId = encodePositionId(trader1.address, 0)
      await orderBook.connect(trader1).setInitialLeverage(positionId, long1, toWei("100"))
      await usdc.connect(trader1).transfer(orderBook.address, toUnit("1000", 6))
      {
        const args = {
          positionId,
          marketId: long1,
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 300,
          lastConsumedToken: zeroAddress,
          collateralToken: usdc.address,
          collateralAmount: toUnit("1000", 6),
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
        await core.setMockPrice(a2b(btc.address), toWei("50001"))
        await orderBook.connect(trader1).placePositionOrder(args, refCode)
        await expect(orderBook.connect(broker).fillPositionOrder(3)).to.revertedWith("limitPrice")
      }
    })

    it("open short: limit price unmatched", async () => {
      const positionId = encodePositionId(trader1.address, 0)
      await orderBook.connect(trader1).setInitialLeverage(positionId, short1, toWei("100"))
      await usdc.connect(trader1).transfer(orderBook.address, toUnit("1000", 6))
      {
        const args = {
          positionId,
          marketId: short1,
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 300,
          lastConsumedToken: zeroAddress,
          collateralToken: usdc.address,
          collateralAmount: toUnit("1000", 6),
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
        await core.setMockPrice(a2b(btc.address), toWei("49999"))
        await orderBook.connect(trader1).placePositionOrder(args, refCode)
        await expect(orderBook.connect(broker).fillPositionOrder(3)).to.revertedWith("limitPrice")
      }
    })

    describe("long a little and test more", () => {
      let positionId = ""
      beforeEach(async () => {
        // open long btc, using usdc
        positionId = encodePositionId(trader1.address, 0)
        await orderBook.connect(trader1).setInitialLeverage(positionId, long1, toWei("100"))
        await usdc.connect(trader1).transfer(orderBook.address, toUnit("10000", 6))
        const args = {
          positionId,
          marketId: long1,
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 300,
          lastConsumedToken: zeroAddress,
          collateralToken: usdc.address,
          collateralAmount: toUnit("10000", 6),
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
        {
          await orderBook.connect(trader1).placePositionOrder(args, refCode)
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // - 10000
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("200", 6)) // unchanged
          expect(await usdc.balanceOf(core.address)).to.equal(toUnit("0", 6)) // unchanged
          expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
          expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6)) // unchanged
          expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
        }
        {
          const [poolTokens, poolBalances] = await pool1.liquidityBalances()
          expect(poolTokens[0]).to.equal(usdc.address)
          expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
        }
        {
          const [poolTokens, poolBalances] = await pool2.liquidityBalances()
          expect(poolTokens[0]).to.equal(usdc.address)
          expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
        }
        {
          const [poolTokens, poolBalances] = await pool3.liquidityBalances()
          expect(poolTokens[2]).to.equal(btc.address)
          expect(poolBalances[2]).to.equal(toWei("19.998")) // unchanged
        }
        {
          // fee = 50000 * 1 * 0.1% = 50
          await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 30)
          await orderBook.connect(broker).fillPositionOrder(3)
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("250", 6)) // + 50
          expect(await usdc.balanceOf(core.address)).to.equal(toUnit("9950", 6)) // at least collateral
          expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
          {
            const state = await pool1.marketState(long1)
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            const state = await pool1.marketState(short1)
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            const collaterals = await core.listAccountCollaterals(positionId)
            expect(collaterals[0].collateralAddress).to.equal(usdc.address)
            expect(collaterals[0].collateralAmount).to.equal(toWei("9950")) // collateral - fee = 10000 - 50
            const positions = await core.listAccountPositions(positionId)
            expect(positions[0].marketId).to.equal(long1)
            expect(positions[0].pools[0].size).to.equal(toWei("1"))
            expect(positions[0].pools[0].entryPrice).to.equal(toWei("50000"))
            expect(positions[0].pools[0].entryBorrowing).to.equal(toWei("0"))
          }
          {
            const collateralsAndPositions = await core.listAccountCollateralsAndPositionsOf(trader1.address)
            expect(collateralsAndPositions.length).to.equal(1)
            expect(collateralsAndPositions[0].positionId).to.equal(positionId)
            expect(collateralsAndPositions[0].collaterals[0].collateralAddress).to.equal(usdc.address)
            expect(collateralsAndPositions[0].collaterals[0].collateralAmount).to.equal(toWei("9950"))
            expect(collateralsAndPositions[0].positions[0].pools[0].size).to.equal(toWei("1"))
            expect(collateralsAndPositions[0].positions[0].pools[0].entryPrice).to.equal(toWei("50000"))
            expect(collateralsAndPositions[0].positions[0].pools[0].entryBorrowing).to.equal(toWei("0"))
          }
          {
            const state = await pool1.marketState(long1)
            expect(state.isLong).to.equal(true)
            expect(state.totalSize).to.equal(toWei("1"))
            expect(state.averageEntryPrice).to.equal(toWei("50000"))
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            const state = await pool2.marketState(long1)
            expect(state.isLong).to.equal(true)
            expect(state.totalSize).to.equal(toWei("0"))
            expect(state.averageEntryPrice).to.equal(toWei("0"))
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            const state = await pool3.marketState(long1)
            expect(state.isLong).to.equal(true)
            expect(state.totalSize).to.equal(toWei("0"))
            expect(state.averageEntryPrice).to.equal(toWei("0"))
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("999900")) // unchanged
            expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("999900")) // unchanged
            expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("999900")) // unchanged
          }
        }
      })

      it("open position cause reserved > aum", async () => {
        const positionId = encodePositionId(trader1.address, 0)
        await usdc.mint(orderBook.address, toUnit("1000000", 6))
        const args = {
          positionId,
          marketId: long1,
          size: toWei("75"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 905 + 300,
          lastConsumedToken: zeroAddress,
          collateralToken: usdc.address,
          collateralAmount: toUnit("1000000", 6),
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
        {
          await orderBook.connect(trader1).placePositionOrder(args, refCode)
        }
        {
          await expect(orderBook.connect(broker).fillPositionOrder(4)).to.revertedWith("ExpBorrow: full")
        }
      })

      describe("the same trader longs again, allocate into 2 pools", () => {
        beforeEach(async () => {
          const positionId = encodePositionId(trader1.address, 0)
          await usdc.mint(orderBook.address, toUnit("100000", 6))
          const args = {
            positionId,
            marketId: long1,
            size: toWei("20"),
            flags: PositionOrderFlags.OpenPosition,
            limitPrice: toWei("51000"),
            expiration: timestampOfTest + 86400 * 2 + 905 + 300,
            lastConsumedToken: zeroAddress,
            collateralToken: usdc.address,
            collateralAmount: toUnit("100000", 6),
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
          {
            await orderBook.connect(trader1).placePositionOrder(args, refCode)
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("250", 6)) // unchanged
            expect(await usdc.balanceOf(core.address)).to.equal(toUnit("9950", 6)) // unchanged
            expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
            expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6)) // unchanged
            expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
          }
          {
            const [poolTokens, poolBalances] = await pool1.liquidityBalances()
            expect(poolTokens[0]).to.equal(usdc.address)
            expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
          }
          {
            const [poolTokens, poolBalances] = await pool2.liquidityBalances()
            expect(poolTokens[0]).to.equal(usdc.address)
            expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
          }
          {
            const [poolTokens, poolBalances] = await pool3.liquidityBalances()
            expect(poolTokens[2]).to.equal(btc.address)
            expect(poolBalances[2]).to.equal(toWei("19.998")) // unchanged
          }
          await core.setMockPrice(a2b(btc.address), toWei("50500"))
          {
            // fee = 50500 * 20 * 0.1% = 1010
            await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 30 + 30)
            await orderBook.connect(broker).fillPositionOrder(4)
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("1260", 6)) // 250 + 1010
            expect(await usdc.balanceOf(core.address)).to.equal(toUnit("108940", 6)) // at least collateral
            expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
            {
              const [poolTokens, poolBalances] = await pool1.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
            }
            {
              const marketInfo1 = await pool1.marketState(long1)
              expect(marketInfo1.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
            }
            {
              const marketInfo2 = await pool2.marketState(long1)
              expect(marketInfo2.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
            }
            // 10 * 9.4219 * 50500 * 0.80 / 999900 - 7 = -3.1931717
            // 6 * 11.5781 * 50500 * 0.80 / 999900 - 6 = -3.1931878
            // 2.2 * 0 - 3
            {
              const collaterals = await core.listAccountCollaterals(positionId)
              expect(collaterals[0].collateralAddress).to.equal(usdc.address)
              expect(collaterals[0].collateralAmount).to.equal(toWei("108940")) // collateral - fee = 9950 + 100000 - 1010
              const positions = await core.listAccountPositions(positionId)
              expect(positions[0].marketId).to.equal(long1)
              expect(positions[0].pools[0].size).to.equal(toWei("9.4219"))
              expect(positions[0].pools[0].entryPrice).to.equal(toWei("50446.932147443721542364")) // (50000 * 1 + 50500 * 8.4219) / 9.4219
              expect(positions[0].pools[0].entryBorrowing).to.equal(toWei("0"))
              expect(positions[0].pools[1].size).to.equal(toWei("11.5781"))
              expect(positions[0].pools[1].entryPrice).to.equal(toWei("50500"))
              expect(positions[0].pools[1].entryBorrowing).to.equal(toWei("0"))
            }
            {
              const state = await pool1.marketState(long1)
              expect(state.isLong).to.equal(true)
              expect(state.totalSize).to.equal(toWei("9.4219"))
              expect(state.averageEntryPrice).to.equal(toWei("50446.932147443721542364"))
            }
            {
              const state = await pool2.marketState(long1)
              expect(state.isLong).to.equal(true)
              expect(state.totalSize).to.equal(toWei("11.5781"))
              expect(state.averageEntryPrice).to.equal(toWei("50500"))
            }
            {
              const state = await pool3.marketState(long1)
              expect(state.isLong).to.equal(true)
              expect(state.totalSize).to.equal(toWei("0"))
              expect(state.averageEntryPrice).to.equal(toWei("0"))
            }
            {
              expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("999400")) // 999900 - (50500 - 50446.932147443721542364) * 9.4219
              expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("999900")) // 999900 - (50500 - 50500) * 11.5781
              expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("1009899")) // 19.998 * 50500
            }
          }
        })

        it("close half (profit), close all (profit)", async () => {
          // close half
          {
            const args = {
              positionId,
              marketId: long1,
              size: toWei("10"),
              flags: PositionOrderFlags.WithdrawAllIfEmpty,
              limitPrice: toWei("55000"),
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
            {
              await orderBook.connect(trader1).placePositionOrder(args, refCode)
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("1260", 6)) // unchanged
              expect(await usdc.balanceOf(core.address)).to.equal(toUnit("108940", 6)) // unchanged
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6)) // unchanged
            }
            {
              const [poolTokens, poolBalances] = await pool1.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
            }
            {
              const [poolTokens, poolBalances] = await pool2.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
            }
            await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 86400 * 7)
            await expect(orderBook.connect(broker).fillPositionOrder(5)).to.revertedWith("limit")
            await core.setMockPrice(a2b(btc.address), toWei("60000"))
            {
              expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("909891.95")) // 999900 - (60000 - 50446.932147443721542364) * 9.4219
              expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("889908.05")) // 999900 - (60000 - 50500) * 11.5781
              expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("1199880")) // 19.998 * 60000
            }
            {
              // fr1 0.10 + exp(10 * 9.4219 * 60000 * 0.80 / 999900 - 7) = 0.183991833628738928
              // fr2 0.10 + exp(6 * 11.5781 * 60000 * 0.80 / 999900 - 6) = 0.169587263966612892
              // acc1 0.183991833628738928 * 7 / 365 = 0.003528610507948417
              // acc2 0.169587263966612892 * 7 / 365 = 0.003252358487030932
              // borrowing 60000 * 9.4219 * 0.003528610507948417 + 60000 * 11.5781 * 0.003252358487030932 = 4254.140828611921435290
              // position fee = 60000 * 10 * 0.1% = 600
              // fees = 600 + 4254.140828611921435290 = 4854.140828611921435290
              // Δsize1 =  9.4219 / (9.4219 + 11.5781) * 10 = 4.4866
              // Δsize2 = 11.5781 / (9.4219 + 11.5781) * 10 = 5.5134
              // pnl1 = (60000 - 50446.932147443721542364) * 4.4866 = 42860.794227278998928029
              // pnl2 = (60000 - 50500) * 5.5134 = 52377.3
              const tx = await orderBook.connect(broker).fillPositionOrder(5)
              // {
              //   for (const i of (await (await tx).wait()).events!) {
              //     if (i.topics[0] === "6a95c0d2b601b7c5cc8e4377c4f827c7a02e15e0f30f3e4e6e7ff6253ddbe72d") {
              //       console.log(core.interface.parseLog(i))
              //     }
              //   }
              // }
              await expect(tx).to.emit(pool1, "UpdateMarketBorrowing").withArgs(
                long1,
                toWei("0.183991833628738928"), // apy
                toWei("0.003528610507948417") // acc
              )
              await expect(tx).to.emit(pool2, "UpdateMarketBorrowing").withArgs(
                long1,
                toWei("0.169587263966612892"), // apy
                toWei("0.003252358487030932") // acc
              )
              await expect(tx)
                .to.emit(core, "ClosePosition")
                .withArgs(
                  trader1.address,
                  positionId,
                  long1,
                  true, // isLong
                  toWei("10"), // size
                  toWei("60000"), // tradingPrice
                  [pool1.address, pool2.address], // backedPools
                  [toWei("4.4866"), toWei("5.5134")], // allocations
                  [toWei("4.9353"), toWei("6.0647")], // newSizes
                  [toWei("50446.932147443721542364"), toWei("50500")], // newEntryPrices
                  [toWei("42860.794227278998928029"), toWei("52377.3")], // poolPnlUsds
                  toWei("600"), // positionFeeUsd
                  toWei("4254.140828611921435290"), // borrowingFeeUsd
                  [usdc.address],
                  [toWei("199323.953398388078564710")] // collateral + pnl - fee = 108940 + 42860.794227278998928029 + 52377.3 - 600 - 4254.140828611921435290
                )
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("6114.140828", 6)) // 1260 + 4854.140828
              expect(await usdc.balanceOf(core.address)).to.equal(toUnit("199323.953399", 6)) // at least collateral
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("957039.205773", 6)) // 999900 - 42860.794227
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("947522.7", 6)) // 999900 - 52377.300000
              expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
              {
                const [poolTokens, poolBalances] = await pool1.liquidityBalances()
                expect(poolTokens[0]).to.equal(usdc.address)
                expect(poolBalances[0]).to.equal(toWei("957039.205773")) // the same as balanceOf
              }
              {
                const [poolTokens, poolBalances] = await pool2.liquidityBalances()
                expect(poolTokens[0]).to.equal(usdc.address)
                expect(poolBalances[0]).to.equal(toWei("947522.7")) // the same as balanceOf
              }
              {
                const collaterals = await core.listAccountCollaterals(positionId)
                expect(collaterals[0].collateralAddress).to.equal(usdc.address)
                expect(collaterals[0].collateralAmount).to.equal(toWei("199323.953398388078564710"))
                const positions = await core.listAccountPositions(positionId)
                expect(positions[0].marketId).to.equal(long1)
                expect(positions[0].pools[0].size).to.equal(toWei("4.9353"))
                expect(positions[0].pools[0].entryPrice).to.equal(toWei("50446.932147443721542364"))
                expect(positions[0].pools[0].entryBorrowing).to.equal(toWei("0.003528610507948417"))
                expect(positions[0].pools[1].size).to.equal(toWei("6.0647"))
                expect(positions[0].pools[1].entryPrice).to.equal(toWei("50500"))
                expect(positions[0].pools[1].entryBorrowing).to.equal(toWei("0.003252358487030932"))
              }
              {
                const state = await pool1.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("4.9353"))
                expect(state.averageEntryPrice).to.equal(toWei("50446.932147443721542364"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.003528610507948417"))
              }
              {
                const state = await pool2.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("6.0647"))
                expect(state.averageEntryPrice).to.equal(toWei("50500"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.003252358487030932"))
              }
              {
                const state = await pool3.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("0"))
                expect(state.averageEntryPrice).to.equal(toWei("0"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.002872628708424787"))
              }
              {
                expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("909891.950000278998928030")) // 957039.205773 - (60000 - 50446.932147443721542364) * 4.9353
                expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("889908.05")) // 947522.7 - (60000 - 50500) * 6.0647
                expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("1199880")) // 19.998 * 60000
              }
            }
          }
          // close all
          {
            const args = {
              positionId,
              marketId: long1,
              size: toWei("11"),
              flags: PositionOrderFlags.WithdrawAllIfEmpty,
              limitPrice: toWei("55000"),
              expiration: timestampOfTest + 86400 * 2 + 905 + 86400 * 7 + 30,
              lastConsumedToken: zeroAddress,
              collateralToken: zeroAddress,
              collateralAmount: toUnit("0", 6),
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
            {
              await orderBook.connect(trader1).placePositionOrder(args, refCode)
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("6114.140828", 6)) // unchanged
              expect(await usdc.balanceOf(core.address)).to.equal(toUnit("199323.953399", 6)) // unchanged
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("957039.205773", 6)) // unchanged
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("947522.7", 6)) // unchanged
            }
            {
              const [poolTokens, poolBalances] = await pool1.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("957039.205773")) // unchanged
            }
            {
              const [poolTokens, poolBalances] = await pool2.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("947522.7")) // unchanged
            }
            {
              // borrowing = 0
              // position fee = 60000 * 11 * 0.1% = 660
              // fees = 660
              // pnl1 = (60000 - 50446.932147443721542364) * 4.9353 = 47147.255772721001071970
              // pnl2 = (60000 - 50500) * 6.0647 = 57614.65
              // should auto withdraw oldCollateral + pnl - fee = 199323.953398388078564710 + 47147.255772721001071970 + 57614.65 - 660 = 303425.85917110907963668
              await orderBook.connect(broker).fillPositionOrder(6)
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("393425.859170", 6)) // 90000 + 303425.85917110907963668
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("6774.140828", 6)) // 6114.140828 + 660
              expect(await usdc.balanceOf(core.address)).to.be.closeTo(toWei("0"), toWei("0.0000001")) // at least collateral
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("909891.950001", 6)) // 957039.205773 - 47147.255772721001071970
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("889908.05", 6)) // 947522.7 - 57614.65
              expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
              {
                const [poolTokens, poolBalances] = await pool1.liquidityBalances()
                expect(poolTokens[0]).to.equal(usdc.address)
                expect(poolBalances[0]).to.equal(toWei("909891.950001")) // the same as balanceOf
              }
              {
                const [poolTokens, poolBalances] = await pool2.liquidityBalances()
                expect(poolTokens[0]).to.equal(usdc.address)
                expect(poolBalances[0]).to.equal(toWei("889908.05")) // the same as balanceOf
              }
              {
                const collaterals = await core.listAccountCollaterals(positionId)
                expect(collaterals.length).to.equal(0)
                const positions = await core.listAccountPositions(positionId)
                expect(positions.length).to.equal(0)
              }
              {
                const state = await pool1.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("0"))
                expect(state.averageEntryPrice).to.equal(toWei("0"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.003528610507948417"))
              }
              {
                const state = await pool2.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("0"))
                expect(state.averageEntryPrice).to.equal(toWei("0"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.003252358487030932"))
              }
              {
                expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("909891.950001")) // the same as liquidityBalance
                expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("889908.05")) // the same as liquidityBalance
                expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("1199880"))
              }
            }
          }
        })

        it("close half (loss), close all (profit+loss)", async () => {
          // close half
          {
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
              withdrawSwapSlippage: 0,
              tpPriceDiff: 0,
              slPriceDiff: 0,
              tpslExpiration: 0,
              tpslFlags: 0,
              tpslWithdrawSwapToken: zeroAddress,
              tpslWithdrawSwapSlippage: 0,
            }
            {
              await orderBook.connect(trader1).placePositionOrder(args, refCode)
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("1260", 6)) // unchanged
              expect(await usdc.balanceOf(core.address)).to.equal(toUnit("108940", 6)) // unchanged
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6)) // unchanged
            }
            {
              const [poolTokens, poolBalances] = await pool1.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("999900")) // the same as balanceOf
            }
            {
              const [poolTokens, poolBalances] = await pool2.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("999900")) // the same as balanceOf
            }
            await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 86400 * 7)
            await core.setMockPrice(a2b(btc.address), toWei("49000"))
            await expect(orderBook.connect(broker).fillPositionOrder(5)).to.revertedWith("limit")
            await core.setMockPrice(a2b(btc.address), toWei("50000"))
            {
              expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("1004110.949999999999999999")) // 999900 - (50000 - 50446.932147443721542364) * 9.4219
              expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("1005689.050000000000000000")) // 999900 - (50000 - 50500) * 11.5781
              expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("999900")) // 19.998 * 50000
            }
            {
              // fr1 0.10 + exp(10 * 9.4219 * 50000 * 0.80 / 999900 - 7) = 0.139523371982098885
              // fr2 0.10 + exp(6 * 11.5781 * 50000 * 0.80 / 999900 - 6) = 0.139915997411459058
              // acc1 0.139523371982098885 * 7 / 365 = 0.002675790695547101
              // acc2 0.139915997411459058 * 7 / 365 = 0.002683320498301954
              // borrowing 50000 * 9.4219 * 0.002675790695547101 + 50000 * 11.5781 * 0.002683320498301954 = 2813.939270788254225965
              // position fee = 50000 * 10 * 0.1% = 500
              // fees = 500 + 2813.939270788254225965 = 3213.939270788254225965
              // Δsize1 =  9.4219 / (9.4219 + 11.5781) * 10 = 4.4866
              // Δsize2 = 11.5781 / (9.4219 + 11.5781) * 10 = 5.5134
              // pnl1 = (50000 - 50446.932147443721542364) * 4.4866 = -2005.205772721001071970
              // pnl2 = (50000 - 50500) * 5.5134 = -2756.7
              const tx = await orderBook.connect(broker).fillPositionOrder(5)
              // {
              //   for (const i of (await (await tx).wait()).events!) {
              //     if (i.topics[0] === "6a95c0d2b601b7c5cc8e4377c4f827c7a02e15e0f30f3e4e6e7ff6253ddbe72d") {
              //       console.log(core.interface.parseLog(i))
              //     }
              //   }
              // }
              await expect(tx).to.emit(pool1, "UpdateMarketBorrowing").withArgs(
                long1,
                toWei("0.139523371982098885"), // apy
                toWei("0.002675790695547101") // acc
              )
              await expect(tx).to.emit(pool2, "UpdateMarketBorrowing").withArgs(
                long1,
                toWei("0.139915997411459058"), // apy
                toWei("0.002683320498301954") // acc
              )
              await expect(tx)
                .to.emit(core, "ClosePosition")
                .withArgs(
                  trader1.address,
                  positionId,
                  long1,
                  true, // isLong
                  toWei("10"), // size
                  toWei("50000"), // tradingPrice
                  [pool1.address, pool2.address], // backedPools
                  [toWei("4.4866"), toWei("5.5134")], // allocations
                  [toWei("4.9353"), toWei("6.0647")], // newSizes
                  [toWei("50446.932147443721542364"), toWei("50500")], // newEntryPrices
                  [toWei("-2005.205772721001071970"), toWei("-2756.7")], // poolPnlUsds
                  toWei("500"), // positionFeeUsd
                  toWei("2813.939270788254225965"), // borrowingFeeUsd
                  [usdc.address],
                  [toWei("100864.154956490744702065")] // collateral + pnl - fee = 108940 - 2005.205772721001071970 - 2756.7 - 500 - 2813.939270788254225965
                )
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("4573.939270", 6)) // 1260 + 500 + 2813.939270788254225965
              expect(await usdc.balanceOf(core.address)).to.equal(toUnit("100864.154958", 6)) // at least collateral
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("1001905.205772", 6)) // 999900 + 2005.205772721001071970
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("1002656.7", 6)) // 999900 + 2756.7
              expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
              {
                const [poolTokens, poolBalances] = await pool1.liquidityBalances()
                expect(poolTokens[0]).to.equal(usdc.address)
                expect(poolBalances[0]).to.equal(toWei("1001905.205772")) // the same as balanceOf
              }
              {
                const [poolTokens, poolBalances] = await pool2.liquidityBalances()
                expect(poolTokens[0]).to.equal(usdc.address)
                expect(poolBalances[0]).to.equal(toWei("1002656.7")) // the same as balanceOf
              }
              {
                const collaterals = await core.listAccountCollaterals(positionId)
                expect(collaterals[0].collateralAddress).to.equal(usdc.address)
                expect(collaterals[0].collateralAmount).to.equal(toWei("100864.154956490744702065"))
                const positions = await core.listAccountPositions(positionId)
                expect(positions[0].marketId).to.equal(long1)
                expect(positions[0].pools[0].size).to.equal(toWei("4.9353"))
                expect(positions[0].pools[0].entryPrice).to.equal(toWei("50446.932147443721542364"))
                expect(positions[0].pools[0].entryBorrowing).to.equal(toWei("0.002675790695547101"))
                expect(positions[0].pools[1].size).to.equal(toWei("6.0647"))
                expect(positions[0].pools[1].entryPrice).to.equal(toWei("50500"))
                expect(positions[0].pools[1].entryBorrowing).to.equal(toWei("0.002683320498301954"))
              }
              {
                const state = await pool1.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("4.9353"))
                expect(state.averageEntryPrice).to.equal(toWei("50446.932147443721542364"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.002675790695547101"))
              }
              {
                const state = await pool2.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("6.0647"))
                expect(state.averageEntryPrice).to.equal(toWei("50500"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.002683320498301954"))
              }
              {
                const state = await pool3.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("0"))
                expect(state.averageEntryPrice).to.equal(toWei("0"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.002872628708424787"))
              }
              {
                expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("1004110.949999278998928029")) // 1001905.205772 - (50000 - 50446.932147443721542364) * 4.9353
                expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("1005689.05")) // 1002656.7 - (50000 - 50500) * 6.0647
                expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("999900")) // 19.998 * 50000
              }
            }
          }
          // close all
          {
            const args = {
              positionId,
              marketId: long1,
              size: toWei("11"),
              flags: PositionOrderFlags.WithdrawAllIfEmpty,
              limitPrice: toWei("50473"),
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
            {
              await orderBook.connect(trader1).placePositionOrder(args, refCode)
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("4573.939270", 6)) // unchanged
              expect(await usdc.balanceOf(core.address)).to.equal(toUnit("100864.154958", 6)) // unchanged
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("1001905.205772", 6)) // unchanged
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("1002656.7", 6)) // unchanged
            }
            {
              const [poolTokens, poolBalances] = await pool1.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("1001905.205772")) // the same as balanceOf
            }
            {
              const [poolTokens, poolBalances] = await pool2.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("1002656.7")) // the same as balanceOf
            }
            await core.setMockPrice(a2b(btc.address), toWei("50473"))
            {
              // borrowing = 0
              // position fee = 50473 * 11 * 0.1% = 660
              // fees = 555.203
              // pnl1 = (50473 - 50446.932147443721542364) * 4.9353 = 128.652672721001071970
              // pnl2 = (50473 - 50500) * 6.0647 = -163.7469
              // should auto withdraw oldCollateral + pnl - fee = 100864.154956490744702065 + 128.652672721001071970 -163.7469 - 555.203 = 100273.857729211745774035
              await orderBook.connect(broker).fillPositionOrder(6)
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("190273.857728", 6)) // 90000 + 100273.857729211745774035
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("5129.14227", 6)) // 4573.939270 + 555.203
              expect(await usdc.balanceOf(core.address)).to.be.closeTo(toWei("0"), toWei("0.0000001")) // at least collateral
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("1001776.553100", 6)) // 1001905.205772 - 128.652672721001071970
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("1002820.4469", 6)) // 1002656.7 + 163.7469
              expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
              {
                const [poolTokens, poolBalances] = await pool1.liquidityBalances()
                expect(poolTokens[0]).to.equal(usdc.address)
                expect(poolBalances[0]).to.equal(toWei("1001776.553100")) // the same as balanceOf
              }
              {
                const [poolTokens, poolBalances] = await pool2.liquidityBalances()
                expect(poolTokens[0]).to.equal(usdc.address)
                expect(poolBalances[0]).to.equal(toWei("1002820.4469")) // the same as balanceOf
              }
              {
                const collaterals = await core.listAccountCollaterals(positionId)
                expect(collaterals.length).to.equal(0)
                const positions = await core.listAccountPositions(positionId)
                expect(positions.length).to.equal(0)
              }
              {
                const state = await pool1.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("0"))
                expect(state.averageEntryPrice).to.equal(toWei("0"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.002675790695547101"))
              }
              {
                const state = await pool2.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("0"))
                expect(state.averageEntryPrice).to.equal(toWei("0"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.002683320498301954"))
              }
              {
                expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("1001776.553100")) // the same as liquidityBalance
                expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("1002820.4469")) // the same as liquidityBalance
                expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("1009359.054")) // 19.998 * 50473
              }
            }
          }
        })

        it("close all (profit), open again", async () => {
          // close all
          {
            const args = {
              positionId,
              marketId: long1,
              size: toWei("21"),
              flags: 0,
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
            await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 86400 * 7)
            await core.setMockPrice(a2b(btc.address), toWei("60000"))
            {
              // fr1 0.10 + exp(10 * 9.4219 * 60000 * 0.80 / 999900 - 7) = 0.183991833628738928
              // fr2 0.10 + exp(6 * 11.5781 * 60000 * 0.80 / 999900 - 6) = 0.169587263966612892
              // acc1 0.183991833628738928 * 7 / 365 = 0.003528610507948417
              // acc2 0.169587263966612892 * 7 / 365 = 0.003252358487030932
              // borrowing 60000 * 9.4219 * 0.003528610507948417 + 60000 * 11.5781 * 0.003252358487030932 = 4254.140828611921435290
              // position fee = 60000 * 21 * 0.1% = 1260
              // fees = 1260 + 4254.140828611921435290 = 5514.140828611921435290
              // Δsize1 =  9.4219
              // Δsize2 = 11.5781
              // pnl1 = (60000 - 50446.932147443721542364) * 9.4219 = 90008.05
              // pnl2 = (60000 - 50500) * 11.5781 = 109991.95
              const tx = await orderBook.connect(broker).fillPositionOrder(5)
              // {
              //   for (const i of (await (await tx).wait()).events!) {
              //     if (i.topics[0] === "6a95c0d2b601b7c5cc8e4377c4f827c7a02e15e0f30f3e4e6e7ff6253ddbe72d") {
              //       console.log(core.interface.parseLog(i))
              //     }
              //   }
              // }
              await expect(tx).to.emit(pool1, "UpdateMarketBorrowing").withArgs(
                long1,
                toWei("0.183991833628738928"), // apy
                toWei("0.003528610507948417") // acc
              )
              await expect(tx).to.emit(pool2, "UpdateMarketBorrowing").withArgs(
                long1,
                toWei("0.169587263966612892"), // apy
                toWei("0.003252358487030932") // acc
              )
              await expect(tx)
                .to.emit(core, "ClosePosition")
                .withArgs(
                  trader1.address,
                  positionId,
                  long1,
                  true, // isLong
                  toWei("21"), // size
                  toWei("60000"), // tradingPrice
                  [pool1.address, pool2.address], // backedPools
                  [toWei("9.4219"), toWei("11.5781")], // allocations
                  [toWei("0"), toWei("0")], // newSizes
                  [toWei("0"), toWei("0")], // newEntryPrices
                  [toWei("90008.05"), toWei("109991.95")], // poolPnlUsds
                  toWei("1260"), // positionFeeUsd
                  toWei("4254.140828611921435290"), // borrowingFeeUsd
                  [usdc.address],
                  [toWei("303425.859171388078564710000000")] // collateral + pnl - fee = 108940 + 90008.05 + 109991.95 - 1260 - 4254.140828611921435290
                )
              {
                const positions = await core.listAccountPositions(positionId)
                expect(positions.length).to.equal(0)
              }
            }
          }
          // open again
          {
            const args = {
              positionId,
              marketId: long1,
              size: toWei("1"),
              flags: PositionOrderFlags.OpenPosition,
              limitPrice: toWei("60000"),
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
            await orderBook.connect(broker).fillPositionOrder(6)
            {
              const positions = await core.listAccountPositions(positionId)
              expect(positions[0].marketId).to.equal(long1)
              expect(positions[0].pools[0].size).to.equal(toWei("1"))
              expect(positions[0].pools[0].entryPrice).to.equal(toWei("60000"))
              expect(positions[0].pools[0].entryBorrowing).to.equal(toWei("0.003528610507948417"))
              expect(positions[0].pools[1].size).to.equal(toWei("0"))
              expect(positions[0].pools[1].entryPrice).to.equal(toWei("0"))
              expect(positions[0].pools[1].entryBorrowing).to.equal(toWei("0"))
            }
          }
        })

        it("close half (profit), withdraw profit + withdraw usd", async () => {
          // close half
          {
            const args = {
              positionId,
              marketId: long1,
              size: toWei("10"),
              flags: PositionOrderFlags.WithdrawProfit, // here
              limitPrice: toWei("55000"),
              expiration: timestampOfTest + 86400 * 2 + 905 + 86400 * 7 + 30,
              lastConsumedToken: zeroAddress,
              collateralToken: zeroAddress,
              collateralAmount: toUnit("0", 6),
              withdrawUsd: toWei("500"), // here
              withdrawSwapToken: zeroAddress,
              withdrawSwapSlippage: toWei("0"),
              tpPriceDiff: toWei("0"),
              slPriceDiff: toWei("0"),
              tpslExpiration: 0,
              tpslFlags: 0,
              tpslWithdrawSwapToken: zeroAddress,
              tpslWithdrawSwapSlippage: toWei("0"),
            }
            {
              await orderBook.connect(trader1).placePositionOrder(args, refCode)
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("1260", 6)) // unchanged
              expect(await usdc.balanceOf(core.address)).to.equal(toUnit("108940", 6)) // unchanged
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6)) // unchanged
            }
            {
              const [poolTokens, poolBalances] = await pool1.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
            }
            {
              const [poolTokens, poolBalances] = await pool2.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
            }
            await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 86400 * 7)
            await expect(orderBook.connect(broker).fillPositionOrder(5)).to.revertedWith("limit")
            await core.setMockPrice(a2b(btc.address), toWei("60000"))
            {
              expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("909891.95")) // 999900 - (60000 - 50446.932147443721542364) * 9.4219
              expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("889908.05")) // 999900 - (60000 - 50500) * 11.5781
              expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("1199880")) // 19.998 * 60000
            }
            {
              // fr1 0.10 + exp(10 * 9.4219 * 60000 * 0.80 / 999900 - 7) = 0.183991833628738928
              // fr2 0.10 + exp(6 * 11.5781 * 60000 * 0.80 / 999900 - 6) = 0.169587263966612892
              // acc1 0.183991833628738928 * 7 / 365 = 0.003528610507948417
              // acc2 0.169587263966612892 * 7 / 365 = 0.003252358487030932
              // borrowing 60000 * 9.4219 * 0.003528610507948417 + 60000 * 11.5781 * 0.003252358487030932 = 4254.140828611921435290
              // position fee = 60000 * 10 * 0.1% = 600
              // fees = 600 + 4254.140828611921435290 = 4854.140828611921435290
              // Δsize1 =  9.4219 / (9.4219 + 11.5781) * 10 = 4.4866
              // Δsize2 = 11.5781 / (9.4219 + 11.5781) * 10 = 5.5134
              // pnl1 = (60000 - 50446.932147443721542364) * 4.4866 = 42860.794227278998928029
              // pnl2 = (60000 - 50500) * 5.5134 = 52377.3
              const tx = await orderBook.connect(broker).fillPositionOrder(5)
              // {
              //   for (const i of (await (await tx).wait()).events!) {
              //     if (i.topics[0] === "6a95c0d2b601b7c5cc8e4377c4f827c7a02e15e0f30f3e4e6e7ff6253ddbe72d") {
              //       console.log(core.interface.parseLog(i))
              //     }
              //   }
              // }
              await expect(tx).to.emit(pool1, "UpdateMarketBorrowing").withArgs(
                long1,
                toWei("0.183991833628738928"), // apy
                toWei("0.003528610507948417") // acc
              )
              await expect(tx).to.emit(pool2, "UpdateMarketBorrowing").withArgs(
                long1,
                toWei("0.169587263966612892"), // apy
                toWei("0.003252358487030932") // acc
              )
              await expect(tx)
                .to.emit(core, "ClosePosition")
                .withArgs(
                  trader1.address,
                  positionId,
                  long1,
                  true, // isLong
                  toWei("10"), // size
                  toWei("60000"), // tradingPrice
                  [pool1.address, pool2.address], // backedPools
                  [toWei("4.4866"), toWei("5.5134")], // allocations
                  [toWei("4.9353"), toWei("6.0647")], // newSizes
                  [toWei("50446.932147443721542364"), toWei("50500")], // newEntryPrices
                  [toWei("42860.794227278998928029"), toWei("52377.3")], // poolPnlUsds
                  toWei("600"), // positionFeeUsd
                  toWei("4254.140828611921435290"), // borrowingFeeUsd
                  [usdc.address],
                  [toWei("199323.953398388078564710")] // collateral + pnl - fee = 108940 + 42860.794227278998928029 + 52377.3 - 600 - 4254.140828611921435290
                )
              await expect(tx).to.emit(core, "Withdraw").withArgs(
                trader1.address,
                positionId,
                usdc.address,
                toUnit("90883.953398", 6) // profit - fee + withdraw = 42860.794227278998928029 + 52377.3 - 600 - 4254.140828611921435290 + 500
              )
              await expect(tx)
                .to.emit(core, "DepositWithdrawFinish")
                .withArgs(
                  trader1.address,
                  positionId,
                  toWei("0"),
                  [usdc.address],
                  [toWei("108439.999999721001071971")] // 199323.953398388078564710 - 90883.953398667077492739
                )
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("180883.953398", 6)) // 90000 + 90883.953398
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("6114.140828", 6)) // 1260 + 4854.140828
              expect(await usdc.balanceOf(core.address)).to.equal(toUnit("108440.000001", 6)) // at least collateral
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("957039.205773", 6)) // 999900 - 42860.794227
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("947522.7", 6)) // 999900 - 52377.300000
              expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
              {
                const collaterals = await core.listAccountCollaterals(positionId)
                expect(collaterals[0].collateralAddress).to.equal(usdc.address)
                expect(collaterals[0].collateralAmount).to.equal(toWei("108439.999999721001071971"))
                const positions = await core.listAccountPositions(positionId)
                expect(positions[0].marketId).to.equal(long1)
                expect(positions[0].pools[0].size).to.equal(toWei("4.9353"))
                expect(positions[0].pools[0].entryPrice).to.equal(toWei("50446.932147443721542364"))
                expect(positions[0].pools[0].entryBorrowing).to.equal(toWei("0.003528610507948417"))
                expect(positions[0].pools[1].size).to.equal(toWei("6.0647"))
                expect(positions[0].pools[1].entryPrice).to.equal(toWei("50500"))
                expect(positions[0].pools[1].entryBorrowing).to.equal(toWei("0.003252358487030932"))
              }
            }
          }
        })

        it("close half (loss), withdraw profit (but no profit) + withdraw usd", async () => {
          const args = {
            positionId,
            marketId: long1,
            size: toWei("10"),
            flags: PositionOrderFlags.WithdrawProfit, // here
            limitPrice: toWei("50000"),
            expiration: timestampOfTest + 86400 * 2 + 905 + 86400 * 7 + 30,
            lastConsumedToken: zeroAddress,
            collateralToken: zeroAddress,
            collateralAmount: toUnit("0", 6),
            withdrawUsd: toWei("500"), // here
            withdrawSwapToken: zeroAddress,
            withdrawSwapSlippage: 0,
            tpPriceDiff: 0,
            slPriceDiff: 0,
            tpslExpiration: 0,
            tpslFlags: 0,
            tpslWithdrawSwapToken: zeroAddress,
            tpslWithdrawSwapSlippage: 0,
          }
          {
            await orderBook.connect(trader1).placePositionOrder(args, refCode)
          }
          await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 86400 * 7)
          await core.setMockPrice(a2b(btc.address), toWei("50000"))
          {
            // fr1 0.10 + exp(10 * 9.4219 * 50000 * 0.80 / 999900 - 7) = 0.139523371982098885
            // fr2 0.10 + exp(6 * 11.5781 * 50000 * 0.80 / 999900 - 6) = 0.139915997411459058
            // acc1 0.139523371982098885 * 7 / 365 = 0.002675790695547101
            // acc2 0.139915997411459058 * 7 / 365 = 0.002683320498301954
            // borrowing 50000 * 9.4219 * 0.002675790695547101 + 50000 * 11.5781 * 0.002683320498301954 = 2813.939270788254225965
            // position fee = 50000 * 10 * 0.1% = 500
            // fees = 500 + 2813.939270788254225965 = 3213.939270788254225965
            // Δsize1 =  9.4219 / (9.4219 + 11.5781) * 10 = 4.4866
            // Δsize2 = 11.5781 / (9.4219 + 11.5781) * 10 = 5.5134
            // pnl1 = (50000 - 50446.932147443721542364) * 4.4866 = -2005.205772721001071970
            // pnl2 = (50000 - 50500) * 5.5134 = -2756.7
            const tx = await orderBook.connect(broker).fillPositionOrder(5)
            // {
            //   for (const i of (await (await tx).wait()).events!) {
            //     if (i.topics[0] === "6a95c0d2b601b7c5cc8e4377c4f827c7a02e15e0f30f3e4e6e7ff6253ddbe72d") {
            //       console.log(core.interface.parseLog(i))
            //     }
            //   }
            // }
            await expect(tx).to.emit(pool1, "UpdateMarketBorrowing").withArgs(
              long1,
              toWei("0.139523371982098885"), // apy
              toWei("0.002675790695547101") // acc
            )
            await expect(tx).to.emit(pool2, "UpdateMarketBorrowing").withArgs(
              long1,
              toWei("0.139915997411459058"), // apy
              toWei("0.002683320498301954") // acc
            )
            await expect(tx)
              .to.emit(core, "ClosePosition")
              .withArgs(
                trader1.address,
                positionId,
                long1,
                true, // isLong
                toWei("10"), // size
                toWei("50000"), // tradingPrice
                [pool1.address, pool2.address], // backedPools
                [toWei("4.4866"), toWei("5.5134")], // allocations
                [toWei("4.9353"), toWei("6.0647")], // newSizes
                [toWei("50446.932147443721542364"), toWei("50500")], // newEntryPrices
                [toWei("-2005.205772721001071970"), toWei("-2756.7")], // poolPnlUsds
                toWei("500"), // positionFeeUsd
                toWei("2813.939270788254225965"), // borrowingFeeUsd
                [usdc.address],
                [toWei("100864.154956490744702065")] // collateral + pnl - fee = 108940 - 2005.205772721001071970 - 2756.7 - 500 - 2813.939270788254225965
              )
            await expect(tx).to.emit(core, "Withdraw").withArgs(
              trader1.address,
              positionId,
              usdc.address,
              toUnit("500", 6) // withdrawUsd
            )
            await expect(tx)
              .to.emit(core, "DepositWithdrawFinish")
              .withArgs(
                trader1.address,
                positionId,
                toWei("0"),
                [usdc.address],
                [toWei("100364.154956490744702065")] // 100864.154956490744702065 - 500
              )
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90500", 6)) // 90000 + 500
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("4573.939270", 6)) // 1260 + 500 + 2813.939270788254225965
            expect(await usdc.balanceOf(core.address)).to.equal(toUnit("100364.154958", 6)) // at least collateral
            expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("1001905.205772", 6)) // 999900 + 2005.205772721001071970
            expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("1002656.7", 6)) // 999900 + 2756.7
            expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
            {
              const collaterals = await core.listAccountCollaterals(positionId)
              expect(collaterals[0].collateralAddress).to.equal(usdc.address)
              expect(collaterals[0].collateralAmount).to.equal(toWei("100364.154956490744702065"))
              const positions = await core.listAccountPositions(positionId)
              expect(positions[0].marketId).to.equal(long1)
              expect(positions[0].pools[0].size).to.equal(toWei("4.9353"))
              expect(positions[0].pools[0].entryPrice).to.equal(toWei("50446.932147443721542364"))
              expect(positions[0].pools[0].entryBorrowing).to.equal(toWei("0.002675790695547101"))
              expect(positions[0].pools[1].size).to.equal(toWei("6.0647"))
              expect(positions[0].pools[1].entryPrice).to.equal(toWei("50500"))
              expect(positions[0].pools[1].entryBorrowing).to.equal(toWei("0.002683320498301954"))
            }
          }
        })

        it("withdraw collateral, should deduct borrowing fee", async () => {
          await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 86400 * 7)
          await core.setMockPrice(a2b(btc.address), toWei("60000"))
          {
            await expect(
              orderBook.connect(trader1).placeWithdrawalOrder({
                positionId: positionId,
                tokenAddress: usdc.address,
                rawAmount: toUnit("0", 6),
                isUnwrapWeth: false,
                lastConsumedToken: zeroAddress,
                withdrawSwapToken: zeroAddress,
                withdrawSwapSlippage: toWei("0"),
              })
            ).to.revertedWith("Zero amount")
            await expect(
              orderBook.connect(trader1).placeWithdrawalOrder({
                positionId: positionId,
                tokenAddress: usdc.address,
                rawAmount: toUnit("1", 6),
                isUnwrapWeth: false,
                lastConsumedToken: zeroAddress,
                withdrawSwapToken: zeroAddress,
                withdrawSwapSlippage: toWei("0"),
              })
            )
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("1260", 6)) // unchanged
            expect(await usdc.balanceOf(core.address)).to.equal(toUnit("108940", 6)) // unchanged
            expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
            expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6)) // unchanged
          }
          {
            // fr1 0.10 + exp(10 * 9.4219 * 60000 * 0.80 / 999900 - 7) = 0.183991833628738928
            // fr2 0.10 + exp(6 * 11.5781 * 60000 * 0.80 / 999900 - 6) = 0.169587263966612892
            // acc1 0.183991833628738928 * 7 / 365 = 0.003528610507948417
            // acc2 0.169587263966612892 * 7 / 365 = 0.003252358487030932
            // borrowing 60000 * 9.4219 * 0.003528610507948417 + 60000 * 11.5781 * 0.003252358487030932 = 4254.140828611921435290
            await expect(orderBook.connect(trader1).fillWithdrawalOrder(5)).to.revertedWith("AccessControl")
            const tx = await orderBook.connect(broker).fillWithdrawalOrder(5)
            await expect(tx).to.emit(pool1, "UpdateMarketBorrowing").withArgs(
              long1,
              toWei("0.183991833628738928"), // apy
              toWei("0.003528610507948417") // acc
            )
            await expect(tx).to.emit(pool2, "UpdateMarketBorrowing").withArgs(
              long1,
              toWei("0.169587263966612892"), // apy
              toWei("0.003252358487030932") // acc
            )
            await expect(tx).to.emit(core, "Withdraw").withArgs(
              trader1.address,
              positionId,
              usdc.address,
              toUnit("1", 6) // withdraw = +1
            )
            await expect(tx)
              .to.emit(core, "DepositWithdrawFinish")
              .withArgs(
                trader1.address,
                positionId,
                toWei("4254.140828611921435290"), // fee
                [usdc.address],
                [toWei("104684.859171388078564710")] // new = collateral - withdraw - fee = 108940 - 1 - 4254.140828611921435290
              )
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90001", 6)) // +withdraw = +1
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("5514.140828", 6)) // + fee = 1260 + 4254.140828611921435290
            expect(await usdc.balanceOf(core.address)).to.equal(toUnit("104684.859172", 6)) // at least collateral
            const collaterals = await core.listAccountCollaterals(positionId)
            expect(collaterals[0].collateralAddress).to.equal(usdc.address)
            expect(collaterals[0].collateralAmount).to.equal(toWei("104684.859171388078564710")) // collateral - withdraw - fee = 108940 - 1 - 4254.140828611921435290
            const positions = await core.listAccountPositions(positionId)
            expect(positions[0].marketId).to.equal(long1)
            expect(positions[0].pools[0].size).to.equal(toWei("9.4219")) // unchanged
            expect(positions[0].pools[0].entryPrice).to.equal(toWei("50446.932147443721542364")) // unchanged
            expect(positions[0].pools[0].entryBorrowing).to.equal(toWei("0.003528610507948417")) // update
            expect(positions[0].pools[1].size).to.equal(toWei("11.5781")) // unchanged
            expect(positions[0].pools[1].entryPrice).to.equal(toWei("50500")) // unchanged
            expect(positions[0].pools[1].entryBorrowing).to.equal(toWei("0.003252358487030932")) // update
          }
        })

        it("withdraw collateral, max possible value", async () => {
          // borrowing = 0
          // pnl = 0
          // collateral = 108940
          // margin balance = 108940
          // im = 50000 * 21 * 0.006 = 6300
          // entryLev = (9.4219 * 50446.932147443721542364 + 11.5781 * 50500) / 100 = 10599.99999999999999999999
          // max withdraw (according to marginBalance >= im) = 108940 - 6300 = 102640
          // max withdraw (according to collateral >= entryLev) = 108940 - 10599.99999999999999999999 = 98340
          {
            await expect(
              orderBook.connect(trader1).placeWithdrawalOrder({
                positionId: positionId,
                tokenAddress: usdc.address,
                rawAmount: toUnit("98341", 6),
                isUnwrapWeth: false,
                lastConsumedToken: zeroAddress,
                withdrawSwapToken: zeroAddress,
                withdrawSwapSlippage: toWei("0"),
              })
            )
            await expect(orderBook.connect(broker).fillWithdrawalOrder(5)).to.revertedWith("UnsafePositionAccount")
          }
          {
            await expect(
              orderBook.connect(trader1).placeWithdrawalOrder({
                positionId: positionId,
                tokenAddress: usdc.address,
                rawAmount: toUnit("98340", 6),
                isUnwrapWeth: false,
                lastConsumedToken: zeroAddress,
                withdrawSwapToken: zeroAddress,
                withdrawSwapSlippage: toWei("0"),
              })
            )
            await orderBook.connect(broker).fillWithdrawalOrder(6)
          }
        })

        it("liquidate because of funding", async () => {
          await core.setMockPrice(a2b(btc.address), toWei("50500"))
          // collateral = 108940
          // pnl1 = (50500 - 50446.932147443721542364) * 9.4219 = 500
          // pnl2 = (50500 - 50500) * 11.5781 = 0
          // fr1 0.10 + exp(10 * 9.4219 * 50500 * 0.80 / 999900 - 7) = 0.141041492280432254
          // fr2 0.10 + exp(6 * 11.5781 * 50500 * 0.80 / 999900 - 6) = 0.141040828988947263
          // mm = 50500 * 21 * 0.005 = 5302.5
          // borrowing = (50500 * 9.4219 * 0.141041492280432254 + 50500 * 11.5781 * 0.141040828988947263) * hours / (24*365) = 17.0746706325129812174653481735 hours
          // Solve[108940 + 500 - 17.0746706325129812174653481735 hours == 5302.5], => 6098.9 hours
          // acc1 0.141041492280432254 * 6099 / (24*365) = 0.098197723906205059
          // acc2 0.141040828988947263 * 6099 / (24*365) = 0.098197262100866364
          // borrowing 50500 * 9.4219 * 0.098197723906205059 + 50500 * 11.5781 * 0.098197262100866364 = 104138.416187696671868235
          // position fee = 50500 * 21 * 0.002 = 2121
          // update to 1 hour before liquidate
          await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 3600 * 6098)
          await expect(orderBook.liquidate(positionId, long1, zeroAddress, false)).to.revertedWith("AccessControl")
          await expect(orderBook.connect(broker).liquidate(positionId, long1, zeroAddress, false)).to.revertedWith(
            "SafePositionAccount"
          )
          await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 3600 * 6099)
          {
            const tx = await orderBook.connect(broker).liquidate(positionId, long1, zeroAddress, false)
            await expect(tx).to.emit(pool1, "UpdateMarketBorrowing").withArgs(
              long1,
              toWei("0.141041492280432254"), // apy
              toWei("0.098197723906205059") // acc
            )
            await expect(tx).to.emit(pool2, "UpdateMarketBorrowing").withArgs(
              long1,
              toWei("0.141040828988947263"), // apy
              toWei("0.098197262100866364") // acc
            )
            await expect(tx)
              .to.emit(core, "LiquidatePosition")
              .withArgs(
                trader1.address,
                positionId,
                long1,
                true, // isLong
                toWei("21"), // oldSize
                toWei("50500"), // tradingPrice
                [pool1.address, pool2.address], // backedPools
                [toWei("9.4219"), toWei("11.5781")], // allocations
                [toWei("500"), toWei("0")], // poolPnlUsds
                toWei("2121"), // positionFeeUsd
                toWei("104138.416187696671868235"), // borrowingFeeUsd
                [usdc.address],
                [toWei("3180.583812303328131765")] // collateral + pnl - fee = 108940 + 500 - 104138.416187696671868235 - 2121
              )
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("107519.416187", 6)) // 1260 + 2121 + 104138.416187696671868235
            expect(await usdc.balanceOf(core.address)).to.equal(toUnit("3180.583813", 6)) // at least collateral
            expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999400", 6)) // 999900 - 500
            expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6)) // 999900 + 0
            expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
          }
        })

        it("liquidate. 0 < fee < margin < MM", async () => {
          // borrowing = 0
          // Solve[108940
          //   + (x - 50446.932147443721542364) * 9.4219
          //   + (x - 50500) * 11.5781
          // == x * 21 * 0.005]
          // x = 45516.15
          // position fee = x * 21 * 0.002
          await core.setMockPrice(a2b(btc.address), toWei("45516"))
          {
            const tx = await orderBook.connect(broker).liquidate(positionId, long1, zeroAddress, false)
            await expect(tx)
              .to.emit(core, "LiquidatePosition")
              .withArgs(
                trader1.address,
                positionId,
                long1,
                true, // isLong
                toWei("21"), // oldSize
                toWei("45516"), // tradingPrice
                [pool1.address, pool2.address], // backedPools
                [toWei("9.4219"), toWei("11.5781")], // allocations
                [toWei("-46458.749599999999999999"), toWei("-57705.2504")], // poolPnlUsds
                toWei("1911.672"), // positionFeeUsd
                toWei("0"), // borrowingFeeUsd
                [usdc.address],
                [toWei("2864.328000000000000001")] // collateral + pnl - fee = 108940 - 46458.749599999999999999 - 57705.2504 - 1911.672
              )
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("3171.672", 6)) // 1260 + 1911.672
            expect(await usdc.balanceOf(core.address)).to.equal(toUnit("2864.328001", 6)) // at least collateral
            expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("1046358.749599", 6)) // 999900 + 46458.749599999999999999
            expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("1057605.2504", 6)) // 999900 + 57705.2504
            expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
          }
        })

        it("liquidate. 0 < margin < fee < MM", async () => {
          // borrowing = 0
          // Solve[108940
          //   + (x - 50446.932147443721542364) * 9.4219
          //   + (x - 50500) * 11.5781
          // == 0]
          // x = 45288.57
          // position fee = x * 21 * 0.002
          await core.setMockPrice(a2b(btc.address), toWei("45300"))
          {
            const tx = await orderBook.connect(broker).liquidate(positionId, long1, zeroAddress, false)
            await expect(tx)
              .to.emit(core, "LiquidatePosition")
              .withArgs(
                trader1.address,
                positionId,
                long1,
                true, // isLong
                toWei("21"), // oldSize
                toWei("45300"), // tradingPrice
                [pool1.address, pool2.address], // backedPools
                [toWei("9.4219"), toWei("11.5781")], // allocations
                [toWei("-48493.879999999999999999"), toWei("-60206.12")], // poolPnlUsds
                toWei("240.000000000000000001"), // positionFeeUsd (not fully charged)
                toWei("0"), // borrowingFeeUsd
                [usdc.address],
                [toWei("0")] // collateral + pnl - fee
              )
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("1500", 6)) // 1260 + 240
            expect(await usdc.balanceOf(core.address)).to.equal(toUnit("0.000001", 6)) // at least collateral
            expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("1048393.879999", 6)) // 999900 + 48493.879999999999999999
            expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("1060106.12", 6)) // 999900 + 60206.12
            expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
          }
        })

        it("liquidate. margin < 0", async () => {
          // borrowing = 0
          // Solve[108940
          //   + (x - 50446.932147443721542364) * 9.4219
          //   + (x - 50500) * 11.5781
          // == 0]
          // x = 45288.57
          // position fee = x * 21 * 0.002
          await core.setMockPrice(a2b(btc.address), toWei("45200"))
          {
            const tx = await orderBook.connect(broker).liquidate(positionId, long1, zeroAddress, false)
            await expect(tx)
              .to.emit(core, "LiquidatePosition")
              .withArgs(
                trader1.address,
                positionId,
                long1,
                true, // isLong
                toWei("21"), // oldSize
                toWei("45200"), // tradingPrice
                [pool1.address, pool2.address], // backedPools
                [toWei("9.4219"), toWei("11.5781")], // allocations
                [toWei("-49436.069999999999999999"), toWei("-59503.930000000000000001")], // poolPnlUsds (not fully charged)
                toWei("0"), // positionFeeUsd (not fully charged)
                toWei("0"), // borrowingFeeUsd
                [usdc.address],
                [toWei("0")] // collateral + pnl - fee
              )
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("1260", 6)) // 1260 + 0
            expect(await usdc.balanceOf(core.address)).to.equal(toUnit("0.000001", 6)) // at least collateral
            expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("1049336.069999", 6)) // 999900 + 49436.069999999999999999
            expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("1059403.93", 6)) // 999900 + 59503.930000000000000001
            expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
          }
        })
      }) // the same trader longs again, allocate into 2 pools

      describe("another trader longs again, allocate into 2 pools", () => {
        beforeEach(async () => {
          const positionId = encodePositionId(trader2.address, 0)
          await orderBook.connect(trader2).setInitialLeverage(positionId, long1, toWei("100"))
          await usdc.mint(orderBook.address, toUnit("100000", 6))
          const args = {
            positionId,
            marketId: long1,
            size: toWei("20"),
            flags: PositionOrderFlags.OpenPosition,
            limitPrice: toWei("51000"),
            expiration: timestampOfTest + 86400 * 2 + 905 + 300,
            lastConsumedToken: zeroAddress,
            collateralToken: usdc.address,
            collateralAmount: toUnit("100000", 6),
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
          {
            await orderBook.connect(trader2).placePositionOrder(args, refCode)
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
            expect(await usdc.balanceOf(trader2.address)).to.equal(toUnit("100000", 6)) // unchanged
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("250", 6)) // unchanged
            expect(await usdc.balanceOf(core.address)).to.equal(toUnit("9950", 6)) // unchanged
            expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
            expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6)) // unchanged
            expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
          }
          {
            const [poolTokens, poolBalances] = await pool1.liquidityBalances()
            expect(poolTokens[0]).to.equal(usdc.address)
            expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
          }
          {
            const [poolTokens, poolBalances] = await pool2.liquidityBalances()
            expect(poolTokens[0]).to.equal(usdc.address)
            expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
          }
          await core.setMockPrice(a2b(btc.address), toWei("50500"))
          {
            // fee = 50500 * 20 * 0.1% = 1010
            await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 30 + 30)
            await orderBook.connect(broker).fillPositionOrder(4)
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
            expect(await usdc.balanceOf(trader2.address)).to.equal(toUnit("100000", 6)) // unchanged
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("1260", 6)) // + 1010
            expect(await usdc.balanceOf(core.address)).to.equal(toUnit("108940", 6)) // + collateral - fee = 9950 + 100000 - 1010
            expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
            {
              const [poolTokens, poolBalances] = await pool1.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("999900")) // the same as balanceOf
            }
            {
              const marketInfo1 = await pool1.marketState(long1)
              expect(marketInfo1.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
            }
            {
              const marketInfo2 = await pool2.marketState(long1)
              expect(marketInfo2.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
            }
            // 10 * 9.4219 * 50500 * 0.80 / 999900 - 7 = -3.1931717
            // 6 * 11.5781 * 50500 * 0.80 / 999900 - 6 = -3.1931878
            // 2.2 * 0 - 3
            {
              const collaterals = await core.listAccountCollaterals(positionId)
              expect(collaterals[0].collateralAddress).to.equal(usdc.address)
              expect(collaterals[0].collateralAmount).to.equal(toWei("98990")) // collateral - fee = 0 + 100000 - 1010
              const positions = await core.listAccountPositions(positionId)
              expect(positions[0].marketId).to.equal(long1)
              expect(positions[0].pools[0].size).to.equal(toWei("8.4219"))
              expect(positions[0].pools[0].entryPrice).to.equal(toWei("50500"))
              expect(positions[0].pools[0].entryBorrowing).to.equal(toWei("0"))
              expect(positions[0].pools[1].size).to.equal(toWei("11.5781"))
              expect(positions[0].pools[1].entryPrice).to.equal(toWei("50500"))
              expect(positions[0].pools[1].entryBorrowing).to.equal(toWei("0"))
            }
            {
              const state = await pool1.marketState(long1)
              expect(state.isLong).to.equal(true)
              expect(state.totalSize).to.equal(toWei("9.4219"))
              expect(state.averageEntryPrice).to.equal(toWei("50446.932147443721542364"))
            }
            {
              const state = await pool2.marketState(long1)
              expect(state.isLong).to.equal(true)
              expect(state.totalSize).to.equal(toWei("11.5781"))
              expect(state.averageEntryPrice).to.equal(toWei("50500"))
            }
            {
              const state = await pool3.marketState(long1)
              expect(state.isLong).to.equal(true)
              expect(state.totalSize).to.equal(toWei("0"))
              expect(state.averageEntryPrice).to.equal(toWei("0"))
            }
            {
              expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("999400")) // 999900 - (50500 - 50446.932147443721542364) * 9.4219
              expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("999900")) // 999900 - (50500 - 50500) * 11.5781
              expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("1009899")) // 19.998 * 50500
            }
          }
        })

        it("close, profit", async () => {
          // trader1 close
          {
            const positionId = encodePositionId(trader1.address, 0)
            const args = {
              positionId,
              marketId: long1,
              size: toWei("1"),
              flags: PositionOrderFlags.WithdrawAllIfEmpty,
              limitPrice: toWei("55000"),
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
            {
              await orderBook.connect(trader1).placePositionOrder(args, refCode)
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
              expect(await usdc.balanceOf(trader2.address)).to.equal(toUnit("100000", 6)) // unchanged
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("1260", 6)) // unchanged
              expect(await usdc.balanceOf(core.address)).to.equal(toUnit("108940", 6)) // unchanged
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6)) // unchanged
            }
            {
              const [poolTokens, poolBalances] = await pool1.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("999900")) // the same as balanceOf
            }
            {
              const [poolTokens, poolBalances] = await pool2.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("999900")) // the same as balanceOf
            }
            await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 86400 * 7)
            await expect(orderBook.connect(broker).fillPositionOrder(5)).to.revertedWith("limit")
            await core.setMockPrice(a2b(btc.address), toWei("60000"))
            {
              expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("909891.95")) // 999900 - (60000 - 50446.932147443721542364) * 9.4219
              expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("889908.05")) // 999900 - (60000 - 50500) * 11.5781
              expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("1199880")) // 19.998 * 60000
            }
            {
              // fr1 0.10 + exp(10 * 9.4219 * 60000 * 0.80 / 999900 - 7) = 0.183991833628738928
              // fr2 0.10 + exp(6 * 11.5781 * 60000 * 0.80 / 999900 - 6) = 0.169587263966612892
              // acc1 0.183991833628738928 * 7 / 365 = 0.003528610507948417
              // acc2 0.169587263966612892 * 7 / 365 = 0.003252358487030932
              // borrowing 60000 * 1 * 0.003528610507948417 + 60000 * 0 * 0.003252358487030932 = 211.71663047690502
              // position fee = 60000 * 1 * 0.1% = 60
              // fees = 60 + 211.71663047690502 = 271.71663047690502
              // Δsize1 = 1
              // Δsize2 = 0
              // pnl1 = (60000 - 50000) * 1 = 10000
              const tx = await orderBook.connect(broker).fillPositionOrder(5)
              await expect(tx).to.emit(pool1, "UpdateMarketBorrowing").withArgs(
                long1,
                toWei("0.183991833628738928"), // apy
                toWei("0.003528610507948417") // acc
              )
              await expect(tx).to.emit(pool2, "UpdateMarketBorrowing").withArgs(
                long1,
                toWei("0.169587263966612892"), // apy
                toWei("0.003252358487030932") // acc
              )
              await expect(tx)
                .to.emit(core, "ClosePosition")
                .withArgs(
                  trader1.address,
                  positionId,
                  long1,
                  true, // isLong
                  toWei("1"), // size
                  toWei("60000"), // tradingPrice
                  [pool1.address, pool2.address], // backedPools
                  [toWei("1"), toWei("0")], // allocations
                  [toWei("0"), toWei("0")], // newSizes
                  [toWei("0"), toWei("0")], // newEntryPrices
                  [toWei("10000"), toWei("0")], // poolPnlUsds
                  toWei("60"), // positionFeeUsd
                  toWei("211.71663047690502"), // borrowingFeeUsd
                  [usdc.address],
                  [toWei("19678.28336952309498")] // collateral + pnl - fee = 9950 + 10000 - 60 - 211.71663047690502
                )
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("109678.283369", 6)) // 90000 + collateral
              expect(await usdc.balanceOf(trader2.address)).to.equal(toUnit("100000", 6)) // unchanged
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("1531.716630", 6)) // 1260 + 60 + 211.71663047690502
              expect(await usdc.balanceOf(core.address)).to.equal(toUnit("98990.000001", 6)) // trader1 = 0, trader2 = 98990
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("989900", 6)) // 999900 - 10000
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6)) // 999900 - 0
              expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
              {
                const [poolTokens, poolBalances] = await pool1.liquidityBalances()
                expect(poolTokens[0]).to.equal(usdc.address)
                expect(poolBalances[0]).to.equal(toWei("989900")) // the same as balanceOf
              }
              {
                const [poolTokens, poolBalances] = await pool2.liquidityBalances()
                expect(poolTokens[0]).to.equal(usdc.address)
                expect(poolBalances[0]).to.equal(toWei("999900")) // the same as balanceOf
              }
              {
                const collaterals = await core.listAccountCollaterals(positionId)
                expect(collaterals.length).to.equal(0)
                const positions = await core.listAccountPositions(positionId)
                expect(positions.length).to.equal(0)
              }
              {
                const state = await pool1.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("8.4219"))
                expect(state.averageEntryPrice).to.equal(toWei("50499.999999999999999999"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.003528610507948417"))
              }
              {
                const state = await pool2.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("11.5781"))
                expect(state.averageEntryPrice).to.equal(toWei("50500"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.003252358487030932"))
              }
              {
                const state = await pool3.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("0"))
                expect(state.averageEntryPrice).to.equal(toWei("0"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.002872628708424787"))
              }
              {
                expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("909891.949999999999999992")) // 989900 - (60000 - 50499.999999999999999999) * 8.4219
                expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("889908.05")) // 999900 - (60000 - 50500) * 11.5781
                expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("1199880")) // 19.998 * 60000
              }
            }
          }
          // trader2 close
          {
            const positionId = encodePositionId(trader2.address, 0)
            const args = {
              positionId,
              marketId: long1,
              size: toWei("20"),
              flags: PositionOrderFlags.WithdrawAllIfEmpty,
              limitPrice: toWei("55000"),
              expiration: timestampOfTest + 86400 * 2 + 905 + 86400 * 7 + 30,
              lastConsumedToken: zeroAddress,
              collateralToken: zeroAddress,
              collateralAmount: toUnit("0", 6),
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
            {
              await orderBook.connect(trader2).placePositionOrder(args, refCode)
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("109678.283369", 6)) // unchanged
              expect(await usdc.balanceOf(trader2.address)).to.equal(toUnit("100000", 6)) // unchanged
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("1531.716630", 6)) // unchanged
              expect(await usdc.balanceOf(core.address)).to.equal(toUnit("98990.000001", 6)) // unchanged
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("989900", 6)) // unchanged
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("999900", 6)) // unchanged
            }
            {
              const [poolTokens, poolBalances] = await pool1.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("989900")) // the same as balanceOf
            }
            {
              const [poolTokens, poolBalances] = await pool2.liquidityBalances()
              expect(poolTokens[0]).to.equal(usdc.address)
              expect(poolBalances[0]).to.equal(toWei("999900")) // the same as balanceOf
            }
            {
              // acc1 0.183991833628738928 * 7 / 365 = 0.003528610507948417
              // acc2 0.169587263966612892 * 7 / 365 = 0.003252358487030932
              // borrowing 60000 * 8.4219 * 0.003528610507948417 + 60000 * 11.5781 * 0.003252358487030932 = 4042.42419813501641529
              // position fee = 60000 * 20 * 0.1% = 1200
              // pnl1 = (60000 - 50499.999999999999999999) * 8.4219 = 80008.05
              // pnl2 = (60000 - 50500) * 11.5781 = 109991.95
              // should auto withdraw oldCollateral + pnl - fee = 98990 + 80008.05 + 109991.95 - 1200 - 4042.42419813501641529 = 283747.575801864983584710
              await orderBook.connect(broker).fillPositionOrder(6)
              expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("109678.283369", 6)) // unchanged
              expect(await usdc.balanceOf(trader2.address)).to.equal(toUnit("383747.575801", 6)) // 100000 + 283747.575801864983584710
              expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("6774.140828", 6)) // 1531.716630 + 1200 + 4042.42419813501641529
              expect(await usdc.balanceOf(core.address)).to.be.closeTo(toWei("0"), toWei("0.0000001")) // near 0 is ok
              expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("909891.95", 6)) // 989900 - 80008.05
              expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("889908.05", 6)) // 999900 - 109991.95
              expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("19.998", 8)) // unchanged
              {
                const [poolTokens, poolBalances] = await pool1.liquidityBalances()
                expect(poolTokens[0]).to.equal(usdc.address)
                expect(poolBalances[0]).to.equal(toWei("909891.95")) // the same as balanceOf
              }
              {
                const [poolTokens, poolBalances] = await pool2.liquidityBalances()
                expect(poolTokens[0]).to.equal(usdc.address)
                expect(poolBalances[0]).to.equal(toWei("889908.05")) // the same as balanceOf
              }
              {
                const collaterals = await core.listAccountCollaterals(positionId)
                expect(collaterals.length).to.equal(0)
                const positions = await core.listAccountPositions(positionId)
                expect(positions.length).to.equal(0)
              }
              {
                const state = await pool1.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("0"))
                expect(state.averageEntryPrice).to.equal(toWei("0"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.003528610507948417"))
              }
              {
                const state = await pool2.marketState(long1)
                expect(state.isLong).to.equal(true)
                expect(state.totalSize).to.equal(toWei("0"))
                expect(state.averageEntryPrice).to.equal(toWei("0"))
                expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0.003252358487030932"))
              }
              {
                expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("909891.95")) // the same as liquidityBalance
                expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("889908.05")) // the same as liquidityBalance
                expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("1199880"))
              }
            }
          }
        })
      })

      it("TODO: long capped pnl", async () => {
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
      })

      it("TODO: ADL a long position", async () => {
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
      })

      it("TODO: remove liquidity cause reserved > spotLiquidity", async () => {
        // {
        //   const collateralInfo = await pool.getAssetStorageV2(0)
        //   expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // 1000000 - fee
        // }
        // // open long xxx, using usdc
        // const longAccountId = assembleSubAccountId(trader1.address, 0, 1, true)
        // await usdc.connect(trader1).transfer(orderBook.address, toUnit("100000", 6))
        // const args2 = {
        //   subAccountId: longAccountId,
        //   collateral: toUnit("100000", 6),
        //   size: toWei("900000"),
        //   price: toWei("1"),
        //   tpPrice: "0",
        //   slPrice: "0",
        //   expiration: timestampOfTest + 86400 * 2 + 800,
        //   tpslExpiration: timestampOfTest + 86400 * 2 + 800,
        //   profitTokenId: 0,
        //   tpslProfitTokenId: 0,
        //   flags: PositionOrderFlags.OpenPosition,
        // }
        // await orderBook.connect(trader1).placePositionOrder(args2, refCode)
        // await orderBook
        //   .connect(broker)
        //   .fillPositionOrder(1, toWei("900000"), toWei("1"), [toWei("1"), toWei("1"), toWei("1")])
        // expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1"), toWei("1")])).to.equal(toWei("1"))
        // // reserve 900,000 * 80%, liquidity 999,900, can remove 279,900
        // {
        //   await mlp.connect(lp1).transfer(orderBook.address, toWei("279901"))
        //   const args = { assetId: 0, rawAmount: toWei("279901"), isAdding: false }
        //   await time.increaseTo(timestampOfTest + 86400 * 2 + 500)
        //   await orderBook.connect(lp1).placeLiquidityOrder(args)
        //   await time.increaseTo(timestampOfTest + 86400 * 2 + 500 + 1800)
        //   await expect(
        //     orderBook.connect(broker).fillLiquidityOrder(2, [toWei("1"), toWei("1"), toWei("1")])
        //   ).to.revertedWith("RSV")
        //   await orderBook.connect(lp1).cancelOrder(2)
        // }
        // {
        //   await mlp.connect(lp1).transfer(orderBook.address, toWei("279900"))
        //   const args = { assetId: 0, rawAmount: toWei("279900"), isAdding: false }
        //   await orderBook.connect(lp1).placeLiquidityOrder(args)
        //   await time.increaseTo(timestampOfTest + 86400 * 2 + 500 + 1800 + 1800)
        //   await orderBook.connect(broker).fillLiquidityOrder(3, [toWei("1"), toWei("1"), toWei("1")])
        // }
      })

      it("TODO: tp/sl strategy", async () => {
        // // open long, tp/sl strategy takes effect when fill
        // const longAccountId = assembleSubAccountId(trader1.address, 0, 1, true)
        // await usdc.connect(trader1).transfer(orderBook.address, toUnit("10000", 6))
        // const args2 = {
        //   subAccountId: longAccountId,
        //   collateral: toUnit("10000", 6),
        //   size: toWei("2"),
        //   price: toWei("2000"),
        //   tpPrice: toWei("2200"),
        //   slPrice: toWei("1800"),
        //   expiration: timestampOfTest + 86400 * 2 + 800,
        //   tpslExpiration: timestampOfTest + 86400 * 2 + 1000,
        //   profitTokenId: 0,
        //   tpslProfitTokenId: 2,
        //   flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder + PositionOrderFlags.TpSlStrategy,
        // }
        // await orderBook.connect(trader1).placePositionOrder(args2, refCode)
        // const tx2 = await orderBook
        //   .connect(broker)
        //   .fillPositionOrder(1, toWei("2"), toWei("2000"), [toWei("1"), toWei("2000"), toWei("1")])
        // await expect(tx2)
        //   .to.emit(orderBook, "NewPositionOrder")
        //   .withArgs(trader1.address, 2, [
        //     args2.subAccountId,
        //     toWei("0"), // collateral
        //     args2.size,
        //     toWei("2200"), // price
        //     toWei("0"), // tpPrice
        //     toWei("0"), // slPrice
        //     timestampOfTest + 86400 * 2 + 1000, // expiration
        //     0, // tpslExpiration
        //     2, // profitTokenId
        //     0, // tpslProfitTokenId
        //     PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.ShouldReachMinProfit,
        //   ])
        // await expect(tx2)
        //   .to.emit(orderBook, "NewPositionOrder")
        //   .withArgs(trader1.address, 3, [
        //     args2.subAccountId,
        //     toWei("0"), // collateral
        //     args2.size,
        //     toWei("1800"), // price
        //     toWei("0"), // tpPrice
        //     toWei("0"), // slPrice
        //     timestampOfTest + 86400 * 2 + 1000, // expiration
        //     0, // tpslExpiration
        //     2, // profitTokenId
        //     0, // tpslProfitTokenId
        //     PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.TriggerOrder,
        //   ])
        // // close tp+sl
        // const args3 = {
        //   subAccountId: longAccountId,
        //   collateral: toUnit("12345", 6),
        //   size: toWei("2"),
        //   price: toWei("2000"),
        //   tpPrice: toWei("2200"),
        //   slPrice: toWei("1800"),
        //   expiration: timestampOfTest + 86400 * 2 + 800,
        //   tpslExpiration: timestampOfTest + 86400 * 2 + 1000,
        //   profitTokenId: 0,
        //   tpslProfitTokenId: 2,
        //   flags: PositionOrderFlags.TpSlStrategy,
        // }
        // await expect(orderBook.connect(trader1).placePositionOrder(args3, refCode)).to.revertedWith("C!0")
        // args3.collateral = toUnit("0", 6)
        // const tx3 = await orderBook.connect(trader1).placePositionOrder(args3, refCode)
        // await expect(tx3)
        //   .to.emit(orderBook, "NewPositionOrder")
        //   .withArgs(trader1.address, 4, [
        //     args2.subAccountId,
        //     toWei("0"), // collateral
        //     args2.size,
        //     toWei("2200"), // price
        //     toWei("0"), // tpPrice
        //     toWei("0"), // slPrice
        //     timestampOfTest + 86400 * 2 + 1000, // expiration
        //     0, // tpslExpiration
        //     2, // profitTokenId
        //     0, // tpslProfitTokenId
        //     PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.ShouldReachMinProfit,
        //   ])
        // await expect(tx3)
        //   .to.emit(orderBook, "NewPositionOrder")
        //   .withArgs(trader1.address, 5, [
        //     args2.subAccountId,
        //     toWei("0"), // collateral
        //     args2.size,
        //     toWei("1800"), // price
        //     toWei("0"), // tpPrice
        //     toWei("0"), // slPrice
        //     timestampOfTest + 86400 * 2 + 1000, // expiration
        //     0, // tpslExpiration
        //     2, // profitTokenId
        //     0, // tpslProfitTokenId
        //     PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.TriggerOrder,
        //   ])
      })
    }) // long a little and test more

    describe("TODO: short a little and test more", () => {
      let shortAccountId = ""
      beforeEach(async () => {
        //     shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
        //     // open short xxx, using usdc
        //     await usdc.connect(trader1).transfer(orderBook.address, toUnit("10000", 6))
        //     await orderBook.connect(trader1).setInitialLeverage(positionId, short1, toWei('100'))
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
        //       expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
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

      it("TODO: normal profit", async () => {})

      it("TODO: normal loss", async () => {})

      it("TODO: short capped pnl", async () => {
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
      })

      describe("TODO: some symbol uses chainlink", () => {
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
        it("TODO: strict stable price dampener. ignore broker price", async () => {
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
        })
        it("TODO: strict stable price dampener. use broker price", async () => {
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
        })
      }) // add chainlink
    }) // short a little and test more

    describe("deposit 2 collaterals, open long, allocated to 3 pools", () => {
      beforeEach(async () => {
        // deposit 2 collaterals
        const positionId = encodePositionId(trader1.address, 0)
        await usdc.connect(trader1).transfer(orderBook.address, toUnit("30000", 6))
        await arb.connect(trader1).transfer(orderBook.address, toUnit("30000", 18))
        await orderBook.connect(trader1).depositCollateral(positionId, usdc.address, toUnit("30000", 6))
        await orderBook.connect(trader1).depositCollateral(positionId, arb.address, toUnit("30000", 18))
        {
          const collaterals = await core.listAccountCollaterals(positionId)
          expect(collaterals.length).to.equal(2)
          expect(collaterals[0].collateralAddress).to.equal(usdc.address)
          expect(collaterals[0].collateralAmount).to.equal(toWei("30000"))
          expect(collaterals[1].collateralAddress).to.equal(arb.address)
          expect(collaterals[1].collateralAmount).to.equal(toWei("30000"))
        }
        // open long
        await orderBook.connect(trader1).setInitialLeverage(positionId, long1, toWei("100"))
        {
          const args = {
            positionId,
            marketId: long1,
            size: toWei("60"),
            flags: PositionOrderFlags.OpenPosition,
            limitPrice: toWei("50000"),
            expiration: timestampOfTest + 86400 * 2 + 905 + 300,
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
        }
        {
          const [poolTokens, poolBalances] = await pool1.liquidityBalances()
          expect(poolTokens[0]).to.equal(usdc.address)
          expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
        }
        {
          const [poolTokens, poolBalances] = await pool2.liquidityBalances()
          expect(poolTokens[0]).to.equal(usdc.address)
          expect(poolBalances[0]).to.equal(toWei("999900")) // unchanged
        }
        {
          const [poolTokens, poolBalances] = await pool3.liquidityBalances()
          expect(poolTokens[2]).to.equal(btc.address)
          expect(poolBalances[2]).to.equal(toWei("19.998")) // unchanged
        }
        {
          // fee = 50000 * 60 * 0.1% = 3000
          await time.increaseTo(timestampOfTest + 86400 * 2 + 905 + 30)
          await orderBook.connect(broker).fillPositionOrder(3)
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("70000", 6)) // 100000 - 30000
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("3200", 6)) // + 3000
          expect(await usdc.balanceOf(core.address)).to.equal(toUnit("27000", 6)) // + collateral - fee = 0 + 30000 - 3000
          expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("999900", 6)) // unchanged
          expect(await arb.balanceOf(trader1.address)).to.equal(toUnit("70000", 18)) // 100000 - 30000
          expect(await arb.balanceOf(core.address)).to.equal(toUnit("30000", 18)) // + collateral - fee = 0 + 30000 - 0
          {
            const state = await pool1.marketState(long1)
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            const state = await pool1.marketState(short1)
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            const collaterals = await core.listAccountCollaterals(positionId)
            expect(collaterals[0].collateralAddress).to.equal(usdc.address)
            expect(collaterals[0].collateralAmount).to.equal(toWei("27000")) // collateral - fee = 30000 - 3000
            expect(collaterals[1].collateralAddress).to.equal(arb.address)
            expect(collaterals[1].collateralAmount).to.equal(toWei("30000")) // collateral = 30000
            const positions = await core.listAccountPositions(positionId)
            expect(positions[0].marketId).to.equal(long1)
            expect(positions[0].pools[0].size).to.equal(toWei("15.1989"))
            expect(positions[0].pools[0].entryPrice).to.equal(toWei("50000"))
            expect(positions[0].pools[0].entryBorrowing).to.equal(toWei("0"))
            expect(positions[0].pools[1].size).to.equal(toWei("21.1652"))
            expect(positions[0].pools[1].entryPrice).to.equal(toWei("50000"))
            expect(positions[0].pools[1].entryBorrowing).to.equal(toWei("0"))
            expect(positions[0].pools[2].size).to.equal(toWei("23.6359"))
            expect(positions[0].pools[2].entryPrice).to.equal(toWei("50000"))
            expect(positions[0].pools[2].entryBorrowing).to.equal(toWei("0"))
          }
          {
            const state = await pool1.marketState(long1)
            expect(state.isLong).to.equal(true)
            expect(state.totalSize).to.equal(toWei("15.1989"))
            expect(state.averageEntryPrice).to.equal(toWei("50000"))
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            const state = await pool2.marketState(long1)
            expect(state.isLong).to.equal(true)
            expect(state.totalSize).to.equal(toWei("21.1652"))
            expect(state.averageEntryPrice).to.equal(toWei("50000"))
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            const state = await pool3.marketState(long1)
            expect(state.isLong).to.equal(true)
            expect(state.totalSize).to.equal(toWei("23.6359"))
            expect(state.averageEntryPrice).to.equal(toWei("50000"))
            expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
          }
          {
            expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("999900")) // unchanged
            expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("999900")) // unchanged
            expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("999900")) // unchanged
          }
        }
      })

      it("close all, take profit => the trader gets 2 types of tokens", async () => {
        const positionId = encodePositionId(trader1.address, 0)
        await core.setMockPrice(a2b(usdc.address), toWei("1"))
        await core.setMockPrice(a2b(arb.address), toWei("3"))
        await core.setMockPrice(a2b(btc.address), toWei("60000"))
        {
          const args = {
            positionId,
            marketId: long1,
            size: toWei("60"),
            flags: 0,
            limitPrice: toWei("50000"),
            expiration: timestampOfTest + 86400 * 2 + 905 + 300,
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
        }
        await orderBook.connect(broker).fillPositionOrder(4)
        // positionFees = 60000 * 60 * 0.001 = 3600
        // borrowingFee = 0
        // pnl1 = (60000 - 50000) * 15.1989 = 151989 usdc
        // pnl2 = (60000 - 50000) * 21.1652 = 211652 usdc
        // pnl3 = (60000 - 50000) * 23.6359 = 236359 = 3.93931666 wbtc
        expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("70000", 6)) // unchanged
        expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("6800", 6)) // 3200 + 3600
        expect(await usdc.balanceOf(core.address)).to.equal(toUnit("387041", 6)) // + collateral + pnl1 + pnl2 - fee = 27000 + 151989 + 211652 - 3600
        expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("847911", 6)) // - pnl1 = 999900 - 151989
        expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("788248", 6)) // - pnl2 = 999900 - 211652
        expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("16.05868334", 8)) // - pnl3 = 19.998 - 3.93931666
        expect(await arb.balanceOf(trader1.address)).to.equal(toUnit("70000", 18)) // unchanged
        expect(await arb.balanceOf(core.address)).to.equal(toUnit("30000", 18)) // unchanged
        {
          const state = await pool1.marketState(long1)
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool1.marketState(short1)
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const collaterals = await core.listAccountCollaterals(positionId)
          expect(collaterals[0].collateralAddress).to.equal(usdc.address)
          expect(collaterals[0].collateralAmount).to.equal(toWei("387041")) // collateral - fee + pnl1 + pnl2 = 27000 - 3000 + 151989 + 211652
          expect(collaterals[1].collateralAddress).to.equal(arb.address)
          expect(collaterals[1].collateralAmount).to.equal(toWei("30000")) // unchanged
          expect(collaterals[2].collateralAddress).to.equal(btc.address)
          expect(collaterals[2].collateralAmount).to.equal(toWei("3.93931666")) // pnl3 = 3.93931666
          const positions = await core.listAccountPositions(positionId)
          expect(positions.length).to.equal(0)
        }
        {
          const state = await pool1.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("0"))
          expect(state.averageEntryPrice).to.equal(toWei("0"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool2.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("0"))
          expect(state.averageEntryPrice).to.equal(toWei("0"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool3.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("0"))
          expect(state.averageEntryPrice).to.equal(toWei("0"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("847911"))
          expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("788248"))
          expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("963521.0004")) // 16.05868334 * 60000
        }
      })

      it("close all, take profit => try to keep usdc and pay fees by profits", async () => {
        const positionId = encodePositionId(trader1.address, 0)
        await core.setMockPrice(a2b(usdc.address), toWei("1"))
        await core.setMockPrice(a2b(arb.address), toWei("3"))
        await core.setMockPrice(a2b(btc.address), toWei("60000"))
        {
          const args = {
            positionId,
            marketId: long1,
            size: toWei("60"),
            flags: 0,
            limitPrice: toWei("50000"),
            expiration: timestampOfTest + 86400 * 2 + 905 + 300,
            lastConsumedToken: usdc.address,
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
        }
        await orderBook.connect(broker).fillPositionOrder(4)
        // positionFees = 60000 * 60 * 0.001 = 3600
        // borrowingFee = 0
        // pnl1 = (60000 - 50000) * 15.1989 = 151989 usdc
        // pnl2 = (60000 - 50000) * 21.1652 = 211652 usdc
        // pnl3 = (60000 - 50000) * 23.6359 = 236359 = 3.93931666 wbtc
        // fee is paid by wbtc
        expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("70000", 6)) // unchanged
        expect(await arb.balanceOf(trader1.address)).to.equal(toUnit("70000", 18)) // unchanged
        expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("3200", 6)) // unchanged
        expect(await arb.balanceOf(feeDistributor.address)).to.equal(toUnit("0", 6)) // unchanged
        expect(await btc.balanceOf(feeDistributor.address)).to.equal(toUnit("0.062", 8)) // 0.002 + 3600 / 60000
        expect(await usdc.balanceOf(core.address)).to.equal(toUnit("390641", 6)) // + collateral + pnl1 + pnl2 = 27000 + 151989 + 211652
        expect(await arb.balanceOf(core.address)).to.equal(toUnit("30000", 18)) // unchanged
        expect(await btc.balanceOf(core.address)).to.equal(toUnit("3.87931666", 8)) // + pnl3 - fee = 3.93931666 - 0.06
        expect(await usdc.balanceOf(pool1.address)).to.equal(toUnit("847911", 6)) // - pnl1 = 999900 - 151989
        expect(await usdc.balanceOf(pool2.address)).to.equal(toUnit("788248", 6)) // - pnl2 = 999900 - 211652
        expect(await btc.balanceOf(pool3.address)).to.equal(toUnit("16.05868334", 8)) // - pnl3 = 19.998 - 3.93931666
        {
          const state = await pool1.marketState(long1)
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool1.marketState(short1)
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const collaterals = await core.listAccountCollaterals(positionId)
          expect(collaterals[0].collateralAddress).to.equal(usdc.address)
          expect(collaterals[0].collateralAmount).to.equal(toWei("390641")) // collateral + pnl1 + pnl2 = 27000 + 151989 + 211652
          expect(collaterals[1].collateralAddress).to.equal(arb.address)
          expect(collaterals[1].collateralAmount).to.equal(toWei("30000")) // unchanged
          expect(collaterals[2].collateralAddress).to.equal(btc.address)
          expect(collaterals[2].collateralAmount).to.equal(toWei("3.87931666")) // pnl3 - fee = 3.93931666 - 3600 / 60000
          const positions = await core.listAccountPositions(positionId)
          expect(positions.length).to.equal(0)
        }
        {
          const state = await pool1.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("0"))
          expect(state.averageEntryPrice).to.equal(toWei("0"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool2.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("0"))
          expect(state.averageEntryPrice).to.equal(toWei("0"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool3.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("0"))
          expect(state.averageEntryPrice).to.equal(toWei("0"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("847911"))
          expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("788248"))
          expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("963521.0004")) // 16.05868334 * 60000
        }
      })

      it("close all, realize loss => the pools get 2 types of tokens", async () => {
        const positionId = encodePositionId(trader1.address, 0)
        await core.setMockPrice(a2b(usdc.address), toWei("1"))
        await core.setMockPrice(a2b(arb.address), toWei("1.5"))
        await core.setMockPrice(a2b(btc.address), toWei("49500"))
        {
          const args = {
            positionId,
            marketId: long1,
            size: toWei("60"),
            flags: 0,
            limitPrice: toWei("40000"),
            expiration: timestampOfTest + 86400 * 2 + 905 + 300,
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
        }
        await orderBook.connect(broker).fillPositionOrder(4)
        // positionFees = 49500 * 60 * 0.001 = 2970
        // borrowingFee = 0
        // pnl1 = (49500 - 50000) * 15.1989 = -7599.45
        // pnl2 = (49500 - 50000) * 21.1652 = -10582.6
        // pnl3 = (49500 - 50000) * 23.6359 = -11817.95
        // pnl1+2+3 = (49500 - 50000) * 60 = -30000
        {
          const state = await pool1.marketState(long1)
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool1.marketState(short1)
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const collaterals = await core.listAccountCollaterals(positionId)
          expect(collaterals[0].collateralAddress).to.equal(usdc.address)
          expect(collaterals[0].collateralAmount).to.equal(toWei("0")) // max(0, collateral + pnl) = max(0, 27000 - 30000)
          expect(collaterals[1].collateralAddress).to.equal(arb.address)
          expect(collaterals[1].collateralAmount).to.equal(toWei("26020")) // collateral + (-fee + remain) / price = 30000 - (2970 + 3000) / 1.5
          const positions = await core.listAccountPositions(positionId)
          expect(positions.length).to.equal(0)
        }
        {
          const state = await pool1.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("0"))
          expect(state.averageEntryPrice).to.equal(toWei("0"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool2.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("0"))
          expect(state.averageEntryPrice).to.equal(toWei("0"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool3.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("0"))
          expect(state.averageEntryPrice).to.equal(toWei("0"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("1007499.45")) // 999900 + 7599.45
          expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("1010482.6")) // 999900 + 10582.6
          expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("1001718.95")) // 19.998 * 49500 + 11817.95
        }
      })

      it("close all, realize loss => try to keep usdc and pay fees and loss by arb", async () => {
        const positionId = encodePositionId(trader1.address, 0)
        await core.setMockPrice(a2b(usdc.address), toWei("1"))
        await core.setMockPrice(a2b(arb.address), toWei("1.5"))
        await core.setMockPrice(a2b(btc.address), toWei("49500"))
        {
          const args = {
            positionId,
            marketId: long1,
            size: toWei("60"),
            flags: 0,
            limitPrice: toWei("40000"),
            expiration: timestampOfTest + 86400 * 2 + 905 + 300,
            lastConsumedToken: usdc.address,
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
        }
        await orderBook.connect(broker).fillPositionOrder(4)
        // positionFees = 49500 * 60 * 0.001 = 2970
        // borrowingFee = 0
        // pnl1 = (49500 - 50000) * 15.1989 = -7599.45
        // pnl2 = (49500 - 50000) * 21.1652 = -10582.6
        // pnl3 = (49500 - 50000) * 23.6359 = -11817.95
        // pnl1+2+3 = (49500 - 50000) * 60 = -30000
        {
          const state = await pool1.marketState(long1)
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool1.marketState(short1)
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const collaterals = await core.listAccountCollaterals(positionId)
          expect(collaterals[1].collateralAddress).to.equal(arb.address)
          expect(collaterals[1].collateralAmount).to.equal(toWei("8019.999999999999999999")) // collateral + pnl - fee = 30000 + (-30000 - 2970) / 1.5
          expect(collaterals[0].collateralAddress).to.equal(usdc.address)
          expect(collaterals[0].collateralAmount).to.equal(toWei("27000")) // unchanged
          const positions = await core.listAccountPositions(positionId)
          expect(positions.length).to.equal(0)
        }
        {
          const state = await pool1.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("0"))
          expect(state.averageEntryPrice).to.equal(toWei("0"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool2.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("0"))
          expect(state.averageEntryPrice).to.equal(toWei("0"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          const state = await pool3.marketState(long1)
          expect(state.isLong).to.equal(true)
          expect(state.totalSize).to.equal(toWei("0"))
          expect(state.averageEntryPrice).to.equal(toWei("0"))
          expect(state.cumulatedBorrowingPerUsd).to.equal(toWei("0"))
        }
        {
          expect(await pool1.callStatic.estimatedAumUsd()).to.equal(toWei("1007499.45")) // 999900 + 7599.45
          expect(await pool2.callStatic.estimatedAumUsd()).to.equal(toWei("1010482.6")) // 999900 + 10582.6
          expect(await pool3.callStatic.estimatedAumUsd()).to.equal(toWei("1001718.950000000000000001")) // 19.998 * 49500 + 11817.95
        }
      })
    }) // 2 collaterals, open long, allocated to 3 pools
  }) // add some liquidity and test more

  it("TODO: stop loss", async () => {})
  it("TODO: tp/sl strategy - open long", async () => {})
  it("TODO: tp/sl strategy - open short", async () => {})
  it("TODO: tp/sl strategy - close long", async () => {})
  it("TODO: tp/sl strategy - liquidate long", async () => {})
})
