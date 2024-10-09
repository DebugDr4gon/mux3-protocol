import { ethers, network } from "hardhat"
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
} from "../scripts/deployUtils"

describe("TestOracle", () => {
  let tester: any
  let user0: any

  before(async () => {
    user0 = (await ethers.getSigners())[0]
  })

  beforeEach(async () => {
    tester = await createContract("TestOracle", [])
    await tester.setup()
  })

  after(async () => {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
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
    tester = await createContract("TestOracle", [])

    await hardhatSetArbERC20Balance("0xf97f4df75117a78c1a5a0dbb814af92458539fb4", tester.address, toWei("1000"))
    await tester.test_chainlinkStreamProvider()
  })

  it("test_muxPriceProvider", async () => {
    // const message = ethers.utils.keccak256(
    //   ethers.utils.solidityPack(
    //     ["uint256", "address", "uint256", "uint256", "uint256"],
    //     [31337, await tester.mpp(), 12, toWei("2000"), 12345678]
    //   )
    // )
    // const signature = await user0.signMessage(ethers.utils.arrayify(message))
    await tester.test_muxPriceProvider()
  })
})
