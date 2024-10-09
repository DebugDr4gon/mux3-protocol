import { ethers, network } from "hardhat"
import { expect } from "chai"
import {
  toWei,
  toUnit,
  fromUnit,
  fromWei,
  createContract,
  encodePositionId,
  encodeMux3Price,
  encodeMux3Prices,
} from "../scripts/deployUtils"
const U = ethers.utils
const B = ethers.BigNumber
import { TestCodec } from "../typechain"
import BigNumber from "bignumber.js"

describe("LibCodec", () => {
  let testCodec: TestCodec

  before(async () => {
    testCodec = (await createContract("TestCodec", [])) as TestCodec
  })

  it("decodePositionId", async () => {
    const t = "0xfEDcbA9876543210123456789AbCDefEDCba9876"
    const i = 0xff
    const positionId = encodePositionId(t, i)
    expect(positionId).to.equal("0xfedcba9876543210123456789abcdefedcba9876ff0000000000000000000000")
    const [t2, i2] = await testCodec.decodePositionId(positionId)
    expect(t2).to.equal(t)
    expect(i2).to.equal(i)
  })

  it("decodePrice", async () => {
    const expectedOracleId = 127
    const cases = [
      {
        price: "65432.1",
        encoded: 4279892977, // (127 << 25) + (17 << 20) + 654321
      },
      {
        price: "0.000000000000000001", // 1e-18
        encoded: 4261412865, // (127 << 25) + (0 << 20) + 1
      },
      {
        price: "9999990000000000000", // 999999e13
        encoded: 4294918719, // (127 << 25) + (31 << 20) + 999999
      },
      {
        price: "0",
        encoded: 4261412864, // (127 << 25) + (0 << 20) + 0
      },
    ]
    for (const c of cases) {
      const encoded = encodeMux3Price({ oracleId: expectedOracleId, price: new BigNumber(c.price) })
      expect(encoded).to.equal(c.encoded, `price=${c.price}`)
      const [oracleIndex, price] = await testCodec.decodePrice(encoded)
      expect(oracleIndex).to.equal(expectedOracleId, `price=${c.price}`)
      expect(price).to.equal(toWei(c.price), `price=${c.price}`)
    }
  })

  it("decodePriceBlocks", async () => {
    const blocks = encodeMux3Prices([
      { oracleId: 1, price: new BigNumber("1") },
      { oracleId: 2, price: new BigNumber("2") },
    ])
    // (1 << 25) + (13 << 20) + 100000
    // (2 << 25) + (13 << 20) + 200000
    expect(blocks[0]).to.equal("0x02d186a004d30d40000000000000000000000000000000000000000000000000")
    const { indexes, prices } = await testCodec.decodePriceBlocks(blocks)
    expect(indexes.length).to.equal(8)
    expect(indexes[0]).to.equal(1)
    expect(prices[0]).to.equal(toWei("1"))
    expect(indexes[1]).to.equal(2)
    expect(prices[1]).to.equal(toWei("2"))
    expect(indexes[2]).to.equal(0)
    expect(indexes[3]).to.equal(0)
    expect(indexes[4]).to.equal(0)
    expect(indexes[5]).to.equal(0)
    expect(indexes[6]).to.equal(0)
    expect(indexes[7]).to.equal(0)
  })

  it("decodePriceBlocks", async () => {
    const blocks = encodeMux3Prices([
      { oracleId: 1, price: new BigNumber("1") },
      { oracleId: 2, price: new BigNumber("2") },
      { oracleId: 3, price: new BigNumber("3") },
      { oracleId: 4, price: new BigNumber("4") },
      { oracleId: 5, price: new BigNumber("5") },
      { oracleId: 6, price: new BigNumber("6") },
      { oracleId: 7, price: new BigNumber("7") },
      { oracleId: 8, price: new BigNumber("8") },
      { oracleId: 9, price: new BigNumber("9") },
    ])
    // (1 << 25) + (13 << 20) + 100000
    // (2 << 25) + (13 << 20) + 200000
    expect(blocks[0]).to.equal("0x02d186a004d30d4006d493e008d61a800ad7a1200cd927c00edaae6010dc3500")
    expect(blocks[1]).to.equal("0x12ddbba000000000000000000000000000000000000000000000000000000000")
    const { indexes, prices } = await testCodec.decodePriceBlocks(blocks)
    expect(indexes.length).to.equal(16)
    expect(indexes[0]).to.equal(1)
    expect(prices[0]).to.equal(toWei("1"))
    expect(indexes[1]).to.equal(2)
    expect(prices[1]).to.equal(toWei("2"))
    expect(indexes[2]).to.equal(3)
    expect(prices[2]).to.equal(toWei("3"))
    expect(indexes[3]).to.equal(4)
    expect(prices[3]).to.equal(toWei("4"))
    expect(indexes[4]).to.equal(5)
    expect(prices[4]).to.equal(toWei("5"))
    expect(indexes[5]).to.equal(6)
    expect(prices[5]).to.equal(toWei("6"))
    expect(indexes[6]).to.equal(7)
    expect(prices[6]).to.equal(toWei("7"))
    expect(indexes[7]).to.equal(8)
    expect(prices[7]).to.equal(toWei("8"))
    expect(indexes[8]).to.equal(9)
    expect(prices[8]).to.equal(toWei("9"))
    expect(indexes[9]).to.equal(0)
    expect(indexes[10]).to.equal(0)
    expect(indexes[11]).to.equal(0)
    expect(indexes[12]).to.equal(0)
    expect(indexes[13]).to.equal(0)
    expect(indexes[14]).to.equal(0)
    expect(indexes[15]).to.equal(0)
  })
})
