import hre, { ethers } from "hardhat"
import { Deployer } from "./deployer/deployer"
import { DiamondCutFacet } from "../typechain"
import { Contract } from "ethers"
import { FacetCutAction, ensureFinished, getSelectors, zeroAddress } from "./deployUtils"

export async function deployDiamondOrSkip(
  deployer: Deployer,
  alias: string,
  facets: { [facetName: string]: Contract },
  diamondInit: Contract
): Promise<Contract> {
  if (!(alias in deployer.deployedContracts)) {
    checkForDuplicatedFunction(deployer, alias, facets)
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
      init: diamondInit.address,
      initCalldata: diamondInit.interface.encodeFunctionData("init"),
    }
    console.log(
      "deploying diamond. save the following args to a file to verify the code:",
      JSON.stringify([initialCuts, initialCutArgs], null, 2)
    )
    await deployer.deploy("Diamond", alias, initialCuts, initialCutArgs)
    deployer.deployedContracts[alias].type = "diamond"
    deployer.deployedContracts[alias].facets = dump
  }
  return await deployer.getDeployedInterface("Diamond", alias)
}

export async function upgradeFacet(
  deployer: Deployer,
  alias: string,
  facetName: "facetManagement" | "facetReader" | "facetOpen" | "facetClose" | "facetPositionAccount",
  deployNewFacet: () => Promise<Contract>
) {
  console.log("=====================")
  console.log("upgrading", facetName)
  const pool = (await deployer.getDeployedInterface("DiamondCutFacet", alias)) as DiamondCutFacet

  // backup old signatures
  const old = deployer.deployedContracts[alias]
  if (!old || old.type !== "diamond" || !old.facets || !old.facets[facetName]) {
    throw new Error(alias + " not found")
  }
  const oldSelectors = [...old.facets[facetName].selectors]

  // deploy new
  const newFacet = await deployNewFacet()
  checkForDuplicatedFunction(deployer, alias, { [facetName]: newFacet })
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

export async function checkForDuplicatedFunction(
  deployer: Deployer,
  alias: string,
  newFacets: { [facetName: string]: Contract }
) {
  const all: { [selector: string]: string } = {}

  // load from deployer
  const oldRecords = deployer.deployedContracts[alias]
  if (oldRecords && oldRecords.facets) {
    for (const facetName in oldRecords.facets) {
      for (const selector of oldRecords.facets[facetName].selectors) {
        all[selector] = facetName
      }
    }
  }

  // check new
  for (const facetName in newFacets) {
    const selectors = Object.values(getSelectors(newFacets[facetName]))
    for (const selector of selectors) {
      if (all[selector] && all[selector] !== facetName) {
        throw new Error("selector " + selector + " in " + facetName + " was defined in " + all[selector])
      }
      all[selector] = facetName
    }
  }
}
