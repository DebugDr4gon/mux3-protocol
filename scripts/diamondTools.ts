import hre, { ethers } from "hardhat"
import { Deployer } from "./deployer/deployer"
import { DiamondCutFacet } from "../typechain"
import { Contract } from "ethers"
import { FacetCutAction, ensureFinished, getSelectors, zeroAddress } from "./deployUtils"

export async function deployDiamondOrSkip(deployer: Deployer, alias: string, facets: { [facetName: string]: Contract }): Promise<Contract> {
  if (!(alias in deployer.deployedContracts)) {
    const admin1 = (await deployer.e.getSigners())[0]
    const dump: { [facetName: string]: { address: string; selectors: string[] } } = {}
    const initialCuts: {
      facetAddress: string
      action: number
      functionSelectors: string[]
    }[] = []
    for (const facetName in facets) {
      const facet = facets[facetName]
      dump[facetName] = {
        address: facets[facetName].address,
        selectors: Object.values(getSelectors(facet)),
      }
      initialCuts.push({
        facetAddress: facet.address,
        action: FacetCutAction.Add,
        functionSelectors: Object.values(getSelectors(facet)),
      })
    }
    const initialCutArgs = {
      owner: admin1.address,
      init: ethers.constants.AddressZero,
      initCalldata: "0x",
    }
    await deployer.deploy("Diamond", alias, initialCuts, initialCutArgs)
    deployer.deployedContracts[alias].type = "diamond"
    deployer.deployedContracts[alias].facets = dump
  }
  return await deployer.getDeployedInterface("Diamond", alias)
}

export async function upgradeFacet(
  deployer: Deployer,
  alias: string,
  facetName: "adminFacet" | "accountFacet" | "getterFacet" | "liquidityFacet" | "tradeFacet",
  deployNewFacet: () => Promise<Contract>
) {
  console.log("=====================")
  console.log("upgrading", facetName)
  const admin1 = (await deployer.e.getSigners())[0]
  const pool = (await deployer.getDeployedInterface("DiamondCutFacet", alias)) as DiamondCutFacet

  // backup old signatures
  const old = deployer.deployedContracts[alias]
  if (!old || old.type !== "diamond" || !old.facets || !old.facets[facetName]) {
    throw new Error(alias + " not found")
  }
  const oldSelectors = [...old.facets[facetName].selectors]

  // deploy new
  const newFacet = await deployNewFacet()
  const ops = [
    {
      facetAddress: zeroAddress,
      action: FacetCutAction.Remove,
      functionSelectors: oldSelectors,
    },
    {
      facetAddress: newFacet.address,
      action: FacetCutAction.Add,
      functionSelectors: Object.values(getSelectors(newFacet)),
    },
  ]
  console.log("running", ops)
  await ensureFinished(pool.diamondCut(ops, zeroAddress, "0x"))

  // replace our records
  deployer.deployedContracts[alias].facets![facetName] = {
    address: newFacet.address,
    selectors: Object.values(getSelectors(newFacet)),
  }
}
