import { ethers, waffle } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import {
  toWei,
  toUnit,
  createContract,
  OrderType,
  PositionOrderFlags,
  toBytes32,
  encodePositionId,
  zeroAddress,
  parsePositionOrder,
  parseLiquidityOrder,
  parseWithdrawalOrder,
} from "../scripts/deployUtils"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import {
  ERC20PresetMinterPauser,
  MockCollateralPool,
  MockMux3,
  OrderBook,
  WETH9,
  MockUniswap3,
  Swapper,
} from "../typechain"
import { time } from "@nomicfoundation/hardhat-network-helpers"
import { BigNumber } from "ethers"

const a2b = (a) => {
  return a + "000000000000000000000000"
}
const u2b = (u) => {
  return ethers.utils.hexZeroPad(u.toTwos(256).toHexString(), 32)
}

describe("Order", () => {
  const refCode = toBytes32("")
  const mid0 = "0x1110000000000000000000000000000000000000000000000000000000000000"

  let token0: ERC20PresetMinterPauser
  let token1: ERC20PresetMinterPauser
  let token2: ERC20PresetMinterPauser
  let weth: WETH9

  let user0: SignerWithAddress
  let broker: SignerWithAddress

  let core: MockMux3
  let imp: MockCollateralPool
  let pool1: MockCollateralPool
  let orderBook: OrderBook

  let timestampOfTest: number

  before(async () => {
    const accounts = await ethers.getSigners()
    user0 = accounts[0]
    broker = accounts[1]
    weth = (await createContract("WETH9", [])) as WETH9
  })

  beforeEach(async () => {
    timestampOfTest = await time.latest()
    timestampOfTest = Math.ceil(timestampOfTest / 3600) * 3600 // move to the next hour

    token0 = (await createContract("ERC20PresetMinterPauser", ["TK0", "TK0"])) as ERC20PresetMinterPauser
    token1 = (await createContract("ERC20PresetMinterPauser", ["TK1", "TK1"])) as ERC20PresetMinterPauser
    token2 = (await createContract("ERC20PresetMinterPauser", ["TK2", "TK2"])) as ERC20PresetMinterPauser

    // core
    core = (await createContract("MockMux3", [])) as MockMux3
    await core.initialize(weth.address)
    await core.addCollateralToken(token0.address, 18, false)
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
    await orderBook.grantRole(ethers.utils.id("BROKER_ROLE"), broker.address)
    await orderBook.setConfig(ethers.utils.id("MCO_LIQUIDITY_LOCK_PERIOD"), u2b(ethers.BigNumber.from(60 * 15)))
    await orderBook.setConfig(ethers.utils.id("MCO_MARKET_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(60 * 2)))
    await orderBook.setConfig(ethers.utils.id("MCO_LIMIT_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(86400 * 30)))
    await orderBook.setConfig(ethers.utils.id("MCO_CANCEL_COOL_DOWN"), u2b(ethers.BigNumber.from(5)))
    await orderBook.setConfig(ethers.utils.id("MCO_MIN_LIQUIDITY_ORDER_USD"), u2b(toWei("0.1")))

    // collateral pool
    imp = (await createContract("MockCollateralPool", [
      core.address,
      orderBook.address,
      weth.address,
    ])) as MockCollateralPool
    await core.setCollateralPoolImplementation(imp.address)

    // pool 1
    await core.createCollateralPool("TN0", "TS0", token0.address, 0)
    const poolAddr = (await core.listCollateralPool())[0]
    pool1 = (await ethers.getContractAt("MockCollateralPool", poolAddr)) as MockCollateralPool
    await pool1.setConfig(ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306")))
    await pool1.setConfig(ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938")))

    // market
    await core.createMarket(mid0, "MARKET0", true, [pool1.address])
    await core.setMarketConfig(mid0, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.1")))
    await core.setMarketConfig(mid0, ethers.utils.id("MM_ORACLE_ID"), a2b(token0.address))
    await core.setMarketConfig(mid0, ethers.utils.id("MM_OPEN_INTEREST_CAP_USD"), u2b(toWei("100000000")))

    // prices
    await core.setMockPrice(a2b(token0.address), toWei("2"))
  })

  it("place", async () => {
    {
      await token0.mint(user0.address, toWei("1"))
      await token0.transfer(orderBook.address, toWei("1"))
      const positionId = encodePositionId(user0.address, 0)
      await orderBook.connect(user0).setInitialLeverage(positionId, mid0, toWei("10"))
      await orderBook.placePositionOrder(
        {
          positionId,
          marketId: mid0,
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
          limitPrice: toWei("3000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          lastConsumedToken: zeroAddress,
          collateralToken: token0.address,
          collateralAmount: toWei("1"),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("1.005"),
          slPriceDiff: toWei("0.995"),
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          tpslFlags:
            PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.WithdrawProfit + PositionOrderFlags.UnwrapEth,
          tpslWithdrawSwapToken: token0.address,
          tpslWithdrawSwapSlippage: toWei("0"),
        },
        refCode
      )
      const orders = await orderBook.getOrders(0, 100)
      expect(orders.totalCount).to.equal(1)
      expect(orders.orderDataArray.length).to.equal(1)
      {
        const order2 = await orderBook.getOrder(0)
        expect(order2[0].payload).to.equal(orders.orderDataArray[0].payload)
      }
      {
        const orders3 = await orderBook.getOrdersOf(user0.address, 0, 100)
        expect(orders3.totalCount).to.equal(1)
        expect(orders3.orderDataArray.length).to.equal(1)
        expect(orders3.orderDataArray[0].payload).to.equal(orders.orderDataArray[0].payload)
      }
      expect(orders.orderDataArray[0].id).to.equal(0)
      expect(orders.orderDataArray[0].orderType).to.equal(OrderType.Position)
      const order = parsePositionOrder(orders.orderDataArray[0].payload)
      expect(order.positionId).to.equal(encodePositionId(user0.address, 0))
      expect(order.marketId).to.equal(mid0)
      expect(order.size).to.equal(toWei("1"))
      expect(order.flags).to.equal(PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder)
      expect(order.limitPrice).to.equal(toWei("3000"))
      expect(order.expiration).to.equal(timestampOfTest + 1000 + 86400 * 3)
      expect(order.lastConsumedToken).to.equal(zeroAddress)
      expect(order.collateralToken).to.equal(token0.address)
      expect(order.collateralAmount).to.equal(toWei("1"))
      expect(order.withdrawUsd).to.equal(toWei("0"))
      expect(order.withdrawSwapToken).to.equal(zeroAddress)
      expect(order.withdrawSwapSlippage).to.equal(toWei("0"))
      expect(order.tpPriceDiff).to.equal(toWei("1.005"))
      expect(order.slPriceDiff).to.equal(toWei("0.995"))
      expect(order.tpslExpiration).to.equal(timestampOfTest + 2000 + 86400 * 3)
      expect(order.tpslFlags).to.equal(
        PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.WithdrawProfit + PositionOrderFlags.UnwrapEth
      )
      expect(order.tpslWithdrawSwapToken).to.equal(token0.address)
      expect(order.tpslWithdrawSwapSlippage).to.equal(toWei("0"))
    }
    expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("1"))
    expect(await token0.balanceOf(user0.address)).to.equal(toWei("0"))
    {
      await token0.mint(user0.address, toWei("40"))
      await token0.transfer(orderBook.address, toWei("40"))
      await orderBook.connect(user0).placeLiquidityOrder({
        poolAddress: pool1.address,
        rawAmount: toWei("40"),
        isAdding: true,
        isUnwrapWeth: false,
      })
      const orders = await orderBook.getOrders(0, 100)
      expect(orders.totalCount).to.equal(2)
      expect(orders.orderDataArray.length).to.equal(2)
      {
        const order2 = await orderBook.getOrder(1)
        expect(order2[0].payload).to.equal(orders.orderDataArray[1].payload)
      }
      {
        const orders3 = await orderBook.getOrdersOf(user0.address, 0, 100)
        expect(orders3.totalCount).to.equal(2)
        expect(orders3.orderDataArray.length).to.equal(2)
        expect(orders3.orderDataArray[1].payload).to.equal(orders.orderDataArray[1].payload)
      }
      expect(orders.orderDataArray[1].orderType).to.equal(OrderType.Liquidity)
      const order = parseLiquidityOrder(orders.orderDataArray[1].payload)
      expect(order.poolAddress).to.equal(pool1.address)
      expect(order.rawAmount).to.equal(toWei("40"))
      expect(order.isAdding).to.equal(true)
    }
    {
      await orderBook.connect(user0).placeWithdrawalOrder({
        positionId: encodePositionId(user0.address, 0),
        tokenAddress: token0.address,
        rawAmount: toWei("500"),
        isUnwrapWeth: false,
        lastConsumedToken: zeroAddress,
        withdrawSwapToken: zeroAddress,
        withdrawSwapSlippage: toWei("0"),
      })
      const orders = await orderBook.getOrders(0, 100)
      expect(orders.totalCount).to.equal(3)
      expect(orders.orderDataArray.length).to.equal(3)
      {
        const order2 = await orderBook.getOrder(2)
        expect(order2[0].payload).to.equal(orders.orderDataArray[2].payload)
      }
      {
        const orders3 = await orderBook.getOrdersOf(user0.address, 0, 100)
        expect(orders3.totalCount).to.equal(3)
        expect(orders3.orderDataArray.length).to.equal(3)
        expect(orders3.orderDataArray[2].payload).to.equal(orders.orderDataArray[2].payload)
      }
      expect(orders.orderDataArray[2].orderType).to.equal(OrderType.Withdrawal)
      const order = parseWithdrawalOrder(orders.orderDataArray[2].payload)
      expect(order.positionId).to.equal(encodePositionId(user0.address, 0))
      expect(order.tokenAddress).to.equal(token0.address)
      expect(order.rawAmount).to.equal(toWei("500"))
      expect(order.isUnwrapWeth).to.equal(false)
      expect(order.lastConsumedToken).to.equal(zeroAddress)
      expect(order.withdrawSwapToken).to.equal(zeroAddress)
      expect(order.withdrawSwapSlippage).to.equal(toWei("0"))
    }
  })

  it("lotSize", async () => {
    await expect(
      orderBook.placePositionOrder(
        {
          positionId: encodePositionId(user0.address, 0),
          marketId: mid0,
          size: toWei("0.05"),
          flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
          limitPrice: toWei("3000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          lastConsumedToken: zeroAddress,
          collateralToken: token0.address,
          collateralAmount: toWei("1"),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("1.005"),
          slPriceDiff: toWei("0.995"),
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          tpslFlags:
            PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.WithdrawProfit + PositionOrderFlags.UnwrapEth,
          tpslWithdrawSwapToken: token0.address,
          tpslWithdrawSwapSlippage: toWei("0"),
        },
        refCode
      )
    ).to.revertedWith("lot size")
  })

  it("market should be exist", async () => {
    await expect(
      orderBook.placePositionOrder(
        {
          positionId: encodePositionId(user0.address, 0),
          marketId: "0xabcd000000000000000000000000000000000000000000000000000000000000",
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
          limitPrice: toWei("3000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          lastConsumedToken: zeroAddress,
          collateralToken: token0.address,
          collateralAmount: toWei("1"),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("1.005"),
          slPriceDiff: toWei("0.995"),
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          tpslFlags:
            PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.WithdrawProfit + PositionOrderFlags.UnwrapEth,
          tpslWithdrawSwapToken: token0.address,
          tpslWithdrawSwapSlippage: toWei("0"),
        },
        refCode
      )
    ).to.revertedWith("marketId")
  })

  it("collateral should exist", async () => {
    await expect(
      orderBook.placePositionOrder(
        {
          positionId: encodePositionId(user0.address, 0),
          marketId: mid0,
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
          limitPrice: toWei("3000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          lastConsumedToken: zeroAddress,
          collateralToken: user0.address,
          collateralAmount: toWei("1"),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("1.005"),
          slPriceDiff: toWei("0.995"),
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          tpslFlags:
            PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.WithdrawProfit + PositionOrderFlags.UnwrapEth,
          tpslWithdrawSwapToken: token0.address,
          tpslWithdrawSwapSlippage: toWei("0"),
        },
        refCode
      )
    ).to.revertedWith("collateralToken")
  })

  it("liquidity should exist", async () => {
    {
      await expect(
        orderBook.connect(user0).placeLiquidityOrder({
          poolAddress: user0.address,
          rawAmount: toWei("40"),
          isAdding: true,
          isUnwrapWeth: false,
        })
      ).to.revertedWith("Invalid pool")
    }
  })

  it("placePositionOrder - open long position, cancel, open, fill", async () => {
    await token0.mint(user0.address, toWei("1000"))
    await token0.transfer(orderBook.address, toWei("100"))
    // no1
    await time.increaseTo(timestampOfTest + 86400)
    const positionId = encodePositionId(user0.address, 0)
    await orderBook.connect(user0).setInitialLeverage(positionId, mid0, toWei("10"))
    {
      await orderBook.placePositionOrder(
        {
          positionId,
          marketId: mid0,
          size: toWei("0.1"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("1000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          lastConsumedToken: zeroAddress,
          collateralToken: token0.address,
          collateralAmount: toWei("100"),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("0"),
          slPriceDiff: toWei("0"),
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          tpslFlags: 0,
          tpslWithdrawSwapToken: zeroAddress,
          tpslWithdrawSwapSlippage: toWei("0"),
        },
        refCode
      )
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("100"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }
      await expect(orderBook.cancelOrder(0)).to.revertedWith("Cool down")
      await time.increaseTo(timestampOfTest + 86400 + 10)
      await orderBook.cancelOrder(0)
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("1000"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // no2
    await token0.transfer(orderBook.address, toWei("100"))
    {
      await orderBook.placePositionOrder(
        {
          positionId: encodePositionId(user0.address, 0),
          marketId: mid0,
          size: toWei("0.1"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("1000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          lastConsumedToken: zeroAddress,
          collateralToken: token0.address,
          collateralAmount: toWei("100"),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("0"),
          slPriceDiff: toWei("0"),
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          tpslFlags: 0,
          tpslWithdrawSwapToken: zeroAddress,
          tpslWithdrawSwapSlippage: toWei("0"),
        },
        refCode
      )
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("100"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }
      await expect(orderBook.connect(broker).fillLiquidityOrder(1, [])).to.revertedWith("Order type")
      await expect(orderBook.connect(broker).fillWithdrawalOrder(1)).to.revertedWith("Order type")
      await orderBook.connect(broker).fillPositionOrder(1)
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(false)
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await token0.balanceOf(core.address)).to.equal(toWei("100"))
    }
  })

  it("placeLiquidityOrder - addLiquidity", async () => {
    await token0.mint(user0.address, toWei("1000"))
    await token0.transfer(orderBook.address, toWei("150"))
    // no1
    {
      await orderBook.placeLiquidityOrder({
        poolAddress: pool1.address,
        rawAmount: toWei("150"),
        isAdding: true,
        isUnwrapWeth: false,
      })
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("850"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("150"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }
      await expect(orderBook.cancelOrder(0)).to.revertedWith("Cool down")
      await time.increaseTo(timestampOfTest + 86400 + 10)
      await orderBook.cancelOrder(0)
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("1000"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // no2
    await token0.transfer(orderBook.address, toWei("150"))
    {
      await orderBook.placeLiquidityOrder({
        poolAddress: pool1.address,
        rawAmount: toWei("150"),
        isAdding: true,
        isUnwrapWeth: false,
      })
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("850"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("150"))
      expect(await token0.balanceOf(pool1.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }
      await expect(orderBook.connect(broker).fillLiquidityOrder(1, [])).to.revertedWith("lock period")
      await time.increaseTo(timestampOfTest + 86400 + 60 * 20)
      await expect(orderBook.connect(broker).fillPositionOrder(1)).to.revertedWith("Order type")
      await expect(orderBook.connect(broker).fillWithdrawalOrder(1)).to.revertedWith("Order type")
      await orderBook.connect(broker).fillLiquidityOrder(1, [])
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(false)
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("850"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await token0.balanceOf(pool1.address)).to.equal(toWei("150"))
    }
  })

  it("placeLiquidityOrder - removeLiquidity", async () => {
    await token0.mint(user0.address, toWei("1000"))
    await token0.transfer(orderBook.address, toWei("150"))
    // add liquidity
    {
      await orderBook.placeLiquidityOrder({
        poolAddress: pool1.address,
        rawAmount: toWei("150"),
        isAdding: true,
        isUnwrapWeth: false,
      })
      await time.increaseTo(timestampOfTest + 86400 + 60 * 20)
      await orderBook.connect(broker).fillLiquidityOrder(0, [])
    }
    expect(await pool1.balanceOf(user0.address)).to.equal(toWei("0")) // because this test uses a mocked liquidity pool
    // no1
    await pool1.mint(user0.address, toWei("2"))
    await pool1.transfer(orderBook.address, toWei("1"))
    {
      await orderBook.placeLiquidityOrder({
        poolAddress: pool1.address,
        rawAmount: toWei("1"),
        isAdding: false,
        isUnwrapWeth: false,
      })
      expect(await pool1.balanceOf(user0.address)).to.equal(toWei("1"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }
      await expect(orderBook.cancelOrder(1)).to.revertedWith("Cool down")
      await time.increaseTo(timestampOfTest + 86400 + 60 * 30)
      await orderBook.cancelOrder(1)
      expect(await pool1.balanceOf(user0.address)).to.equal(toWei("2"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // no2
    await pool1.transfer(orderBook.address, toWei("1"))
    {
      await orderBook.placeLiquidityOrder({
        poolAddress: pool1.address,
        rawAmount: toWei("1"),
        isAdding: false,
        isUnwrapWeth: false,
      })
      expect(await pool1.balanceOf(user0.address)).to.equal(toWei("1"))
      expect(await pool1.balanceOf(orderBook.address)).to.equal(toWei("1"))
      expect(await pool1.balanceOf(pool1.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }
      await time.increaseTo(timestampOfTest + 86400 + 60 * 50)
      await orderBook.connect(broker).fillLiquidityOrder(2, [])
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(false)
      expect(await pool1.balanceOf(user0.address)).to.equal(toWei("1"))
      expect(await pool1.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await pool1.balanceOf(pool1.address)).to.equal(toWei("1")) // because this test uses a mocked liquidity pool
    }
  })

  it("broker can cancel orders", async () => {
    await token0.mint(orderBook.address, toWei("100"))
    // limit order
    await time.increaseTo(timestampOfTest + 1000)
    const positionId = encodePositionId(user0.address, 0)
    {
      await orderBook.placePositionOrder(
        {
          positionId,
          marketId: mid0,
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("3000"),
          expiration: timestampOfTest + 1000 + 86400 * 365,
          lastConsumedToken: zeroAddress,
          collateralToken: token0.address,
          collateralAmount: toWei("100"),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("1.005"),
          slPriceDiff: toWei("0.995"),
          tpslExpiration: timestampOfTest + 2000 + 86400 * 365,
          tpslFlags: 0,
          tpslWithdrawSwapToken: token0.address,
          tpslWithdrawSwapSlippage: toWei("0"),
        },
        refCode
      )
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("0"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("100"))
      await time.increaseTo(timestampOfTest + 1000 + 86400 * 30 - 5)
      await expect(orderBook.connect(broker).cancelOrder(0)).revertedWith("Not expired")
      await time.increaseTo(timestampOfTest + 1000 + 86400 * 30 + 5)
      await orderBook.connect(broker).cancelOrder(0)
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("100"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // withdraw order
    {
      const args = {
        positionId,
        tokenAddress: token0.address,
        rawAmount: toWei("100"),
        isUnwrapWeth: false,
        lastConsumedToken: zeroAddress,
        withdrawSwapToken: zeroAddress,
        withdrawSwapSlippage: toWei("0"),
      }
      await orderBook.placeWithdrawalOrder(args)
      await time.increaseTo(timestampOfTest + 1000 + 86400 * 30 + 5 + 110)
      await expect(orderBook.connect(broker).cancelOrder(1)).revertedWith("Not expired")
      await time.increaseTo(timestampOfTest + 1000 + 86400 * 30 + 5 + 130)
      await orderBook.connect(broker).cancelOrder(1)
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("100"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // market order
    {
      await token0.mint(orderBook.address, toWei("100"))
      await orderBook.placePositionOrder(
        {
          positionId,
          marketId: mid0,
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
          limitPrice: toWei("3000"),
          expiration: timestampOfTest + 1000 + 86400 * 365,
          lastConsumedToken: zeroAddress,
          collateralToken: token0.address,
          collateralAmount: toWei("100"),
          withdrawUsd: toWei("0"),
          withdrawSwapToken: zeroAddress,
          withdrawSwapSlippage: toWei("0"),
          tpPriceDiff: toWei("1.005"),
          slPriceDiff: toWei("0.995"),
          tpslExpiration: timestampOfTest + 2000 + 86400 * 365,
          tpslFlags: 0,
          tpslWithdrawSwapToken: token0.address,
          tpslWithdrawSwapSlippage: toWei("0"),
        },
        refCode
      )
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("100"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("100"))
      await time.increaseTo(timestampOfTest + 1000 + 86400 * 30 + 5 + 130 + 110)
      await expect(orderBook.connect(broker).cancelOrder(2)).revertedWith("Not expired")
      await time.increaseTo(timestampOfTest + 1000 + 86400 * 30 + 5 + 130 + 130)
      await orderBook.connect(broker).cancelOrder(2)
      expect(await token0.balanceOf(user0.address)).to.equal(toWei("200"))
      expect(await token0.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
  })

  it("placeLiquidityOrder - broker fee", async () => {
    await orderBook.setConfig(ethers.utils.id("MCO_ORDER_GAS_FEE_GWEI"), u2b(BigNumber.from("1000000")))
    await token0.mint(user0.address, toWei("1000"))
    await token0.transfer(orderBook.address, toWei("150"))
    // no1 - gas fee
    await weth.deposit({ value: toUnit("1", 6 + 9) })
    await weth.transfer(orderBook.address, toUnit("1", 6 + 9))
    await orderBook.depositGas(user0.address, toUnit("1", 6 + 9))
    expect(await orderBook.gasBalanceOf(user0.address)).to.equal(toUnit("1", 6 + 9))
    const args = {
      poolAddress: pool1.address,
      rawAmount: toWei("150"),
      isAdding: true,
      isUnwrapWeth: false,
    }
    await orderBook.placeLiquidityOrder(args)
    await time.increaseTo(timestampOfTest + 86400 + 10)

    {
      const balance = await waffle.provider.getBalance(user0.address)
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("1", 6 + 9))
      expect(await orderBook.gasBalanceOf(user0.address)).to.equal(toUnit("0", 6 + 9))
      const tx = await orderBook.cancelOrder(0)
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("0", 6 + 9))
      const receipt = await tx.wait()
      const gasUsed = receipt.gasUsed
      const gasPrice = receipt.effectiveGasPrice
      expect(await waffle.provider.getBalance(user0.address)).to.equal(
        balance.add(toUnit("1", 6 + 9)).sub(gasUsed.mul(gasPrice))
      )
    }

    await token0.mint(user0.address, toWei("1000"))
    await token0.transfer(orderBook.address, toWei("150"))
    await weth.deposit({ value: toUnit("1", 6 + 9) })
    await weth.transfer(orderBook.address, toUnit("1", 6 + 9))
    await orderBook.depositGas(user0.address, toUnit("1", 6 + 9))
    await orderBook.placeLiquidityOrder(args)
    await time.increaseTo(timestampOfTest + 86400 + 10 + 886400 + 10)

    {
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("1", 6 + 9))
      const balance = await waffle.provider.getBalance(broker.address)
      const tx = await orderBook.connect(broker).fillLiquidityOrder(1, [])
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("0", 6 + 9))
      const receipt = await tx.wait()
      const gasUsed = receipt.gasUsed
      const gasPrice = receipt.effectiveGasPrice
      expect(await waffle.provider.getBalance(broker.address)).to.equal(
        balance.add(toUnit("1", 6 + 9)).sub(gasUsed.mul(gasPrice))
      )
    }
  })

  it("place position order - broker fee", async () => {
    await orderBook.setConfig(ethers.utils.id("MCO_ORDER_GAS_FEE_GWEI"), u2b(BigNumber.from("1000000")))
    await token0.mint(user0.address, toWei("1"))
    await token0.transfer(orderBook.address, toWei("1"))
    const positionId = encodePositionId(user0.address, 0)
    await orderBook.connect(user0).setInitialLeverage(positionId, mid0, toWei("10"))
    const args = {
      positionId,
      marketId: mid0,
      size: toWei("1"),
      flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
      limitPrice: toWei("3000"),
      expiration: timestampOfTest + 1000 + 86400 * 2,
      lastConsumedToken: zeroAddress,
      collateralToken: token0.address,
      collateralAmount: toWei("1"),
      withdrawUsd: toWei("0"),
      withdrawSwapToken: zeroAddress,
      withdrawSwapSlippage: toWei("0"),
      tpPriceDiff: toWei("1.005"),
      slPriceDiff: toWei("0.995"),
      tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
      tpslFlags:
        PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.WithdrawProfit + PositionOrderFlags.UnwrapEth,
      tpslWithdrawSwapToken: token0.address,
      tpslWithdrawSwapSlippage: toWei("0"),
    }
    await expect(orderBook.placePositionOrder(args, refCode)).to.be.revertedWith("Insufficient gas fee")
    await weth.deposit({ value: toUnit("1", 6 + 9) })
    await weth.transfer(orderBook.address, toUnit("1", 6 + 9))
    await orderBook.depositGas(user0.address, toUnit("1", 6 + 9))
    expect(await orderBook.gasBalanceOf(user0.address)).to.equal(toUnit("1", 6 + 9))
    await orderBook.placePositionOrder(args, refCode)

    {
      await time.increaseTo(timestampOfTest + 10)
      const balance = await waffle.provider.getBalance(user0.address)
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("1", 6 + 9))
      expect(await orderBook.gasBalanceOf(user0.address)).to.equal(toUnit("0", 6 + 9))
      const tx = await orderBook.cancelOrder(0)
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("0", 6 + 9))
      const receipt = await tx.wait()
      const gasUsed = receipt.gasUsed
      const gasPrice = receipt.effectiveGasPrice
      expect(await waffle.provider.getBalance(user0.address)).to.equal(
        balance.add(toUnit("1", 6 + 9)).sub(gasUsed.mul(gasPrice))
      )
    }

    await token0.mint(user0.address, toWei("1000"))
    await token0.transfer(orderBook.address, toWei("150"))
    await weth.deposit({ value: toUnit("1", 6 + 9) })
    await weth.transfer(orderBook.address, toUnit("1", 6 + 9))
    await orderBook.depositGas(user0.address, toUnit("1", 6 + 9))
    await orderBook.placePositionOrder(args, refCode)
    await time.increaseTo(timestampOfTest + 20)

    {
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("1", 6 + 9))
      const balance = await waffle.provider.getBalance(broker.address)
      const tx = await orderBook.connect(broker).fillPositionOrder(1)
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("0", 6 + 9))
      const receipt = await tx.wait()
      const gasUsed = receipt.gasUsed
      const gasPrice = receipt.effectiveGasPrice
      expect(await waffle.provider.getBalance(broker.address)).to.equal(
        balance.add(toUnit("1", 6 + 9)).sub(gasUsed.mul(gasPrice))
      )
    }
  })

  it("withdraw order - broker fee", async () => {
    // swapper
    const uniswap = (await createContract("MockUniswap3", [
      zeroAddress,
      weth.address,
      zeroAddress,
      zeroAddress,
    ])) as MockUniswap3
    const swapper = (await createContract("Swapper", [])) as Swapper
    await swapper.initialize(weth.address)
    await swapper.setUniswap3(uniswap.address, uniswap.address)
    await core.setConfig(ethers.utils.id("MC_SWAPPER"), a2b(swapper.address))

    await orderBook.setConfig(ethers.utils.id("MCO_ORDER_GAS_FEE_GWEI"), u2b(BigNumber.from("1000000")))
    await token0.mint(user0.address, toWei("1"))
    await token0.transfer(orderBook.address, toWei("1"))
    const positionId = encodePositionId(user0.address, 0)
    await orderBook.connect(user0).setInitialLeverage(positionId, mid0, toWei("10"))
    await weth.deposit({ value: toUnit("1", 6 + 9) })
    await weth.transfer(orderBook.address, toUnit("1", 6 + 9))
    await orderBook.depositGas(user0.address, toUnit("1", 6 + 9))
    await orderBook.placePositionOrder(
      {
        positionId,
        marketId: mid0,
        size: toWei("1"),
        flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
        limitPrice: toWei("3000"),
        expiration: timestampOfTest + 1000 + 86400 * 2,
        lastConsumedToken: zeroAddress,
        collateralToken: token0.address,
        collateralAmount: toWei("1"),
        withdrawUsd: toWei("0"),
        withdrawSwapToken: zeroAddress,
        withdrawSwapSlippage: toWei("0"),
        tpPriceDiff: toWei("1.005"),
        slPriceDiff: toWei("0.995"),
        tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
        tpslFlags:
          PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.WithdrawProfit + PositionOrderFlags.UnwrapEth,
        tpslWithdrawSwapToken: token0.address,
        tpslWithdrawSwapSlippage: toWei("0"),
      },
      refCode
    )
    await time.increaseTo(timestampOfTest + 10)

    {
      const balance = await waffle.provider.getBalance(user0.address)
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("1", 6 + 9))
      expect(await orderBook.gasBalanceOf(user0.address)).to.equal(toUnit("0", 6 + 9))
      const tx = await orderBook.cancelOrder(0)
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("0", 6 + 9))
      const receipt = await tx.wait()
      const gasUsed = receipt.gasUsed
      const gasPrice = receipt.effectiveGasPrice
      expect(await waffle.provider.getBalance(user0.address)).to.equal(
        balance.add(toUnit("1", 6 + 9)).sub(gasUsed.mul(gasPrice))
      )
    }

    const args = {
      positionId,
      tokenAddress: token0.address,
      rawAmount: toWei("0.01"),
      isUnwrapWeth: false,
      lastConsumedToken: zeroAddress,
      withdrawSwapToken: zeroAddress,
      withdrawSwapSlippage: 0,
    }
    await weth.deposit({ value: toUnit("1", 6 + 9) })
    await weth.transfer(orderBook.address, toUnit("1", 6 + 9))
    await orderBook.depositGas(user0.address, toUnit("1", 6 + 9))
    await orderBook.placeWithdrawalOrder(args)

    {
      await time.increaseTo(timestampOfTest + 20)
      const balance = await waffle.provider.getBalance(user0.address)
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("1", 6 + 9))
      expect(await orderBook.gasBalanceOf(user0.address)).to.equal(toUnit("0", 6 + 9))
      const tx = await orderBook.cancelOrder(1)
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("0", 6 + 9))
      const receipt = await tx.wait()
      const gasUsed = receipt.gasUsed
      const gasPrice = receipt.effectiveGasPrice
      expect(await waffle.provider.getBalance(user0.address)).to.equal(
        balance.add(toUnit("1", 6 + 9)).sub(gasUsed.mul(gasPrice))
      )
    }

    await token0.mint(user0.address, toWei("1000"))
    await token0.transfer(orderBook.address, toWei("150"))
    await weth.deposit({ value: toUnit("1", 6 + 9) })
    await weth.transfer(orderBook.address, toUnit("1", 6 + 9))
    await orderBook.depositGas(user0.address, toUnit("1", 6 + 9))
    await orderBook.placeWithdrawalOrder(args)

    {
      await time.increaseTo(timestampOfTest + 30)
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("1", 6 + 9))
      const balance = await waffle.provider.getBalance(broker.address)
      const tx = await orderBook.connect(broker).fillWithdrawalOrder(2)
      expect(await weth.balanceOf(orderBook.address)).to.equal(toUnit("0", 6 + 9))
      const receipt = await tx.wait()
      const gasUsed = receipt.gasUsed
      const gasPrice = receipt.effectiveGasPrice
      expect(await waffle.provider.getBalance(broker.address)).to.equal(
        balance.add(toUnit("1", 6 + 9)).sub(gasUsed.mul(gasPrice))
      )
    }
  })

  it("placeLiquidityOrder - addLiquidity to a draining pool", async () => {
    await token0.mint(user0.address, toWei("1000"))
    await token0.transfer(orderBook.address, toWei("150"))
    // no1
    await orderBook.placeLiquidityOrder({
      poolAddress: pool1.address,
      rawAmount: toWei("150"),
      isAdding: true,
      isUnwrapWeth: false,
    })
    await core.setPoolConfig(pool1.address, ethers.utils.id("MCP_IS_DRAINING"), u2b(ethers.BigNumber.from("1")))
    await time.increaseTo(timestampOfTest + 86400 + 10)
    await expect(orderBook.connect(broker).fillLiquidityOrder(0, [])).to.revertedWith("Draining")
    // no2
    await token0.transfer(orderBook.address, toWei("150"))
    await expect(
      orderBook.placeLiquidityOrder({
        poolAddress: pool1.address,
        rawAmount: toWei("150"),
        isAdding: true,
        isUnwrapWeth: false,
      })
    ).to.be.revertedWith("Draining")
  })
})
