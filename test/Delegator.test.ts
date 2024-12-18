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
} from "../scripts/deployUtils"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { CollateralPool, OrderBook, TestMux3, MockERC20, Delegator, WETH9 } from "../typechain"
import { time } from "@nomicfoundation/hardhat-network-helpers"
import { BigNumber } from "ethers"

const a2b = (a) => {
  return a + "000000000000000000000000"
}
const u2b = (u) => {
  return ethers.utils.hexZeroPad(u.toTwos(256).toHexString(), 32)
}

describe("Delegator", () => {
  const refCode = toBytes32("")
  const long1 = toBytes32("LongBTC")

  let usdc: MockERC20
  let weth: WETH9

  let admin: SignerWithAddress
  let trader1: SignerWithAddress
  let trader2: SignerWithAddress
  let trader3: SignerWithAddress

  let core: TestMux3
  let imp: CollateralPool
  let pool1: CollateralPool
  let orderBook: OrderBook
  let delegator: Delegator

  let timestampOfTest: number

  before(async () => {
    const accounts = await ethers.getSigners()
    admin = accounts[0]
    trader1 = accounts[1]
    trader2 = accounts[2]
    trader3 = accounts[3]
    weth = (await createContract("WETH9", [])) as WETH9
  })

  beforeEach(async () => {
    timestampOfTest = await time.latest()
    timestampOfTest = Math.ceil(timestampOfTest / 3600) * 3600 // move to the next hour

    // token
    usdc = (await createContract("MockERC20", ["USDC", "USDC", 6])) as MockERC20
    await usdc.mint(trader1.address, toUnit("100000", 6))

    // core
    core = (await createContract("TestMux3", [])) as TestMux3
    await core.initialize(weth.address)
    await core.addCollateralToken(usdc.address, 6)

    // orderBook
    const libOrderBook = await createContract("LibOrderBook")
    orderBook = (await createContract("OrderBook", [], {
      "contracts/libraries/LibOrderBook.sol:LibOrderBook": libOrderBook,
    })) as OrderBook
    await orderBook.initialize(core.address, weth.address)

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
    await core.createCollateralPool("TN1", "TS1", usdc.address, 0)
    const pool1Addr = (await core.listCollateralPool())[0]
    pool1 = (await ethers.getContractAt("CollateralPool", pool1Addr)) as CollateralPool

    // markets only uses pool1
    await core.createMarket(
      long1,
      "Long1",
      true, // isLong
      [pool1.address]
    )
    await core.setMarketConfig(long1, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.1")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_INITIAL_MARGIN_RATE"), u2b(toWei("0.006")))
    await core.setMarketConfig(long1, ethers.utils.id("MM_ORACLE_ID"), a2b(weth.address))
    await core.setMarketConfig(long1, ethers.utils.id("MM_OPEN_INTEREST_CAP_USD"), u2b(toWei("100000000")))

    // delegator
    delegator = (await createContract("Delegator", [])) as Delegator
    await delegator.initialize(orderBook.address)

    // role
    await orderBook.grantRole(ethers.utils.id("DELEGATOR_ROLE"), delegator.address)
    await core.grantRole(ethers.utils.id("ORDER_BOOK_ROLE"), orderBook.address)

    // prices
    await core.setMockPrice(a2b(weth.address), toWei("1000"))
    await core.setMockPrice(a2b(usdc.address), toWei("1"))
  })

  it("setDelegation, getDelegation", async () => {
    // set delegate
    await delegator.connect(trader1).delegate(trader2.address, 0, { value: toWei("1") })
    expect(await delegator.getDelegationByOwner(trader1.address)).to.deep.equal([trader2.address, toWei("0")])

    await delegator.connect(trader1).delegate(trader2.address, 100, { value: toWei("1") })
    expect(await delegator.getDelegationByOwner(trader1.address)).to.deep.equal([
      trader2.address,
      BigNumber.from("100"),
    ])

    await delegator.connect(trader1).delegate(trader3.address, 200, { value: toWei("1") })
    expect(await delegator.getDelegationByOwner(trader1.address)).to.deep.equal([
      trader3.address,
      BigNumber.from("200"),
    ])

    await delegator.connect(trader1).delegate(trader3.address, 0, { value: toWei("1") })
    expect(await delegator.getDelegationByOwner(trader1.address)).to.deep.equal([trader3.address, BigNumber.from("0")])
  })

  it("setInitialLeverage", async () => {
    await delegator.connect(trader1).delegate(trader2.address, 100, { value: toWei("1") })
    expect(await delegator.getDelegationByOwner(trader1.address)).to.deep.equal([
      trader2.address,
      BigNumber.from("100"),
    ])

    const positionId = encodePositionId(trader1.address, 0)
    await delegator.connect(trader2).setInitialLeverage(positionId, long1, toWei("20"))
    expect(await core.getInitialLeverage(positionId, long1)).to.equal(toWei("20"))
    expect(await delegator.getDelegationByOwner(trader1.address)).to.deep.equal([trader2.address, BigNumber.from("99")])
  })

  it("place, cancel", async () => {
    // set delegate
    const balance1 = await ethers.provider.getBalance(trader2.address)
    await delegator.connect(trader1).delegate(trader2.address, 0, { value: toWei("1") })
    const balance2 = await ethers.provider.getBalance(trader2.address)
    expect(balance2.sub(balance1)).to.equal(toWei("1"))

    // open short, using usdc
    const positionId = encodePositionId(trader1.address, 0)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    const args = {
      positionId,
      marketId: long1,
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
      tpslExpiration: 0,
      tpslFlags: 0,
      tpslWithdrawSwapToken: zeroAddress,
      tpslWithdrawSwapSlippage: toWei("0"),
    }
    {
      await expect(delegator.connect(trader3).placePositionOrder(args, refCode)).to.revertedWith("Not authorized")
      await expect(delegator.connect(trader2).placePositionOrder(args, refCode)).to.revertedWith("No action count")
      await delegator.connect(trader1).delegate(trader2.address, 100)
      await delegator.connect(trader2).setInitialLeverage(positionId, long1, toWei("100"))
      const tx1 = await delegator
        .connect(trader2)
        .multicall([
          (await delegator.populateTransaction.transferToken(trader1.address, usdc.address, toUnit("1000", 6))).data!,
          (await delegator.populateTransaction.placePositionOrder(args, refCode)).data!,
        ])
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 0, [
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
    }
    // cancel
    {
      await expect(delegator.connect(trader3).cancelOrder(0)).to.revertedWith("Not authorized")
      await delegator.connect(trader2).delegate(trader3.address, 100)
      await expect(delegator.connect(trader3).cancelOrder(0)).to.revertedWith("Not authorized")
      await expect(delegator.connect(trader2).cancelOrder(1)).to.revertedWith("No such orderId")
      await delegator.connect(trader2).cancelOrder(0)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("100000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
    }
  })

  it("deposit, withdraw", async () => {
    // set delegate
    const balance1 = await ethers.provider.getBalance(trader2.address)
    await delegator.connect(trader1).delegate(trader2.address, 0, { value: toWei("1") })
    const balance2 = await ethers.provider.getBalance(trader2.address)
    expect(balance2.sub(balance1)).to.equal(toWei("1"))

    const positionId = encodePositionId(trader1.address, 0)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    // deposit
    {
      await expect(
        delegator.connect(trader3).depositCollateral(positionId, usdc.address, toUnit("1000", 6))
      ).to.revertedWith("Not authorized")
      await expect(
        delegator.connect(trader2).depositCollateral(positionId, usdc.address, toUnit("1000", 6))
      ).to.revertedWith("No action count")
      await expect(
        delegator.connect(trader2).transferToken(trader1.address, usdc.address, toUnit("1000", 6))
      ).to.revertedWith("No action count")
      await delegator.connect(trader1).delegate(trader2.address, 100)
      const tx1 = await delegator
        .connect(trader2)
        .multicall([
          (await delegator.populateTransaction.transferToken(trader1.address, usdc.address, toUnit("1000", 6))).data!,
          (await delegator.populateTransaction.depositCollateral(positionId, usdc.address, toUnit("1000", 6))).data!,
        ])
      await expect(tx1).to.emit(core, "Deposit").withArgs(trader1.address, positionId, usdc.address, toUnit("1000", 6))
      await expect(tx1)
        .to.emit(core, "DepositWithdrawFinish")
        .withArgs(trader1.address, positionId, toWei("0"), [usdc.address], [toWei("1000")])
      expect(await usdc.balanceOf(core.address)).to.equal(toUnit("1000", 6))
      expect(await core.listAccountCollaterals(positionId)).to.deep.equal([[usdc.address, toUnit("1000", 18)]])
      expect(await delegator.getDelegationByOwner(trader1.address)).to.deep.equal([
        trader2.address,
        BigNumber.from("98"),
      ])
    }
    // withdraw
    {
      const tx1 = await delegator.connect(trader2).multicall([
        (
          await delegator.populateTransaction.placeWithdrawalOrder({
            positionId: positionId,
            tokenAddress: usdc.address,
            rawAmount: toUnit("500", 6),
            isUnwrapWeth: false,
            lastConsumedToken: zeroAddress,
            withdrawSwapToken: zeroAddress,
            withdrawSwapSlippage: toWei("0"),
          })
        ).data!,
      ])
      await expect(tx1)
        .to.emit(orderBook, "NewWithdrawalOrder")
        .withArgs(trader1.address, 0, [positionId, usdc.address, toUnit("500", 6), false])
      expect(await usdc.balanceOf(core.address)).to.equal(toUnit("1000", 6))
      expect(await core.listAccountCollaterals(positionId)).to.deep.equal([[usdc.address, toUnit("1000", 18)]])
      expect(await delegator.getDelegationByOwner(trader1.address)).to.deep.equal([
        trader2.address,
        BigNumber.from("97"),
      ])
    }
  })
})
