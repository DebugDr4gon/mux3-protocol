import { ethers } from "hardhat"
import { BytesLike } from "ethers"
import { ContractTransaction, Contract, ContractReceipt } from "ethers"
import { TransactionReceipt } from "@ethersproject/providers"
import { hexlify } from "@ethersproject/bytes"
import { BigNumber as EthersBigNumber, BigNumberish, parseFixed, formatFixed } from "@ethersproject/bignumber"
import chalk from "chalk"

export const zeroBytes32 = ethers.constants.HashZero
export const zeroAddress = ethers.constants.AddressZero

export enum OrderType {
  Invalid, // 0
  Position, // 1
  Liquidity, // 2
  Withdrawal, // 3
  Rebalance, // 4
  Adl, // 5
  Liquidate, // 6
}

export enum PositionOrderFlags {
  OpenPosition = 0x80, // this flag means open-position; otherwise close-position
  MarketOrder = 0x40, // this flag only affects order expire time and shows a better effect on UI
  WithdrawAllIfEmpty = 0x20, // this flag means auto withdraw all collateral if position.size == 0
  TriggerOrder = 0x10, // this flag means this is a trigger order (ex: stop-loss order). otherwise this is a limit order (ex: take-profit order)
  AutoDeleverage = 0x02, // denotes that this order is an auto-deleverage order
  UnwrapEth = 0x100, // unwrap WETH into ETH. only valid when fill close-position, or cancel open-position, or fill liquidity, or cancel liquidity
  WithdrawProfit = 0x200, // withdraw profit - fee. only valid when fill close-position
}

export enum ReferenceOracleType {
  None,
  Chainlink,
}

export const FacetCutAction = {
  Add: 0,
  Replace: 1,
  Remove: 2,
}

export const ASSET_IS_STABLE = 0x00000000000001 // is a usdt, usdc, ...
export const ASSET_CAN_ADD_REMOVE_LIQUIDITY = 0x00000000000002 // can call addLiquidity and removeLiquidity with this token
export const ASSET_IS_TRADABLE = 0x00000000000100 // allowed to be assetId
export const ASSET_IS_OPENABLE = 0x00000000010000 // can open position
export const ASSET_IS_SHORTABLE = 0x00000001000000 // allow shorting this asset
export const ASSET_IS_ENABLED = 0x00010000000000 // allowed to be assetId and collateralId
export const ASSET_IS_STRICT_STABLE = 0x01000000000000 // assetPrice is always 1 unless volatility exceeds strictStableDeviation

// -1 => 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
// -0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff => 0xf000000000000000000000000000000000000000000000000000000000000001
export function int256ToBytes32(n: EthersBigNumber): string {
  const hex = n.toTwos(256).toHexString()
  return ethers.utils.hexZeroPad(hex, 32)
}

export function toWei(n: string): EthersBigNumber {
  return ethers.utils.parseEther(n)
}

export function fromWei(n: BigNumberish): string {
  return ethers.utils.formatEther(n)
}

export function toUnit(n: string, decimals: number): EthersBigNumber {
  return parseFixed(n, decimals)
}

export function fromUnit(n: BigNumberish, decimals: number): string {
  return formatFixed(n, decimals)
}

export function toBytes32(s: string): string {
  return ethers.utils.formatBytes32String(s)
}

export function fromBytes32(s: BytesLike): string {
  return ethers.utils.parseBytes32String(s)
}

export function toChainlink(n: string): EthersBigNumber {
  return toUnit(n, 8)
}

export function printInfo(...message: any[]) {
  console.log(chalk.yellow("INF "), ...message)
}

export function printError(...message: any[]) {
  console.log(chalk.red("ERR "), ...message)
}

export function hashString(x: string): Buffer {
  return hash(ethers.utils.toUtf8Bytes(x))
}

export function hash(x: BytesLike): Buffer {
  return Buffer.from(ethers.utils.keccak256(x).slice(2), "hex")
}

export async function createFactory(path: any, libraries: { [name: string]: { address: string } } = {}): Promise<any> {
  const parsed: { [name: string]: string } = {}
  for (var name in libraries) {
    parsed[name] = libraries[name].address
  }
  return await ethers.getContractFactory(path, { libraries: parsed })
}

export async function createContract(
  path: any,
  args: any = [],
  libraries: { [name: string]: { address: string } } = {}
): Promise<Contract> {
  const factory = await createFactory(path, libraries)
  return await factory.deploy(...args)
}

export function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export async function ensureFinished(
  transaction: Promise<Contract> | Promise<ContractTransaction>
): Promise<TransactionReceipt | ContractReceipt> {
  const result: Contract | ContractTransaction = await transaction
  let receipt: TransactionReceipt | ContractReceipt
  if ((result as Contract).deployTransaction) {
    receipt = await (result as Contract).deployTransaction.wait()
  } else {
    receipt = await result.wait()
  }
  if (receipt.status !== 1) {
    throw new Error(`receipt err: ${receipt.transactionHash}`)
  }
  return receipt
}

//  |----- 160 -----|------ 96 ------|
//  | user address  | position index |
export function encodePositionId(account: string, index: number | EthersBigNumber): string {
  return hexlify(ethers.utils.solidityPack(["address", "uint96"], [account, index]))
}

export function encodePoolMarketKey(prefix: string, marketId: string) {
  return ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(["bytes32", "bytes32"], [ethers.utils.id(prefix), marketId])
  )
}

export function getSelectors(contract: Contract): { [method: string]: string } {
  const selectors = {}
  for (const name in contract.interface.functions) {
    const signature = contract.interface.getSighash(contract.interface.functions[name])
    selectors[name] = signature
  }
  return selectors
}

export async function getMuxSignature(
  priceData: {
    oracleId: string
    chainid: number
    contractAddress: string
    seq: number
    price: number
    timestamp: number
  },
  signer: any
) {
  const message = ethers.utils.keccak256(
    ethers.utils.solidityPack(
      ["uint256", "uint256", "address", "uint256", "uint256", "uint256"],
      [
        priceData.oracleId,
        priceData.chainid,
        priceData.contractAddress,
        priceData.seq,
        priceData.price,
        priceData.timestamp,
      ]
    )
  )
  return await signer.signMessage(ethers.utils.arrayify(message))
}

export async function getMuxPriceData(
  priceData: {
    oracleId: string
    chainid: number
    contractAddress: string
    seq: number
    price: number
    timestamp: number
  },
  signer: any
) {
  const message = ethers.utils.keccak256(
    ethers.utils.solidityPack(
      ["uint256", "uint256", "address", "uint256", "uint256", "uint256"],
      [
        priceData.oracleId,
        priceData.chainid,
        priceData.contractAddress,
        priceData.seq,
        priceData.price,
        priceData.timestamp,
      ]
    )
  )
  const signature = await signer.signMessage(ethers.utils.arrayify(message))
  return ethers.utils.defaultAbiCoder.encode(
    ["(bytes32,uint256,uint256,uint256,bytes)"],
    [[priceData.oracleId, priceData.seq, priceData.price, priceData.timestamp, signature]]
  )
}

export function parsePositionOrder(orderData: string) {
  const [
    positionId,
    marketId,
    size,
    flags,
    limitPrice,
    expiration,
    lastConsumedToken,
    collateralToken,
    collateralAmount,
    withdrawUsd,
    withdrawSwapToken,
    withdrawSwapSlippage,
    tpPriceDiff,
    slPriceDiff,
    tpslExpiration,
    tpslFlags,
    tpslWithdrawSwapToken,
    tpslWithdrawSwapSlippage,
  ] = ethers.utils.defaultAbiCoder.decode(
    [
      "bytes32", // positionId
      "bytes32", // marketId
      "uint256", // size
      "uint256", // flags
      "uint256", // limitPrice
      "uint64", // expiration
      "address", // lastConsumedToken
      "address", // collateralToken
      "uint256", // collateralAmount
      "uint256", // withdrawUsd
      "address", // withdrawSwapToken
      "uint256", // withdrawSwapSlippage
      "uint256", // tpPriceDiff
      "uint256", // slPriceDiff
      "uint64", // tpslExpiration
      "uint256", // tpslFlags
      "address", // tpslWithdrawSwapToken
      "uint256", // tpslWithdrawSwapSlippage
    ],
    orderData
  )
  return {
    positionId,
    marketId,
    size,
    flags,
    limitPrice,
    expiration,
    lastConsumedToken,
    collateralToken,
    collateralAmount,
    withdrawUsd,
    withdrawSwapToken,
    withdrawSwapSlippage,
    tpPriceDiff,
    slPriceDiff,
    tpslExpiration,
    tpslFlags,
    tpslWithdrawSwapToken,
    tpslWithdrawSwapSlippage,
  }
}

export function parseLiquidityOrder(orderData: string) {
  const [poolAddress, rawAmount, isAdding, isUnwrapWeth] = ethers.utils.defaultAbiCoder.decode(
    [
      "address", // poolAddress
      "uint256", // rawAmount
      "bool", // isAdding
      "bool", // isUnwrapWeth
    ],
    orderData
  )
  return {
    poolAddress,
    rawAmount,
    isAdding,
    isUnwrapWeth,
  }
}

export function parseWithdrawalOrder(orderData: string) {
  const [
    positionId,
    tokenAddress,
    rawAmount,
    isUnwrapWeth,
    lastConsumedToken,
    withdrawSwapToken,
    withdrawSwapSlippage,
  ] = ethers.utils.defaultAbiCoder.decode(
    [
      "bytes32", // positionId
      "address", // tokenAddress
      "uint256", // rawAmount
      "bool", // isUnwrapWeth
      "address", // lastConsumedToken
      "address", // withdrawSwapToken
      "uint256", // withdrawSwapSlippage
    ],
    orderData
  )
  return {
    positionId,
    tokenAddress,
    rawAmount,
    isUnwrapWeth,
    lastConsumedToken,
    withdrawSwapToken,
    withdrawSwapSlippage,
  }
}

export async function hardhatSetArbERC20Balance(
  tokenAddress: BytesLike,
  account: BytesLike,
  balance: BigNumberish,
  balanceSlot: number = 51
) {
  let slot = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["address", "uint"], [account, balanceSlot]))
  // remove padding for JSON RPC. ex: 0x0dd9ff... => 0xdd9ff...
  while (slot.startsWith("0x0")) {
    slot = "0x" + slot.slice(3)
  }
  const val = ethers.utils.defaultAbiCoder.encode(["uint256"], [balance])
  await ethers.provider.send("hardhat_setStorageAt", [tokenAddress, slot, val])
}
