import { ethers, waffle } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { toWei, createContract, toUnit } from "../scripts/deployUtils"

describe("Swapper", () => {
  let user0: any
  let user1: any
  let user2: any

  let uniswap: any
  let swapper: any

  let usdc: any
  let weth: any
  let wbtc: any
  let arb: any

  const UNI_FEE_030 = "000bb8"
  const UNI_FEE_005 = "0001f4"

  before(async () => {
    const signers = await ethers.getSigners()
    user0 = signers[0]
    user1 = signers[1]
    user2 = signers[2]
  })

  beforeEach(async () => {
    usdc = await createContract("MockERC20", ["USDC", "USDC", 18])
    weth = await createContract("WETH9", [])
    wbtc = await createContract("MockERC20", ["WBTC", "WBTC", 18])
    arb = await createContract("MockERC20", ["ARB", "ARB", 18])

    uniswap = await createContract("MockUniswapV3", [usdc.address, weth.address, wbtc.address, arb.address])
    swapper = await createContract("Swapper", [])
    await swapper.initialize(weth.address, uniswap.address, uniswap.address)
  })

  it("swap usdc=>weth", async () => {
    await swapper.setSwapPath(weth.address, usdc.address, [weth.address + UNI_FEE_005 + usdc.address.slice(2)])
    await usdc.mint(uniswap.address, toWei("10000"))

    await weth.deposit({ value: toWei("1") })
    await weth.transfer(swapper.address, toWei("1"))
    expect(await weth.balanceOf(swapper.address)).to.equal(toWei("1"))
    expect(await usdc.balanceOf(user0.address)).to.equal(toWei("0"))

    await swapper.swapAndTransfer(weth.address, toWei("1"), usdc.address, toUnit("3000", 6), user0.address, false)
    expect(await weth.balanceOf(swapper.address)).to.equal(toWei("0"))
    expect(await usdc.balanceOf(user0.address)).to.equal(toUnit("3000", 6))
  })

  it("swap usdc=>weth", async () => {
    await swapper.setSwapPath(usdc.address, weth.address, [usdc.address + UNI_FEE_005 + weth.address.slice(2)])
    await weth.deposit({ value: toWei("2") })
    await weth.transfer(uniswap.address, toWei("2"))

    await usdc.mint(swapper.address, toUnit("6000", 6))
    expect(await weth.balanceOf(user1.address)).to.equal(toWei("0"))
    expect(await usdc.balanceOf(swapper.address)).to.equal(toUnit("6000", 6))

    await swapper.swapAndTransfer(usdc.address, toUnit("6000", 6), weth.address, toWei("2"), user1.address, false)
    expect(await usdc.balanceOf(swapper.address)).to.equal(toWei("0"))
    expect(await usdc.balanceOf(user1.address)).to.equal(toWei("0"))
    expect(await weth.balanceOf(user1.address)).to.equal(toWei("2"))
  })

  it("swap usdc=>weth unwrap", async () => {
    await swapper.setSwapPath(usdc.address, weth.address, [usdc.address + UNI_FEE_005 + weth.address.slice(2)])
    await weth.deposit({ value: toWei("2") })
    await weth.transfer(uniswap.address, toWei("2"))

    await usdc.mint(swapper.address, toUnit("6000", 6))
    expect(await weth.balanceOf(user0.address)).to.equal(toWei("0"))
    expect(await usdc.balanceOf(swapper.address)).to.equal(toUnit("6000", 6))

    const rawBalance = await waffle.provider.getBalance(user1.address)
    await swapper.swapAndTransfer(usdc.address, toUnit("6000", 6), weth.address, toWei("2"), user1.address, true)
    expect(await usdc.balanceOf(swapper.address)).to.equal(toWei("0"))
    expect(await waffle.provider.getBalance(user1.address)).to.equal(rawBalance.add(toWei("2")))
  })
})
