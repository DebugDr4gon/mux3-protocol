import { task, subtask } from "hardhat/config"
import "@typechain/hardhat"
import "@nomiclabs/hardhat-ethers"
import "@nomiclabs/hardhat-waffle"
import "@nomicfoundation/hardhat-verify"
import { Deployer } from "./scripts/deployer/deployer"
import { retrieveLinkReferences } from "./scripts/deployer/linkReferenceParser"
import { config } from "dotenv"
import "solidity-coverage"
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names"

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    }
  },
  solidity: {
    compilers: [
      {
        // [hardhat docs](https://hardhat.org/hardhat-runner/docs/reference/solidity-support#support-for-ir-based-codegen)
        // says (since Oct, 2024) that if you use the viaIR option, we recommend you set the optimization step sequence to "u",
        // to make Hardhat work as well as possible
        version: "0.8.28",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            details: {
              yulDetails: {
                optimizerSteps: "u",
              },
            },
          },
          evmVersion: "cancun",
        },
      },
      {
        version: "0.8.19",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  mocha: {
    timeout: 3600000,
  },
  gasReporter: {
    currency: "ETH",
    gasPrice: 100,
  },
}
