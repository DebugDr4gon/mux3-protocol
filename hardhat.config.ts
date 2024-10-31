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
        version: "0.8.28",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            details: {
              yulDetails: {
                // when release the product, use default optimizerSteps. only set optimizerSteps to "u" during development.
                // references
                // * hardhat doc: https://hardhat.org/hardhat-runner/docs/reference/solidity-support#support-for-ir-based-codegen
                // * optimizer steps: https://docs.soliditylang.org/en/v0.8.28/internals/optimizer.html#optimizer-steps
                // * default sequence: https://github.com/ethereum/solidity/blob/v0.8.28/libsolidity/interface/OptimiserSettings.h#L44-L62
                // optimizerSteps: "u",
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
