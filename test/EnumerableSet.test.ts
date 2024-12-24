import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { createContract } from "../scripts/deployUtils"
import { TestEnumerableSet } from "../typechain"

describe("TestEnumerableSet", () => {
  let test: TestEnumerableSet

  beforeEach(async () => {
    test = (await createContract("TestEnumerableSet")) as TestEnumerableSet
  })

  it("clearAllMethod1", async () => {
    // add
    await test.add(1)
    await test.add(2)
    {
      const ids = await test.dump()
      expect(ids.length).to.equal(2)
      expect(ids[0]).to.equal(1)
      expect(ids[1]).to.equal(2)
      expect(await test.contains(1)).to.be.true
      expect(await test.contains(2)).to.be.true
      expect(await test.contains(3)).to.be.false
    }
    // clear
    await test.clear()
    {
      const ids = await test.dump()
      expect(ids.length).to.equal(0)
      expect(await test.contains(1)).to.be.false
      expect(await test.contains(2)).to.be.false
      expect(await test.contains(3)).to.be.false
    }
    // add
    await test.add(3)
    await test.add(4)
    {
      const ids = await test.dump()
      expect(ids.length).to.equal(2)
      expect(ids[0]).to.equal(3)
      expect(ids[1]).to.equal(4)
      expect(await test.contains(1)).to.be.false
      expect(await test.contains(2)).to.be.false
      expect(await test.contains(3)).to.be.true
      expect(await test.contains(4)).to.be.true
    }
    // clear
    await test.clear()
    {
      const ids = await test.dump()
      expect(ids.length).to.equal(0)
      expect(await test.contains(1)).to.be.false
      expect(await test.contains(2)).to.be.false
      expect(await test.contains(3)).to.be.false
      expect(await test.contains(4)).to.be.false
    }
  })
})
