import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { FacetMux3Owner, DiamondCutFacet, DiamondLoupeFacet, Diamond } from "../typechain"
import { createContract, createFactory, FacetCutAction, getSelectors, zeroAddress } from "../scripts/deployUtils"

describe("Delegator", () => {
  let admin1: SignerWithAddress
  let admin2: SignerWithAddress
  let admin3: SignerWithAddress

  let ownershipFacet: FacetMux3Owner
  let diamondCutFacet: DiamondCutFacet
  let diamondLoupeFacet: DiamondLoupeFacet
  let diamond: Diamond

  before(async () => {
    const accounts = await ethers.getSigners()
    admin1 = accounts[0]
    admin2 = accounts[1]
    admin3 = accounts[2]

    ownershipFacet = (await createContract("FacetMux3Owner")) as FacetMux3Owner
    diamondCutFacet = (await createContract("DiamondCutFacet")) as DiamondCutFacet
    diamondLoupeFacet = (await createContract("DiamondLoupeFacet")) as DiamondLoupeFacet
  })

  beforeEach(async () => {
    const initialCuts = [
      {
        facetAddress: diamondCutFacet.address,
        action: FacetCutAction.Add,
        functionSelectors: Object.values(getSelectors(diamondCutFacet)),
      },
      {
        facetAddress: diamondLoupeFacet.address,
        action: FacetCutAction.Add,
        functionSelectors: Object.values(getSelectors(diamondLoupeFacet)),
      },
      {
        facetAddress: ownershipFacet.address,
        action: FacetCutAction.Add,
        functionSelectors: Object.values(getSelectors(ownershipFacet)),
      },
    ]
    const initialCutArgs = {
      owner: admin1.address,
      init: zeroAddress,
      initCalldata: "0x",
    }
    diamond = (await createContract("Diamond", [initialCuts, initialCutArgs])) as Diamond
  })

  it("transferOwner", async () => {
    const diamondOwner = (await createFactory("FacetMux3Owner")).attach(diamond.address) as FacetMux3Owner

    expect(await diamondOwner.owner()).to.equal(admin1.address)
    await expect(diamondOwner.connect(admin2).transferOwnership(admin2.address)).to.be.revertedWith("NotContractOwner")
    await diamondOwner.transferOwnership(admin2.address)
    expect(await diamondOwner.owner()).to.equal(admin1.address)
    expect(await diamondOwner.pendingOwner()).to.equal(admin2.address)
    await diamondOwner.connect(admin2).acceptOwnership()
    expect(await diamondOwner.owner()).to.equal(admin2.address)
  })
})
