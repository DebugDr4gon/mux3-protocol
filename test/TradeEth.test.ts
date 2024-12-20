import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import {
  toWei,
  createContract,
  toBytes32,
  encodePositionId,
  toUnit,
  zeroAddress,
  encodePoolMarketKey,
  PositionOrderFlags,
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
} from "../typechain"
import { time } from "@nomicfoundation/hardhat-network-helpers"

const a2b = (a) => {
  return a + "000000000000000000000000"
}
const u2b = (u) => {
  return ethers.utils.hexZeroPad(u.toTwos(256).toHexString(), 32)
}

describe("Trade, eth collateral", () => {
  const refCode = toBytes32("")
  const long1 = toBytes32("LongBTC")

  let usdc: MockERC20
  let weth: WETH9

  let admin: SignerWithAddress
  let broker: SignerWithAddress
  let lp1: SignerWithAddress
  let trader1: SignerWithAddress
  let trader2: SignerWithAddress

  let core: TestMux3
  let imp: CollateralPool
  let pool1: CollateralPool
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
    await usdc.mint(lp1.address, toUnit("1000000", 6))
    await usdc.mint(trader1.address, toUnit("100000", 6))
    await usdc.mint(trader2.address, toUnit("100000", 6))

    // core
    core = (await createContract("TestMux3", [])) as TestMux3
    await core.initialize(weth.address)
    await core.addCollateralToken(usdc.address, 6, true)
    await core.addCollateralToken(weth.address, 18, false)
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
    const emitter = await createContract("CollateralPoolEventEmitter")
    await emitter.initialize(core.address)
    imp = (await createContract("CollateralPool", [
      core.address,
      orderBook.address,
      weth.address,
      emitter.address,
    ])) as CollateralPool
    await core.setCollateralPoolImplementation(imp.address)

    // pool 1
    await core.createCollateralPool("TN0", "TS0", weth.address, 0)
    const poolAddr = (await core.listCollateralPool())[0]
    pool1 = (await ethers.getContractAt("CollateralPool", poolAddr)) as CollateralPool
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("10")))
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-7")))
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000")))
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", long1), u2b(toWei("0.80")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", long1), u2b(toWei("0.75")))
    await core.setPoolConfig(pool1.address, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", long1), u2b(toWei("0.70")))

    // market 1 - uses 2 pools
    await core.createMarket(
      long1,
      "Long1",
      true, // isLong
      [pool1.address]
    )
    await core.setMarketConfig(long1, ethers.utils.id("MM_POSITION_FEE_RATE"), u2b(toWei("0.001")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_LIQUIDATION_FEE_RATE"), u2b(toWei("0.002")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_INITIAL_MARGIN_RATE"), u2b(toWei("0.006")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_MAINTENANCE_MARGIN_RATE"), u2b(toWei("0.005")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.0001")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_ORACLE_ID"), a2b(weth.address))
    await core.setMarketConfig(long1, ethers.utils.id("MM_OPEN_INTEREST_CAP_USD"), u2b(toWei("100000000")))

    // feeDistributor
    feeDistributor = (await createContract("MockMux3FeeDistributor", [core.address])) as MockMux3FeeDistributor
    await core.setConfig(ethers.utils.id("MC_FEE_DISTRIBUTOR"), a2b(feeDistributor.address))

    // role
    await orderBook.grantRole(ethers.utils.id("BROKER_ROLE"), broker.address)
    await core.grantRole(ethers.utils.id("ORDER_BOOK_ROLE"), orderBook.address)

    // price
    await core.setMockPrice(a2b(usdc.address), toWei("1"))
    await core.setMockPrice(a2b(weth.address), toWei("3000"))

    // swapper
    uniswap = (await createContract("MockUniswapV3", [
      usdc.address,
      weth.address,
      zeroAddress,
      zeroAddress,
    ])) as MockUniswapV3
    const swapper = (await createContract("Swapper", [])) as Swapper
    await swapper.initialize(weth.address, uniswap.address, uniswap.address)
    await core.setConfig(ethers.utils.id("MC_SWAPPER"), a2b(swapper.address))
  })

  describe("add liquidity", () => {
    beforeEach(async () => {
      await time.increaseTo(timestampOfTest + 86400 * 2)
      await orderBook.wrapNative(toWei("100"), { value: toWei("100") })
      {
        const args = {
          poolAddress: pool1.address,
          rawAmount: toWei("100"),
          isAdding: true,
          isUnwrapWeth: true,
        }
        await orderBook.connect(lp1).placeLiquidityOrder(args)
      }
      {
        await time.increaseTo(timestampOfTest + 86400 * 2 + 930)
        await orderBook.connect(broker).fillLiquidityOrder(0)
        expect(await weth.balanceOf(feeDistributor.address)).to.equal(toWei("0.01")) // fee = 100 * 0.01%
        expect(await weth.balanceOf(pool1.address)).to.equal(toWei("99.99"))
        expect(await pool1.balanceOf(lp1.address)).to.equal(toWei("299970")) // 99.99 * 3000
      }
      {
        const [poolTokens, poolBalances] = await pool1.liquidityBalances()
        expect(poolTokens[1]).to.equal(weth.address)
        expect(poolBalances[1]).to.equal(toWei("99.99")) // 100 - fee
      }
    })

    it("remove liquidity", async () => {
      {
        const args = { poolAddress: pool1.address, rawAmount: toWei("3000"), isAdding: false, isUnwrapWeth: true }
        await expect(orderBook.connect(lp1).placeLiquidityOrder(args)).to.revertedWith("not enough")
        await pool1.connect(lp1).transfer(orderBook.address, toWei("3000"))
        await orderBook.connect(lp1).placeLiquidityOrder(args)
      }
      {
        const balance1 = await ethers.provider.getBalance(lp1.address)
        await time.increaseTo(timestampOfTest + 86400 * 2 + 930 + 930)
        await orderBook.connect(broker).fillLiquidityOrder(1)
        const balance2 = await ethers.provider.getBalance(lp1.address)
        expect(balance2.sub(balance1).toString()).to.equal(toWei("0.9999")) // return 3000 * (1 - 0.0001) / 3000
      }
    })

    describe("deposit", () => {
      let positionId: string

      beforeEach(async () => {
        positionId = encodePositionId(trader1.address, 0)
        await orderBook.wrapNative(toWei("1"), { value: toWei("1") })
        await orderBook.connect(trader1).depositCollateral(positionId, weth.address, toWei("1"))
        {
          const collaterals = await core.listAccountCollaterals(positionId)
          expect(collaterals.length).to.equal(1)
          expect(collaterals[0].collateralAddress).to.equal(weth.address)
          expect(collaterals[0].collateralAmount).to.equal(toWei("1"))
        }
      })

      it("withdrawAll", async () => {
        const balance1 = await ethers.provider.getBalance(trader1.address)
        const args = {
          positionId,
          isUnwrapWeth: true,
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
        }
        await orderBook.connect(trader1).withdrawAllCollateral(args)
        const balance2 = await ethers.provider.getBalance(trader1.address)
        expect(balance2.sub(balance1).lte(toWei("1"))).to.be.true
        expect(balance2.sub(balance1).gt(toWei("0.999"))).to.be.true
      })

      it("withdraw", async () => {
        const args = {
          positionId,
          tokenAddress: weth.address,
          rawAmount: toWei("1"),
          isUnwrapWeth: true,
          lastConsumedToken: weth.address,
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
        }
        await orderBook.connect(trader1).placeWithdrawalOrder(args)
        const balance1 = await ethers.provider.getBalance(trader1.address)
        await orderBook.connect(broker).fillWithdrawalOrder(1)
        const balance2 = await ethers.provider.getBalance(trader1.address)
        expect(balance2.sub(balance1).toString()).to.equal(toWei("1"))
      })
    })

    it("open but cancel", async () => {
      const positionId = encodePositionId(trader1.address, 0)
      await orderBook.connect(trader1).setInitialLeverage(positionId, long1, toWei("100"))
      await orderBook.connect(trader1).wrapNative(toWei("1"), { value: toWei("1") })
      {
        const args = {
          positionId,
          marketId: long1,
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.UnwrapEth + PositionOrderFlags.MarketOrder,
          limitPrice: toWei("50000"),
          expiration: timestampOfTest + 86400 * 2 + 930 + 300,
          lastConsumedToken: zeroAddress,
          collateralToken: weth.address,
          collateralAmount: toWei("1"),
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
        await orderBook.connect(trader1).placePositionOrder(args, refCode)
      }
      {
        await expect(orderBook.connect(trader1).cancelOrder(1)).to.be.revertedWith("Cool down")
        await time.increaseTo(timestampOfTest + 86400 * 2 + 930 + 150)
        const balance1 = await ethers.provider.getBalance(trader1.address)
        await orderBook.connect(broker).cancelOrder(1)
        const balance2 = await ethers.provider.getBalance(trader1.address)
        expect(balance2.sub(balance1).toString()).to.equal(toWei("1"))
      }
    })
  })

  it("multicall - depositGas", async () => {
    await orderBook.multicall(
      [
        orderBook.interface.encodeFunctionData("wrapNative", [toWei("0.01")]),
        orderBook.interface.encodeFunctionData("depositGas", [admin.address, toWei("0.01")]),
      ],
      { value: toWei("0.01") }
    )
  })
})
