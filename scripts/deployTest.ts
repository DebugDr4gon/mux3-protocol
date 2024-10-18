import hre, { ethers } from "hardhat"
import { Deployer, DeploymentOptions } from "./deployer/deployer"
import { restorableEnviron } from "./deployer/environ"
import {
  ReferenceOracleType,
  encodePoolMarketKey,
  ensureFinished,
  toBytes32,
  toUnit,
  toWei,
  zeroAddress,
} from "./deployUtils"
import { CollateralPool, Delegator, FeeDistributor, Mux3, OrderBook } from "../typechain"

const ENV: DeploymentOptions = {
  network: hre.network.name,
  artifactDirectory: "./artifacts/contracts",
  addressOverride: {},
}

const a2b = (a) => {
  return a + "000000000000000000000000"
}
const u2b = (u) => {
  return ethers.utils.hexZeroPad(u.toTwos(256).toHexString(), 32)
}

const brokers = [
  "0x4A14ea8A87794157981303FA8aA317A8d6bc2612", // test net broker

  "0x49Db8818022EF28dbf57E0211628c454a50144ed", // mux broker
  "0xBc5bb8fe68eFBB9d5Bf6dEfAB3D8c01b5F36A80f", // mux broker
]

async function main(deployer: Deployer) {
  // deploy
  let proxyAdmin = deployer.addressOf("ProxyAdmin")
  let usdc = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
  let weth = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1"

  let poolImp = await deployer.deployOrSkip("CollateralPool", "CollateralPool__implementation")
  let core = (await deployer.deployUpgradeableOrSkip("Mux3", "Mux3", proxyAdmin)) as Mux3
  let orderBook = (await deployer.deployUpgradeableOrSkip("OrderBook", "OrderBook", proxyAdmin)) as OrderBook
  let delegator = (await deployer.deployUpgradeableOrSkip("Delegator", "Delegator", proxyAdmin)) as Delegator
  let feeDistributor = (await deployer.deployUpgradeableOrSkip(
    "FeeDistributor",
    "FeeDistributor",
    proxyAdmin
  )) as FeeDistributor

  // fee
  await feeDistributor.initialize(core.address)

  // core
  await core.initialize()
  await core.setCollateralPoolImplementation(poolImp.address)
  await core.grantRole(ethers.utils.id("ORDER_BOOK_ROLE"), orderBook.address)
  await core.setConfig(ethers.utils.id("MC_BORROWING_BASE_APY"), u2b(toWei("0.10")))
  await core.setConfig(ethers.utils.id("MC_BORROWING_INTERVAL"), u2b(ethers.BigNumber.from(3600)))
  await core.setConfig(ethers.utils.id("MC_FEE_DISTRIBUTOR"), a2b(feeDistributor.address))

  // collateral
  await core.addCollateralToken(usdc, 6)
  await core.setCollateralTokenStatus(usdc, true)
  await core.createCollateralPool("USDC0", "USDC0", usdc, 6)

  // pool 1
  const pool1Addr = (await core.listCollateralPool())[0]
  let pool1 = (await ethers.getContractAt("CollateralPool", pool1Addr)) as CollateralPool
  await pool1.setConfig(ethers.utils.id("MCP_SYMBOL"), ethers.utils.formatBytes32String("Test USDC Pool"))
  await pool1.setConfig(ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306")))
  await pool1.setConfig(ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938")))
  await pool1.setConfig(ethers.utils.id("MCP_IS_HIGH_PRIORITY"), u2b(toWei("0")))
  await pool1.setConfig(ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000")))
  await pool1.setConfig(ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001")))

  // markets
  const longEthMarketId = toBytes32("LongETH")
  await core.createMarket(longEthMarketId, "ETH_LONG", true, [pool1Addr])
  await core.setMarketConfig(longEthMarketId, ethers.utils.id("MM_POSITION_FEE_RATE"), u2b(toWei("0.0006")))
  await core.setMarketConfig(longEthMarketId, ethers.utils.id("MM_INITIAL_MARGIN_RATE"), u2b(toWei("0.006")))
  await core.setMarketConfig(longEthMarketId, ethers.utils.id("MM_MAINTENANCE_MARGIN_RATE"), u2b(toWei("0.005")))
  await core.setMarketConfig(longEthMarketId, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.001")))
  await core.setMarketConfig(longEthMarketId, ethers.utils.id("MM_MAX_INITIAL_LEVERAGE"), u2b(toWei("100")))
  await pool1.setConfig(encodePoolMarketKey("MCP_ADL_RESERVE_RATE", longEthMarketId), u2b(toWei("0.80")))
  await pool1.setConfig(encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", longEthMarketId), u2b(toWei("0.75")))
  await pool1.setConfig(encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", longEthMarketId), u2b(toWei("0.70")))

  const shortEthMarketId = toBytes32("ShortETH")
  await core.createMarket(shortEthMarketId, "ETH_SHORT", false, [pool1Addr])
  await core.setMarketConfig(shortEthMarketId, ethers.utils.id("MM_POSITION_FEE_RATE"), u2b(toWei("0.0006")))
  await core.setMarketConfig(shortEthMarketId, ethers.utils.id("MM_INITIAL_MARGIN_RATE"), u2b(toWei("0.006")))
  await core.setMarketConfig(shortEthMarketId, ethers.utils.id("MM_MAINTENANCE_MARGIN_RATE"), u2b(toWei("0.005")))
  await core.setMarketConfig(shortEthMarketId, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.001")))
  await core.setMarketConfig(shortEthMarketId, ethers.utils.id("MM_MAX_INITIAL_LEVERAGE"), u2b(toWei("100")))
  await pool1.setConfig(encodePoolMarketKey("MCP_ADL_RESERVE_RATE", shortEthMarketId), u2b(toWei("0.80")))
  await pool1.setConfig(encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", shortEthMarketId), u2b(toWei("0.75")))
  await pool1.setConfig(encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", shortEthMarketId), u2b(toWei("0.70")))

  // orderbook
  await orderBook.initialize(core.address, weth)
  for (const broker of brokers) {
    await orderBook.grantRole(ethers.utils.id("BROKER_ROLE"), broker)
  }
  await orderBook.setConfig(ethers.utils.id("MCO_LIQUIDITY_LOCK_PERIOD"), u2b(ethers.BigNumber.from(60 * 2))) // 60 * 15
  await orderBook.setConfig(ethers.utils.id("MCO_MARKET_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(60 * 2)))
  await orderBook.setConfig(ethers.utils.id("MCO_LIMIT_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(86400 * 30)))
  await orderBook.setConfig(ethers.utils.id("MCO_CANCEL_COOL_DOWN"), u2b(ethers.BigNumber.from(5)))
  await orderBook.grantRole(ethers.utils.id("DELEGATOR_ROLE"), delegator.address)

  // delegator
  await delegator.initialize(orderBook.address)

  // set price
  // await core.setMockPrice(longEthMarketId, toWei("3000"))
  // await core.setMockPrice(shortEthMarketId, toWei("3000"))
  // await core.setMockPrice(a2b(usdc), toWei("1"))
}

restorableEnviron(ENV, main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
