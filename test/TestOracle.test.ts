import { ethers, network } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { toWei, createContract, getMuxSignature, getMuxPriceData } from "../scripts/deployUtils"

describe("TestOracle", () => {
  let tester: any
  let forked = false

  beforeEach(async () => {
    tester = await createContract("TestOracle", [])
    await tester.setup()
  })

  after(async () => {
    if (forked) {
      await network.provider.request({
        method: "hardhat_reset",
        params: [],
      })
      forked = false
    }
  })

  async function hardhatSetArbERC20Balance(tokenAddress: any, account: any, balance: any) {
    const balanceSlot = 51
    let slot = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["address", "uint"], [account, balanceSlot]))
    // remove padding for JSON RPC. ex: 0x0dd9ff... => 0xdd9ff...
    while (slot.startsWith("0x0")) {
      slot = "0x" + slot.slice(3)
    }
    const val = ethers.utils.defaultAbiCoder.encode(["uint256"], [balance])
    await ethers.provider.send("hardhat_setStorageAt", [tokenAddress, slot, val])
  }

  it("test_setPrice", async () => {
    await tester.test_setPrice()
  })

  it("test_chainlinkStreamProvider", async () => {
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: "https://arb1.arbitrum.io/rpc",
            enabled: true,
            ignoreUnknownTxType: true, // added in our hardhat patch. see README.md
            blockNumber: 257199002,
          },
        },
      ],
    })
    forked = true

    tester = await createContract("TestOracle", [])
    await hardhatSetArbERC20Balance("0xf97f4df75117a78c1a5a0dbb814af92458539fb4", tester.address, toWei("1000"))
    await tester.setup()
    await tester.test_chainlinkStreamProvider()
  })

  it("test_mockChainlinkStreamProvider", async () => {
    await tester.test_mockChainlinkStreamProvider()
  })

  it("test_mockChainlinkStreamProvider_error", async () => {
    await expect(tester.test_mockChainlinkStreamProvider_error()).to.be.revertedWith("NotWhitelisted")
  })

  it("test_muxPriceProvider", async () => {
    const signer = await ethers.Wallet.createRandom()
    // const message = ethers.utils.keccak256(
    //   ethers.utils.solidityPack(
    //     ["uint256", "address", "uint256", "uint256", "uint256"],
    //     [31337, await tester.mpp(), 12, toWei("2000"), 12345678]
    //   )
    // )
    // const signature = await signer.signMessage(ethers.utils.arrayify(message))
    const signature = await getMuxSignature(
      { chainid: 31337, contractAddress: await tester.mpp(), seq: 12, price: toWei("2000"), timestamp: 17295938660 },
      signer
    )
    await tester.test_muxPriceProvider(signer.address, signature)
  })

  it("test_muxPriceProvider_error", async () => {
    const signer = await ethers.Wallet.createRandom()
    const signature = await getMuxSignature(
      { chainid: 31337, contractAddress: await tester.mpp(), seq: 12, price: toWei("2000"), timestamp: 17295938660 },
      signer
    )
    await expect(tester.test_muxPriceProvider_error(signer.address, signature)).to.be.revertedWith("InvalidSignature")
  })
})
