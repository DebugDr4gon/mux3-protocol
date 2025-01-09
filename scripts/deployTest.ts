import hre, { ethers } from "hardhat"
import { Deployer, DeploymentOptions } from "./deployer/deployer"
import { restorableEnviron } from "./deployer/environ"
import { encodePoolMarketKey, toBytes32, toWei, ensureFinished } from "./deployUtils"
import {
  ChainlinkStreamProvider,
  CollateralPoolAumReader,
  CollateralPoolEventEmitter,
  Delegator,
  Mux3,
  Mux3FeeDistributor,
  OrderBook,
  SusdsOracleL2,
  Swapper,
} from "../typechain"
import { deployDiamondOrSkip } from "./diamondTools"

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

const mux3OracleSigner = "0x4A14ea8A87794157981303FA8aA317A8d6bc2612"

const muxReferralTiers = "0xef6868929C8FCf11996e621cfd1b89d3B3aa6Bda"

const muxReferralManager = "0xa68d96F26112377abdF3d6b9fcde9D54f2604C2a"

async function main(deployer: Deployer) {
  // deploy
  let proxyAdmin = deployer.addressOf("ProxyAdmin")
  let usdc = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
  let weth = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1"
  let wbtc = "0x2f2a2543b76a4166549f7aab2e75bef0aefc5b0f"
  const arb = "0x912ce59144191c1204e64559fe8253a0e49e6548"
  const susds = "0x688c202577670fa1ae186c433965d178f26347f9"
  const susdsOracleL1 = "0x437CEa956B415e97517020490205c07f4a845168"
  const susde = "0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2"

  const diamondInit = await deployer.deployOrSkip("DiamondInit", "DiamondInit")
  const facets = {
    // check https://louper.dev/diamond/ for the current cuts
    diamondCutFacet: await deployer.deployOrSkip("DiamondCutFacet", "DiamondCutFacet"),
    diamondLoupeFacet: await deployer.deployOrSkip("DiamondLoupeFacet", "DiamondLoupeFacet"),
    mux3OwnerFacet: await deployer.deployOrSkip("Mux3OwnerFacet", "Mux3OwnerFacet"),
    facetManagement: await deployer.deployOrSkip("FacetManagement", "FacetManagement"),
    facetReader: await deployer.deployOrSkip("FacetReader", "FacetReader"),
    facetOpen: await deployer.deployOrSkip("FacetOpen", "FacetOpen"),
    facetClose: await deployer.deployOrSkip("FacetClose", "FacetClose"),
    facetPositionAccount: await deployer.deployOrSkip("FacetPositionAccount", "FacetPositionAccount"),
  }
  await deployDiamondOrSkip(deployer, "Mux3", facets, diamondInit)
  const core = (await deployer.getDeployedInterface("Mux3", "Mux3")) as Mux3
  const orderBook = (await deployer.deployUpgradeableOrSkip("OrderBook", "OrderBook", proxyAdmin)) as OrderBook
  const delegator = (await deployer.deployUpgradeableOrSkip("Delegator", "Delegator", proxyAdmin)) as Delegator
  const feeDistributor = (await deployer.deployUpgradeableOrSkip(
    "Mux3FeeDistributor",
    "Mux3FeeDistributor",
    proxyAdmin
  )) as Mux3FeeDistributor
  const chainlinkStreamProvider = (await deployer.deployUpgradeableOrSkip(
    "ChainlinkStreamProvider",
    "ChainlinkStreamProvider",
    proxyAdmin
  )) as ChainlinkStreamProvider
  const collateralPoolEventEmitter = (await deployer.deployUpgradeableOrSkip(
    "CollateralPoolEventEmitter",
    "CollateralPoolEventEmitter",
    proxyAdmin
  )) as CollateralPoolEventEmitter
  const poolImp = await deployer.deployOrSkip(
    "CollateralPool",
    "CollateralPool__implementation",
    core.address,
    orderBook.address,
    weth,
    collateralPoolEventEmitter.address
  )
  const mux3PriceProvider = await deployer.deployUpgradeableOrSkip("MuxPriceProvider", "MuxPriceProvider", proxyAdmin)
  const testReferralManager = await deployer.deployUpgradeableOrSkip(
    "TestReferralManager",
    "TestReferralManager",
    proxyAdmin
  )
  const swapper = (await deployer.deployUpgradeableOrSkip("Swapper", "Swapper", proxyAdmin)) as Swapper
  const susdsOracleL2 = (await deployer.deployUpgradeableOrSkip(
    "SusdsOracleL2",
    "SusdsOracleL2",
    proxyAdmin
  )) as SusdsOracleL2
  const collateralPoolAumReader = (await deployer.deployUpgradeableOrSkip(
    "CollateralPoolAumReader",
    "CollateralPoolAumReader",
    proxyAdmin
  )) as CollateralPoolAumReader
  const lEthMarketId = toBytes32("LongETH")
  const sEthMarketId = toBytes32("ShortETH")
  const lBtcMarketId = toBytes32("LongBTC")
  const sBtcMarketId = toBytes32("ShortBTC")
  const lArbMarketId = toBytes32("LongARB")
  const sArbMarketId = toBytes32("ShortARB")

  // core
  await ensureFinished(core.initialize(weth))
  await ensureFinished(core.setCollateralPoolImplementation(poolImp.address))
  await ensureFinished(core.grantRole(ethers.utils.id("ORDER_BOOK_ROLE"), orderBook.address))
  await ensureFinished(core.setConfig(ethers.utils.id("MC_BORROWING_BASE_APY"), u2b(toWei("0.10"))))
  await ensureFinished(core.setConfig(ethers.utils.id("MC_BORROWING_INTERVAL"), u2b(ethers.BigNumber.from(3600))))
  await ensureFinished(core.setConfig(ethers.utils.id("MC_FEE_DISTRIBUTOR"), a2b(feeDistributor.address)))
  await ensureFinished(core.setConfig(ethers.utils.id("MC_SWAPPER"), a2b(swapper.address)))
  await ensureFinished(core.setConfig(ethers.utils.id("MC_STRICT_STABLE_DEVIATION"), u2b(toWei("0.003"))))

  // event emitter
  await ensureFinished(collateralPoolEventEmitter.initialize(core.address))

  // orderbook
  await ensureFinished(orderBook.initialize(core.address, weth))
  for (const broker of brokers) {
    await ensureFinished(orderBook.grantRole(ethers.utils.id("BROKER_ROLE"), broker))
  }
  await ensureFinished(
    orderBook.setConfig(ethers.utils.id("MCO_LIQUIDITY_LOCK_PERIOD"), u2b(ethers.BigNumber.from(60 * 2)))
  ) // 60 * 15
  await ensureFinished(orderBook.setConfig(ethers.utils.id("MCO_MIN_LIQUIDITY_ORDER_USD"), u2b(toWei("0.1"))))
  await ensureFinished(
    orderBook.setConfig(ethers.utils.id("MCO_MARKET_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(60 * 2)))
  )
  await ensureFinished(
    orderBook.setConfig(ethers.utils.id("MCO_LIMIT_ORDER_TIMEOUT"), u2b(ethers.BigNumber.from(86400 * 30)))
  )
  await ensureFinished(orderBook.setConfig(ethers.utils.id("MCO_CANCEL_COOL_DOWN"), u2b(ethers.BigNumber.from(5))))
  await ensureFinished(orderBook.setConfig(ethers.utils.id("MCO_REFERRAL_MANAGER"), a2b(testReferralManager.address))) // change me to muxReferralManager when release
  await ensureFinished(orderBook.grantRole(ethers.utils.id("DELEGATOR_ROLE"), delegator.address))
  await ensureFinished(
    orderBook.setConfig(ethers.utils.id("MCO_ORDER_GAS_FEE_GWEI"), u2b(ethers.BigNumber.from("5882")))
  ) // 0.02 / 3400 * 1e18 / 1e9

  // collateral
  await ensureFinished(core.addCollateralToken(usdc, 6, true))
  await ensureFinished(core.addCollateralToken(weth, 18, false))
  await ensureFinished(core.addCollateralToken(susds, 18, true))
  await ensureFinished(core.addCollateralToken(susde, 18, true))
  await ensureFinished(core.setStrictStableId(a2b(usdc), true))

  // pool 17: usdc (remove me!)
  await ensureFinished(core.createCollateralPool("MUX Elemental Pool 17", "MEP-17", usdc, 0))
  const pool17 = (await core.listCollateralPool())[0]
  console.log("pool17Addr", pool17)
  await ensureFinished(core.setPoolConfig(pool17, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306"))))
  await ensureFinished(core.setPoolConfig(pool17, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938"))))
  await ensureFinished(core.setPoolConfig(pool17, ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000"))))
  await ensureFinished(core.setPoolConfig(pool17, ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001"))))

  // pool 18: usdc (remove me!)
  await ensureFinished(core.createCollateralPool("MUX Elemental Pool 18", "MEP-18", usdc, 1))
  const pool18 = (await core.listCollateralPool())[1]
  console.log("pool18Addr", pool18)
  await ensureFinished(core.setPoolConfig(pool18, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306"))))
  await ensureFinished(core.setPoolConfig(pool18, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938"))))
  await ensureFinished(core.setPoolConfig(pool18, ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000"))))
  await ensureFinished(core.setPoolConfig(pool18, ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001"))))
  await ensureFinished(core.setPoolConfig(pool18, ethers.utils.id("MCP_IS_DRAINING"), u2b(ethers.BigNumber.from("0"))))

  // pool 3: weth (remove me!)
  await ensureFinished(core.createCollateralPool("MUX Elemental Pool 3", "MEP-3", weth, 2))
  const pool3 = (await core.listCollateralPool())[2]
  console.log("pool3Addr", pool3)
  await ensureFinished(core.setPoolConfig(pool3, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306"))))
  await ensureFinished(core.setPoolConfig(pool3, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938"))))
  await ensureFinished(core.setPoolConfig(pool3, ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000"))))
  await ensureFinished(core.setPoolConfig(pool3, ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001"))))

  // pool 7: susds, support eth
  await ensureFinished(core.createCollateralPool("MUX Elemental Pool 7", "MEP-7", susds, 3))
  const pool7 = (await core.listCollateralPool())[3]
  console.log("pool7Addr", pool7)
  await ensureFinished(core.setPoolConfig(pool7, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306"))))
  await ensureFinished(core.setPoolConfig(pool7, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938"))))
  await ensureFinished(core.setPoolConfig(pool7, ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000"))))
  await ensureFinished(core.setPoolConfig(pool7, ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001"))))
  await ensureFinished(core.setPoolConfig(pool7, ethers.utils.id("MCP_IS_DRAINING"), u2b(ethers.BigNumber.from("0"))))

  // pool 5: susds, support eth
  await ensureFinished(core.createCollateralPool("MUX Elemental Pool 5", "MEP-5", susde, 4))
  const pool5 = (await core.listCollateralPool())[4]
  console.log("pool5Addr", pool5)
  await ensureFinished(core.setPoolConfig(pool5, ethers.utils.id("MCP_BORROWING_K"), u2b(toWei("6.36306"))))
  await ensureFinished(core.setPoolConfig(pool5, ethers.utils.id("MCP_BORROWING_B"), u2b(toWei("-6.58938"))))
  await ensureFinished(core.setPoolConfig(pool5, ethers.utils.id("MCP_LIQUIDITY_CAP_USD"), u2b(toWei("1000000"))))
  await ensureFinished(core.setPoolConfig(pool5, ethers.utils.id("MCP_LIQUIDITY_FEE_RATE"), u2b(toWei("0.0001"))))

  // markets
  await ensureFinished(core.createMarket(lEthMarketId, "ETH", true, [pool17, pool18, pool3, pool7, pool5]))
  await ensureFinished(
    core.setMarketConfig(lEthMarketId, ethers.utils.id("MM_POSITION_FEE_RATE"), u2b(toWei("0.0006")))
  )
  await ensureFinished(
    core.setMarketConfig(lEthMarketId, ethers.utils.id("MM_LIQUIDATION_FEE_RATE"), u2b(toWei("0.0006")))
  )
  await ensureFinished(
    core.setMarketConfig(lEthMarketId, ethers.utils.id("MM_INITIAL_MARGIN_RATE"), u2b(toWei("0.006")))
  )
  await ensureFinished(
    core.setMarketConfig(lEthMarketId, ethers.utils.id("MM_MAINTENANCE_MARGIN_RATE"), u2b(toWei("0.005")))
  )
  await ensureFinished(core.setMarketConfig(lEthMarketId, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.001"))))
  await ensureFinished(core.setMarketConfig(lEthMarketId, ethers.utils.id("MM_ORACLE_ID"), a2b(weth)))
  await ensureFinished(
    core.setMarketConfig(lEthMarketId, ethers.utils.id("MM_OPEN_INTEREST_CAP_USD"), u2b(toWei("10000")))
  )
  for (const p of [pool17, pool18, pool3, pool7, pool5]) {
    await ensureFinished(
      core.setPoolConfig(p, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", lEthMarketId), u2b(toWei("0.80")))
    )
    await ensureFinished(
      core.setPoolConfig(p, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", lEthMarketId), u2b(toWei("0.75")))
    )
    await ensureFinished(
      core.setPoolConfig(p, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", lEthMarketId), u2b(toWei("0.70")))
    )
  }

  await ensureFinished(core.createMarket(sEthMarketId, "ETH", false, [pool17, pool18, pool3, pool7, pool5]))
  await ensureFinished(
    core.setMarketConfig(sEthMarketId, ethers.utils.id("MM_POSITION_FEE_RATE"), u2b(toWei("0.0006")))
  )
  await ensureFinished(
    core.setMarketConfig(sEthMarketId, ethers.utils.id("MM_LIQUIDATION_FEE_RATE"), u2b(toWei("0.0006")))
  )
  await ensureFinished(
    core.setMarketConfig(sEthMarketId, ethers.utils.id("MM_INITIAL_MARGIN_RATE"), u2b(toWei("0.006")))
  )
  await ensureFinished(
    core.setMarketConfig(sEthMarketId, ethers.utils.id("MM_MAINTENANCE_MARGIN_RATE"), u2b(toWei("0.005")))
  )
  await ensureFinished(core.setMarketConfig(sEthMarketId, ethers.utils.id("MM_LOT_SIZE"), u2b(toWei("0.001"))))
  await ensureFinished(core.setMarketConfig(sEthMarketId, ethers.utils.id("MM_ORACLE_ID"), a2b(weth)))
  await ensureFinished(
    core.setMarketConfig(sEthMarketId, ethers.utils.id("MM_OPEN_INTEREST_CAP_USD"), u2b(toWei("10000")))
  )
  for (const p of [pool17, pool18, pool3, pool7, pool5]) {
    await ensureFinished(
      core.setPoolConfig(p, encodePoolMarketKey("MCP_ADL_RESERVE_RATE", sEthMarketId), u2b(toWei("0.80")))
    )
    await ensureFinished(
      core.setPoolConfig(p, encodePoolMarketKey("MCP_ADL_TRIGGER_RATE", sEthMarketId), u2b(toWei("0.75")))
    )
    await ensureFinished(
      core.setPoolConfig(p, encodePoolMarketKey("MCP_ADL_MAX_PNL_RATE", sEthMarketId), u2b(toWei("0.70")))
    )
  }

  // periphery
  await ensureFinished(delegator.initialize(orderBook.address))
  await ensureFinished(
    feeDistributor.initialize(core.address, orderBook.address, muxReferralManager, muxReferralTiers, weth)
  )
  await ensureFinished(feeDistributor.setFeeRatio(toWei("0.85")))

  // oracle: chainlink stream provider
  await ensureFinished(core.setOracleProvider(chainlinkStreamProvider.address, true))
  await ensureFinished(chainlinkStreamProvider.initialize("0x478Aa2aC9F6D65F84e09D9185d126c3a17c2a93C"))
  await ensureFinished(chainlinkStreamProvider.setPriceExpirationSeconds(86400))
  await ensureFinished(chainlinkStreamProvider.setCallerWhitelist(core.address, true))
  await ensureFinished(
    chainlinkStreamProvider.setFeedId(a2b(weth), "0x000362205e10b3a147d02792eccee483dca6c7b44ecce7012cb8c6e0b68b3ae9")
  )
  await ensureFinished(
    chainlinkStreamProvider.setFeedId(a2b(wbtc), "0x00039d9e45394f473ab1f050a1b963e6b05351e52d71e507509ada0c95ed75b8")
  )

  // oracle: mux3 provider
  await ensureFinished(core.setOracleProvider(mux3PriceProvider.address, true))
  await ensureFinished(mux3PriceProvider.initialize())
  await ensureFinished(mux3PriceProvider.setPriceExpirationSeconds(86400))
  await ensureFinished(mux3PriceProvider.grantRole(ethers.utils.id("ORACLE_SIGNER"), mux3OracleSigner))

  // swapper
  const uniRouter = "0xE592427A0AEce92De3Edee1F18E0157C05861564"
  const uniQuoter = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6"
  await ensureFinished(swapper.initialize(weth, uniRouter, uniQuoter))
  const UNI_FEE_030 = "000bb8"
  const UNI_FEE_005 = "0001f4"
  await ensureFinished(
    swapper.setSwapPath(usdc, weth, [usdc + UNI_FEE_030 + weth.slice(2), usdc + UNI_FEE_005 + weth.slice(2)])
  )
  await ensureFinished(
    swapper.setSwapPath(weth, usdc, [weth + UNI_FEE_030 + usdc.slice(2), weth + UNI_FEE_005 + usdc.slice(2)])
  )

  // susds
  await ensureFinished(susdsOracleL2.initialize(susdsOracleL1))

  // aum reader
  // https://docs.chain.link/data-feeds/price-feeds/addresses/?network=arbitrum&amp%3Bpage=1&page=1
  await ensureFinished(collateralPoolAumReader.initialize())
  await ensureFinished(collateralPoolAumReader.setPriceExpiration(86400))
  await ensureFinished(
    collateralPoolAumReader.setMarketPriceProvider(lEthMarketId, "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612")
  )
  await ensureFinished(
    collateralPoolAumReader.setMarketPriceProvider(sEthMarketId, "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612")
  )
  await ensureFinished(
    collateralPoolAumReader.setTokenPriceProvider(weth, "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612")
  )
  await ensureFinished(
    collateralPoolAumReader.setMarketPriceProvider(lBtcMarketId, "0x6ce185860a4963106506C203335A2910413708e9")
  )
  await ensureFinished(
    collateralPoolAumReader.setMarketPriceProvider(sBtcMarketId, "0x6ce185860a4963106506C203335A2910413708e9")
  )
  await ensureFinished(
    collateralPoolAumReader.setTokenPriceProvider(wbtc, "0x6ce185860a4963106506C203335A2910413708e9")
  )
  await ensureFinished(
    collateralPoolAumReader.setTokenPriceProvider(usdc, "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3")
  )
  await ensureFinished(collateralPoolAumReader.setTokenPriceProvider(arb, "0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6"))
  await ensureFinished(collateralPoolAumReader.setTokenPriceProvider(susds, susdsOracleL2.address))
  await ensureFinished(
    collateralPoolAumReader.setTokenPriceProvider(susde, "0xf2215b9c35b1697B5f47e407c917a40D055E68d7")
  ) // https://data.chain.link/feeds/arbitrum/mainnet/susde-usd
}

restorableEnviron(ENV, main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
