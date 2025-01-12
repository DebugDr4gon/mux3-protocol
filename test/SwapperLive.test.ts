import { ethers, network } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { toWei, createContract, toUnit, hardhatSetArbERC20Balance } from "../scripts/deployUtils"
import { TestSwapper } from "../typechain"

describe("SwapperLive", () => {
  let user0: any
  let user1: any
  let user2: any

  const uni3Router = "0xE592427A0AEce92De3Edee1F18E0157C05861564"
  const uni3Quoter = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6"
  const balancer2Vault = "0xba12222222228d8ba445958a75a0704d566bf2c8"
  const UNI_FEE_030 = "000bb8"
  const UNI_FEE_005 = "0001f4"

  before(async () => {
    const signers = await ethers.getSigners()
    user0 = signers[0]
    user1 = signers[1]
    user2 = signers[2]
  })

  after(async () => {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })

  // it("uniswap3, live test", async () => {
  //   await network.provider.request({
  //     method: "hardhat_reset",
  //     params: [
  //       {
  //         forking: {
  //           jsonRpcUrl: "https://arb1.arbitrum.io/rpc",
  //           enabled: true,
  //           ignoreUnknownTxType: true, // added in our hardhat patch. see README.md
  //           blockNumber: 293909815,
  //         },
  //       },
  //     ],
  //   })

  //   // quote
  //   const tester = (await createContract("TestSwapper", [])) as TestSwapper
  //   const tokens = [
  //     "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f", // 0 wbtc
  //     "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", // 1 USDC
  //   ]
  //   const quote = await tester.callStatic.quoteUniswap3(
  //     uni3Quoter,
  //     tokens[0] + UNI_FEE_005 + tokens[1].slice(2),
  //     toUnit("1", 8)
  //   )
  //   // console.log("quote", quote)
  //   expect(quote.success).to.equal(true)
  //   expect(quote.amountOut).to.equal(toUnit("94254.137933", 6))

  //   // swap
  //   const wbtc = await ethers.getContractAt("MockERC20", tokens[0])
  //   const usdc = await ethers.getContractAt("MockERC20", tokens[1])
  //   await hardhatSetArbERC20Balance(
  //     tokens[0],
  //     tester.address,
  //     toUnit("1", 8) // amount in
  //   )
  //   expect(await wbtc.balanceOf(tester.address)).to.equal(toUnit("1", 8))
  //   expect(await usdc.balanceOf(tester.address)).to.equal(toUnit("0", 6))
  //   const tx2 = await tester.swapUniswap3(
  //     uni3Router,
  //     tokens[0] + UNI_FEE_005 + tokens[1].slice(2),
  //     tokens[0],
  //     tokens[1],
  //     toUnit("1", 8) // amount in
  //   )
  //   await expect(tx2)
  //     .to.emit(tester, "Uniswap3Call")
  //     .withArgs(tokens[0], tokens[1], toUnit("1", 8), toUnit("94254.137933", 6))
  // })

  // it("balancer2, live test", async () => {
  //   await network.provider.request({
  //     method: "hardhat_reset",
  //     params: [
  //       {
  //         forking: {
  //           jsonRpcUrl: "https://arb1.arbitrum.io/rpc",
  //           enabled: true,
  //           ignoreUnknownTxType: true, // added in our hardhat patch. see README.md
  //           blockNumber: 293909815,
  //         },
  //       },
  //     ],
  //   })

  //   // quote
  //   const tester = (await createContract("TestSwapper", [])) as TestSwapper
  //   const tokens = [
  //     "0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2", // 0 sUSDe
  //     "0xca5d8f8a8d49439357d3cf46ca2e720702f132b8", // 1 GYD
  //     "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", // 2 USDC
  //   ]
  //   const swaps = [
  //     {
  //       poolId: "0xdeeaf8b0a8cf26217261b813e085418c7dd8f1ee00020000000000000000058f",
  //       assetInIndex: 0,
  //       assetOutIndex: 1,
  //       amount: toWei("0"),
  //       userData: "0x",
  //     },
  //     {
  //       poolId: "0x1e713b6b93fc31e8f59de1f757043964d9ddc5fa0002000000000000000005c7",
  //       assetInIndex: 1,
  //       assetOutIndex: 2,
  //       amount: toWei("0"),
  //       userData: "0x",
  //     },
  //   ]
  //   const quote = await tester.callStatic.quoteBalancer2(
  //     balancer2Vault,
  //     tokens,
  //     swaps,
  //     toWei("1") // amount in
  //   )
  //   // console.log("quote", quote)
  //   expect(quote.success).to.equal(true)
  //   expect(quote.amountOut).to.equal(toUnit("1.139251", 6))

  //   // swap
  //   const sUSDe = await ethers.getContractAt("MockERC20", tokens[0])
  //   const usdc = await ethers.getContractAt("MockERC20", tokens[2])
  //   const sUSDeBalanceSlot = 5
  //   await hardhatSetArbERC20Balance(
  //     tokens[0],
  //     tester.address,
  //     toWei("1"), // amount in
  //     sUSDeBalanceSlot
  //   )
  //   expect(await sUSDe.balanceOf(tester.address)).to.equal(toWei("1"))
  //   expect(await usdc.balanceOf(tester.address)).to.equal(toUnit("0", 6))
  //   const tx2 = await tester.swapBalancer2(
  //     balancer2Vault,
  //     tokens,
  //     swaps,
  //     tokens[0],
  //     tokens[2],
  //     toWei("1") // amount in
  //   )
  //   await expect(tx2).to.emit(tester, "Balancer2Call").withArgs(tokens[0], tokens[2], toWei("1"), toUnit("1.139251", 6))
  // })

  // it("balancer2, insufficient liquidity, live test", async () => {
  //   await network.provider.request({
  //     method: "hardhat_reset",
  //     params: [
  //       {
  //         forking: {
  //           jsonRpcUrl: "https://arb1.arbitrum.io/rpc",
  //           enabled: true,
  //           ignoreUnknownTxType: true, // added in our hardhat patch. see README.md
  //           blockNumber: 293909815,
  //         },
  //       },
  //     ],
  //   })

  //   // quote
  //   const tester = (await createContract("TestSwapper", [])) as TestSwapper
  //   const tokens = [
  //     "0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2", // 0 sUSDe
  //     "0xca5d8f8a8d49439357d3cf46ca2e720702f132b8", // 1 GYD
  //     "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", // 2 USDC
  //   ]
  //   const swaps = [
  //     {
  //       poolId: "0xdeeaf8b0a8cf26217261b813e085418c7dd8f1ee00020000000000000000058f",
  //       assetInIndex: 0,
  //       assetOutIndex: 1,
  //       amount: toWei("0"),
  //       userData: "0x",
  //     },
  //     {
  //       poolId: "0x1e713b6b93fc31e8f59de1f757043964d9ddc5fa0002000000000000000005c7",
  //       assetInIndex: 1,
  //       assetOutIndex: 2,
  //       amount: toWei("0"),
  //       userData: "0x",
  //     },
  //   ]
  //   const quote = await tester.callStatic.quoteBalancer2(
  //     balancer2Vault,
  //     tokens,
  //     swaps,
  //     toWei("1000000000") // amount in
  //   )
  //   // console.log("quote", quote)
  //   expect(quote.success).to.equal(false)
  // })
})
