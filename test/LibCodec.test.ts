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
    expect(positionId).to.equal("0xfedcba9876543210123456789abcdefedcba98760000000000000000000000ff")
    expect(await testCodec.encodePositionId(t, i)).to.equal(positionId)
    const [t2, i2] = await testCodec.decodePositionId(positionId)
    expect(t2).to.equal(t)
    expect(i2).to.equal(i)
  })
})
