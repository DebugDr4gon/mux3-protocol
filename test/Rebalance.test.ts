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
  TestRebalancer,
} from "../typechain"
import { time } from "@nomicfoundation/hardhat-network-helpers"

const a2b = (a) => {
  return a + "000000000000000000000000"
}
const u2b = (u) => {
  return ethers.utils.hexZeroPad(u.toTwos(256).toHexString(), 32)
}

describe("Rebalance", () => {
  const refCode = toBytes32("")

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
  let orderBook: OrderBook
  let feeDistributor: MockMux3FeeDistributor
  let emitter: CollateralPoolEventEmitter
  let rebalancer: TestRebalancer

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
    await core.addCollateralToken(usdc.address, 6, true)
    await core.addCollateralToken(arb.address, 18, false)
    await core.addCollateralToken(btc.address, 8, false)
    await core.setConfig(ethers.utils.id("MC_BORROWING_BASE_APY"), u2b(toWei("0.10")))
    await core.setConfig(ethers.utils.id("MC_BORROWING_INTERVAL"), u2b(ethers.BigNumber.from(3600)))

    // orderBook
    const libOrderBook = await createContract("LibOrderBook")
    const libOrderBook2 = await createContract("LibOrderBook2")
    orderBook = (await createContract("OrderBook", [], {
      "contracts/libraries/LibOrderBook.sol:LibOrderBook": libOrderBook,
      "contracts/libraries/LibOrderBook2.sol:LibOrderBook2": libOrderBook2,
    })) as OrderBook
    await orderBook.initialize(core.address, weth.address)
    await orderBook.setConfig(ethers.utils.id("MCO_LIQUIDITY_LOCK_PERIOD"), u2b(ethers.BigNumber.from(60 * 15)))
    await orderBook.setConfig(ethers.utils.id("MCO_MARKET_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(60 * 2)))
    await orderBook.setConfig(ethers.utils.id("MCO_LIMIT_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(86400 * 30)))
    await orderBook.setConfig(ethers.utils.id("MCO_CANCEL_COOL_DOWN"), u2b(ethers.BigNumber.from(5)))
    await orderBook.setConfig(ethers.utils.id("MCO_MIN_LIQUIDITY_ORDER_USD"), u2b(toWei("0.1")))
    await orderBook.setConfig(ethers.utils.id("MCO_ORDER_GAS_FEE_GWEI"), u2b(ethers.BigNumber.from("1000000")))

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

    // feeDistributor
    feeDistributor = (await createContract("MockMux3FeeDistributor", [core.address])) as MockMux3FeeDistributor
    await core.setConfig(ethers.utils.id("MC_FEE_DISTRIBUTOR"), a2b(feeDistributor.address))

    // rebalancer
    rebalancer = (await createContract("TestRebalancer", [core.address, orderBook.address])) as TestRebalancer

    // role
    await orderBook.grantRole(ethers.utils.id("BROKER_ROLE"), broker.address)
    await orderBook.grantRole(ethers.utils.id("REBALANCER_ROLE"), rebalancer.address)
    await core.grantRole(ethers.utils.id("ORDER_BOOK_ROLE"), orderBook.address)

    // price
    await core.setMockPrice(a2b(usdc.address), toWei("1"))
    await core.setMockPrice(a2b(weth.address), toWei("1000"))
    await core.setMockPrice(a2b(arb.address), toWei("2"))
    await core.setMockPrice(a2b(btc.address), toWei("50000"))
  })

  describe("donate some arb into the pool", () => {
    beforeEach(async () => {
      // donate some arb into the pool
      await arb.mint(orderBook.address, toWei("10"))
      await orderBook.grantRole(ethers.utils.id("FEE_DONATOR_ROLE"), admin.address) // so that we can call donateLiquidity
      await orderBook.donateLiquidity(pool1.address, arb.address, toWei("10"))
      await orderBook.revokeRole(ethers.utils.id("FEE_DONATOR_ROLE"), admin.address)
      {
        const balances = await pool1.liquidityBalances()
        expect(balances.tokens[0]).to.equal(usdc.address)
        expect(balances.balances[0]).to.equal(toWei("0"))
        expect(balances.tokens[1]).to.equal(arb.address)
        expect(balances.balances[1]).to.equal(toWei("10"))
      }
      {
        expect(await pool1.getAumUsd()).to.equal(toWei("20"))
      }
    })

    it("rebalance - limit by maxRawAmount1", async () => {
      await rebalancer.placeOrder({
        poolAddress: pool1.address,
        token0: arb.address,
        rawAmount0: toWei("10"),
        maxRawAmount1: toUnit("0", 6), // 10 * 2 / 1
        userData: ethers.utils.toUtf8Bytes("TestRebalancer.userData"),
      })
      await expect(orderBook.connect(broker).fillRebalanceOrder(0)).to.be.revertedWith("LimitPriceNotMet")
    })

    it("rebalance", async () => {
      await usdc.mint(rebalancer.address, toUnit("1000000", 6))
      await rebalancer.placeOrder({
        poolAddress: pool1.address,
        token0: arb.address,
        rawAmount0: toWei("10"),
        maxRawAmount1: toUnit("20", 6), // 10 * 2 / 1
        userData: ethers.utils.toUtf8Bytes("TestRebalancer.userData"),
      })
      expect(await usdc.balanceOf(rebalancer.address)).to.equal(toUnit("1000000", 6))
      expect(await arb.balanceOf(rebalancer.address)).to.equal(toUnit("0", 18))
      await orderBook.connect(broker).fillRebalanceOrder(0)
      expect(await usdc.balanceOf(rebalancer.address)).to.equal(toUnit("999980", 6)) // 1000000 - 20
      expect(await arb.balanceOf(rebalancer.address)).to.equal(toUnit("10", 18)) // rawAmount0
      {
        const balances = await pool1.liquidityBalances()
        expect(balances.tokens[0]).to.equal(usdc.address)
        expect(balances.balances[0]).to.equal(toWei("20"))
        expect(balances.tokens[1]).to.equal(arb.address)
        expect(balances.balances[1]).to.equal(toWei("0"))
      }
      {
        expect(await pool1.getAumUsd()).to.equal(toWei("20"))
      }
    })

    it("cancel rebalance", async () => {
      await usdc.mint(rebalancer.address, toUnit("1000000", 6))
      await rebalancer.placeOrder({
        poolAddress: pool1.address,
        token0: arb.address,
        rawAmount0: toWei("10"),
        maxRawAmount1: toUnit("20", 6), // 10 * 2 / 1
        userData: ethers.utils.toUtf8Bytes("TestRebalancer.userData"),
      })
      expect(await usdc.balanceOf(rebalancer.address)).to.equal(toUnit("1000000", 6))
      expect(await arb.balanceOf(rebalancer.address)).to.equal(toUnit("0", 18))
      await time.increaseTo(timestampOfTest + 30)
      await expect(orderBook.connect(trader1).cancelOrder(0)).to.be.revertedWith("Not authorized")
      await rebalancer.cancelOrder(0)
      expect(await usdc.balanceOf(rebalancer.address)).to.equal(toUnit("1000000", 6))
      expect(await arb.balanceOf(rebalancer.address)).to.equal(toUnit("0", 18))
    })
  })
})
