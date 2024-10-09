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
  zeroAddress,
} from "../scripts/deployUtils"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import {
  ERC20PresetMinterPauser,
  MockCollateralPool,
  MockFeeDistributor,
  MockMux3,
  OrderBook,
  WETH9,
} from "../typechain"
import { time } from "@nomicfoundation/hardhat-network-helpers"
const U = ethers.utils

const a2b = (a) => {
  return a + "000000000000000000000000"
}
const u2b = (u) => {
  return ethers.utils.hexZeroPad(u.toTwos(256).toHexString(), 32)
}

function parsePositionOrder(orderData: string) {
  const [
    marketId,
    positionId,
    size,
    flags,
    limitPrice,
    tpPrice,
    slPrice,
    expiration,
    tpslExpiration,
    profitToken,
    tpslProfitToken,
    collateralToken,
    collateralAmount,
    initialLeverage,
  ] = ethers.utils.defaultAbiCoder.decode(
    [
      "bytes32",
      "bytes32",
      "uint256",
      "uint256",
      "uint256",
      "uint256",
      "uint256",
      "uint256",
      "uint256",
      "address",
      "address",
      "address",
      "uint256",
      "uint256",
    ],
    orderData
  )
  return {
    marketId,
    positionId,
    size,
    flags,
    limitPrice,
    tpPrice,
    slPrice,
    expiration,
    tpslExpiration,
    profitToken,
    tpslProfitToken,
    collateralToken,
    collateralAmount,
    initialLeverage,
  }
}

function parseLiquidityOrder(orderData: string) {
  const [poolAddress, rawAmount, isAdding] = ethers.utils.defaultAbiCoder.decode(
    ["address", "uint256", "bool"],
    orderData
  )
  return {
    poolAddress,
    rawAmount,
    isAdding,
  }
}

function parseWithdrawalOrder(orderData: string) {
  const [positionId, tokenAddress, rawAmount] = ethers.utils.defaultAbiCoder.decode(
    ["bytes32", "address", "uint256"],
    orderData
  )
  return {
    positionId,
    tokenAddress,
    rawAmount,
  }
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

    token0 = (await createContract("ERC20PresetMinterPauser", ["TK0", "TK0"])) as ERC20PresetMinterPauser
    token1 = (await createContract("ERC20PresetMinterPauser", ["TK1", "TK1"])) as ERC20PresetMinterPauser
    token2 = (await createContract("ERC20PresetMinterPauser", ["TK2", "TK2"])) as ERC20PresetMinterPauser

    core = (await createContract("MockMux3", [])) as MockMux3
    imp = (await createContract("MockCollateralPool", [])) as MockCollateralPool
    await core.initialize()
    await core.setCollateralPoolImplementation(imp.address)
    await core.addCollateralToken(token0.address, 18)
    await core.setCollateralTokenStatus(token0.address, true)
    await core.setConfig(ethers.utils.id("MC_BORROWING_BASE_APY"), u2b(toWei("0.10")))
    await core.setConfig(ethers.utils.id("MC_BORROWING_INTERVAL"), u2b(ethers.BigNumber.from(3600)))

    await core.createCollateralPool("TN0", "TS0", token0.address, 18)
    const poolAddr = (await core.listCollateralPool())[0]
    pool1 = (await ethers.getContractAt("MockCollateralPool", poolAddr)) as MockCollateralPool
    await pool1.setConfig(ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306")))
    await pool1.setConfig(ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938")))
    await pool1.setConfig(ethers.utils.id("MCP_IS_HIGH_PRIORITY"), u2b(toWei("0")))

    await core.setMockPrice(mid0, toWei("1"))
    await core.setMockPrice(a2b(token0.address), toWei("2"))
    await core.createMarket(mid0, "MARKET0", true, [pool1.address])
    await core.setMarketConfig(mid0, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.1")))

    const libOrderBook = await createContract("LibOrderBook")
    orderBook = (await createContract("OrderBook", [], {
      "contracts/libraries/LibOrderBook.sol:LibOrderBook": libOrderBook,
    })) as OrderBook
    await orderBook.initialize(core.address, weth.address)
    await orderBook.grantRole(ethers.utils.id("BROKER_ROLE"), broker.address)
    await orderBook.setConfig(ethers.utils.id("MCO_LIQUIDITY_LOCK_PERIOD"), u2b(ethers.BigNumber.from(60 * 15)))
    await orderBook.setConfig(ethers.utils.id("MCO_MARKET_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(60 * 2)))
    await orderBook.setConfig(ethers.utils.id("MCO_LIMIT_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(86400 * 30)))
    await orderBook.setConfig(ethers.utils.id("MCO_CANCEL_COOL_DOWN"), u2b(ethers.BigNumber.from(5)))
  })

  it("place", async () => {
    {
      await token0.mint(user0.address, toWei("1"))
      await token0.transfer(orderBook.address, toWei("1"))
      await orderBook.placePositionOrder(
        {
          marketId: mid0,
          positionId: encodePositionId(user0.address, 0),
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
          limitPrice: toWei("3000"),
          tpPrice: toWei("4000"),
          slPrice: toWei("2000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          profitToken: zeroAddress,
          tpslProfitToken: zeroAddress,
          collateralToken: token0.address,
          collateralAmount: toWei("1"),
          initialLeverage: toWei("10"),
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
      expect(order.marketId).to.equal(mid0)
      expect(order.positionId).to.equal(encodePositionId(user0.address, 0))
      expect(order.size).to.equal(toWei("1"))
      expect(order.flags).to.equal(PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder)
      expect(order.limitPrice).to.equal(toWei("3000"))
      expect(order.tpPrice).to.equal(toWei("4000"))
      expect(order.slPrice).to.equal(toWei("2000"))
      expect(order.expiration).to.equal(timestampOfTest + 1000 + 86400 * 3)
      expect(order.tpslExpiration).to.equal(timestampOfTest + 2000 + 86400 * 3)
      expect(order.profitToken).to.equal(zeroAddress)
      expect(order.tpslProfitToken).to.equal(zeroAddress)
      expect(order.collateralToken).to.equal(token0.address)
      expect(order.collateralAmount).to.equal(toWei("1"))
      expect(order.initialLeverage).to.equal(toWei("10"))
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
    //     {
    //       await orderBook.connect(user0).placeWithdrawalOrder({
    //         subAccountId: assembleSubAccountId(user0.address, 0, 1, true),
    //         rawAmount: toWei("500"),
    //         profitTokenId: 1,
    //         isProfit: true,
    //       })
    //       const orders = await orderBook.getOrders(0, 100)
    //       expect(orders.totalCount).to.equal(3)
    //       expect(orders.orderDataArray.length).to.equal(3)
    //       {
    //         const order2 = await orderBook.getOrder(2)
    //         expect(order2[0].payload).to.equal(orders.orderDataArray[2].payload)
    //       }
    //       {
    //         const orders3 = await orderBook.getOrdersOf(user0.address, 0, 100)
    //         expect(orders3.totalCount).to.equal(3)
    //         expect(orders3.orderDataArray.length).to.equal(3)
    //         expect(orders3.orderDataArray[2].payload).to.equal(orders.orderDataArray[2].payload)
    //       }
    //       expect(orders.orderDataArray[2].orderType).to.equal(OrderType.Withdrawal)
    //       const order = parseWithdrawalOrder(orders.orderDataArray[2].payload)
    //       expect(order.subAccountId).to.equal(assembleSubAccountId(user0.address, 0, 1, true))
    //       expect(order.rawAmount).to.equal(toWei("500"))
    //       expect(order.profitTokenId).to.equal(1)
    //       expect(order.isProfit).to.equal(true)
    //     }
  })

  it("lotSize", async () => {
    await expect(
      orderBook.placePositionOrder(
        {
          marketId: mid0,
          positionId: encodePositionId(user0.address, 0),
          size: toWei("0.05"),
          flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
          limitPrice: toWei("3000"),
          tpPrice: toWei("4000"),
          slPrice: toWei("2000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          profitToken: zeroAddress,
          tpslProfitToken: zeroAddress,
          collateralToken: zeroAddress,
          collateralAmount: toWei("0"),
          initialLeverage: toWei("10"),
        },
        refCode
      )
    ).to.revertedWith("lot size")
  })

  it("market should be exist", async () => {
    await expect(
      orderBook.placePositionOrder(
        {
          marketId: "0xabcd000000000000000000000000000000000000000000000000000000000000",
          positionId: encodePositionId(user0.address, 0),
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
          limitPrice: toWei("3000"),
          tpPrice: toWei("4000"),
          slPrice: toWei("2000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          profitToken: zeroAddress,
          tpslProfitToken: zeroAddress,
          collateralToken: zeroAddress,
          collateralAmount: toWei("0"),
          initialLeverage: toWei("10"),
        },
        refCode
      )
    ).to.revertedWith("marketId")
  })

  it("collateral should exist", async () => {
    await expect(
      orderBook.placePositionOrder(
        {
          marketId: mid0,
          positionId: encodePositionId(user0.address, 0),
          size: toWei("1"),
          flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
          limitPrice: toWei("3000"),
          tpPrice: toWei("4000"),
          slPrice: toWei("2000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          profitToken: zeroAddress,
          tpslProfitToken: zeroAddress,
          collateralToken: user0.address,
          collateralAmount: toWei("0"),
          initialLeverage: toWei("10"),
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

  it("placePositionOrder - open long position", async () => {
    await token0.mint(user0.address, toWei("1000"))
    await token0.transfer(orderBook.address, toWei("100"))
    // no1
    await time.increaseTo(timestampOfTest + 86400)
    {
      await orderBook.placePositionOrder(
        {
          marketId: mid0,
          positionId: encodePositionId(user0.address, 0),
          size: toWei("0.1"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("1000"),
          tpPrice: toWei("0"),
          slPrice: toWei("0"),
          expiration: timestampOfTest + 1000 + 86400,
          tpslExpiration: timestampOfTest + 1000 + 86400,
          profitToken: zeroAddress,
          tpslProfitToken: zeroAddress,
          collateralToken: token0.address,
          collateralAmount: toWei("100"),
          initialLeverage: toWei("10"),
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
          marketId: mid0,
          positionId: encodePositionId(user0.address, 0),
          size: toWei("0.1"),
          flags: PositionOrderFlags.OpenPosition,
          limitPrice: toWei("1000"),
          tpPrice: toWei("0"),
          slPrice: toWei("0"),
          expiration: timestampOfTest + 1000 + 86400,
          tpslExpiration: timestampOfTest + 1000 + 86400,
          profitToken: zeroAddress,
          tpslProfitToken: zeroAddress,
          collateralToken: token0.address,
          collateralAmount: toWei("100"),
          initialLeverage: toWei("10"),
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
      await orderBook.connect(broker).fillPositionOrder(1, [])
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
      await expect(
        orderBook.connect(broker).fillLiquidityOrder(1, [toWei("1"), toWei("2000"), toWei("1")])
      ).to.revertedWith("lock period")
      await time.increaseTo(timestampOfTest + 86400 + 60 * 20)
      await orderBook.connect(broker).fillLiquidityOrder(1, [toWei("1"), toWei("2000"), toWei("1")])
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
      await orderBook.connect(broker).fillLiquidityOrder(0, [toWei("1"), toWei("2000"), toWei("1")])
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
      await orderBook.connect(broker).fillLiquidityOrder(2, [toWei("1"), toWei("2000"), toWei("1")])
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(false)
      expect(await pool1.balanceOf(user0.address)).to.equal(toWei("1"))
      expect(await pool1.balanceOf(orderBook.address)).to.equal(toWei("1")) // because this test uses a mocked liquidity pool
      expect(await pool1.balanceOf(pool1.address)).to.equal(toWei("0"))
    }
  })

  it("TODO: broker can cancel orders", async () => {
    //     await ctk.approve(orderBook.address, toWei("1000000"))
    //     await ctk.mint(user0.address, toWei("1000"))
    //     // limit order
    //     await time.increaseTo(timestampOfTest + 86400 + 0)
    //     const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
    //     {
    //       await orderBook.placePositionOrder(
    //         {
    //           subAccountId,
    //           collateral: toWei("100"),
    //           size: toWei("0.1"),
    //           price: toWei("1000"),
    //           tpPrice: toWei("0"),
    //           slPrice: toWei("0"),
    //           expiration: timestampOfTest + 1000 + 86400,
    //           tpslExpiration: timestampOfTest + 1000 + 86400,
    //           profitTokenId: 0,
    //           tpslProfitTokenId: 0,
    //           flags: PositionOrderFlags.OpenPosition,
    //         },
    //         refCode
    //       )
    //       expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
    //       expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("100"))
    //       await time.increaseTo(timestampOfTest + 86400 + 86400 * 365 - 5)
    //       await expect(orderBook.connect(broker).cancelOrder(0)).revertedWith("EXP")
    //       await time.increaseTo(timestampOfTest + 86400 + 86400 * 365 + 5)
    //       await orderBook.connect(broker).cancelOrder(0)
    //       expect(await ctk.balanceOf(user0.address)).to.equal(toWei("1000"))
    //       expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
    //       {
    //         const orders = await orderBook.getOrders(0, 100)
    //         expect(orders.totalCount).to.equal(0)
    //         expect(orders.orderDataArray.length).to.equal(0)
    //       }
    //       const result = await orderBook.getOrder(0)
    //       expect(result[1]).to.equal(false)
    //     }
    //     // withdraw order
    //     {
    //       await orderBook.placeWithdrawalOrder({ subAccountId, rawAmount: toWei("500"), profitTokenId: 0, isProfit: true })
    //       await time.increaseTo(timestampOfTest + 86400 + 86400 * 365 + 5 + 120)
    //       await expect(orderBook.connect(broker).cancelOrder(1)).revertedWith("EXP")
    //       await time.increaseTo(timestampOfTest + 86400 + 86400 * 365 + 5 + 120 + 5)
    //       await orderBook.connect(broker).cancelOrder(1)
    //       {
    //         const orders = await orderBook.getOrders(0, 100)
    //         expect(orders.totalCount).to.equal(0)
    //         expect(orders.orderDataArray.length).to.equal(0)
    //       }
    //       const result = await orderBook.getOrder(0)
    //       expect(result[1]).to.equal(false)
    //     }
    //     // market order
    //     {
    //       await orderBook.placePositionOrder(
    //         {
    //           subAccountId,
    //           collateral: toWei("100"),
    //           size: toWei("0.1"),
    //           price: toWei("1000"),
    //           tpPrice: toWei("0"),
    //           slPrice: toWei("0"),
    //           expiration: timestampOfTest + 86400 + 86400 * 365 + 5 + 120 + 5 + 86400,
    //           tpslExpiration: timestampOfTest + 86400 + 86400 * 365 + 5 + 120 + 5 + 86400,
    //           profitTokenId: 0,
    //           tpslProfitTokenId: 0,
    //           flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
    //         },
    //         refCode
    //       )
    //       expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
    //       expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("100"))
    //       await time.increaseTo(timestampOfTest + 86400 + 86400 * 365 + 5 + 120 + 5 + 110)
    //       await expect(orderBook.connect(broker).cancelOrder(2)).revertedWith("EXP")
    //       await time.increaseTo(timestampOfTest + 86400 + 86400 * 365 + 5 + 120 + 5 + 130)
    //       await orderBook.connect(broker).cancelOrder(2)
    //       expect(await ctk.balanceOf(user0.address)).to.equal(toWei("1000"))
    //       expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
    //       {
    //         const orders = await orderBook.getOrders(0, 100)
    //         expect(orders.totalCount).to.equal(0)
    //         expect(orders.orderDataArray.length).to.equal(0)
    //       }
    //       const result = await orderBook.getOrder(0)
    //       expect(result[1]).to.equal(false)
    //     }
  })
})
