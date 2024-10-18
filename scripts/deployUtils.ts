import { ethers } from "hardhat"
import { BytesLike } from "ethers"
import { ContractTransaction, Contract, ContractReceipt } from "ethers"
import { TransactionReceipt } from "@ethersproject/providers"
import { hexlify, concat, zeroPad, arrayify } from "@ethersproject/bytes"
import { BigNumber as EthersBigNumber, BigNumberish, parseFixed, formatFixed } from "@ethersproject/bignumber"
import chalk from "chalk"
import { BigNumber } from "bignumber.js"

export const zeroBytes32 = ethers.constants.HashZero
export const zeroAddress = ethers.constants.AddressZero

export enum OrderType {
  Invalid,
  Position,
  Liquidity,
  Withdrawal,
}

export enum PositionOrderFlags {
  OpenPosition = 0x80, // this flag means openPosition; otherwise closePosition
  MarketOrder = 0x40, // this flag only affects order expire time and show a better effect on UI
  WithdrawAllIfEmpty = 0x20, // this flag means auto withdraw all collateral if position.size == 0
  TriggerOrder = 0x10, // this flag means this is a trigger order (ex: stop-loss order). otherwise this is a limit order (ex: take-profit order)
  TpSlStrategy = 0x08, // for open-position-order, this flag auto place take-profit and stop-loss orders when open-position-order fills.
  //                      for close-position-order, this flag means ignore limitPrice and profitTokenId, and use extra.tpPrice, extra.slPrice, extra.tpslProfitTokenId instead.
  ShouldReachMinProfit = 0x04, // this flag is used to ensure that either the minProfitTime is met or the minProfitRate ratio is reached when close a position. only available when minProfitTime > 0.
  AutoDeleverage = 0x02, // denotes that this order is an auto-deleverage order
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
export function int256ToBytes32(n: ethers.BigNumber): string {
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

//  |----- 160 -----|------ 8 -------|-- 88 --|
//  | user address  | position index | unused |
export function encodePositionId(account: string, index: number): string {
  return hexlify(concat([arrayify(account), [arrayify(EthersBigNumber.from(index))[0]], zeroPad([], 11)]))
}

export type Mux3Price = {
  oracleId: number
  price: BigNumber // human readable price
}

// |---- 7 ----|- 5 -|- 20 -|
// | oracle id | exp | mant |
export function encodeMux3Price(p: Mux3Price): number {
  if (p.oracleId <= 0 || p.oracleId > 127) {
    throw new Error(`invalid OracleID: ${p.oracleId}`)
  }
  const wad = p.price.shiftedBy(18)
  let exp = 0
  let mantissa = wad
  const maxMantissa = new BigNumber("1000000")
  while (mantissa.gte(maxMantissa)) {
    mantissa = mantissa.div(10)
    exp++
  }
  const minMantissa = new BigNumber("100000")
  while (mantissa.lt(minMantissa) && exp > 0) {
    mantissa = mantissa.times(10)
    exp--
  }
  if (exp > 31) {
    throw new Error(`price out of range: ${p.price.toFixed()}`)
  }
  mantissa = mantissa.dp(0, BigNumber.ROUND_DOWN)
  const bId = ethers.BigNumber.from(p.oracleId).shl(25)
  const bExp = ethers.BigNumber.from(exp).shl(20)
  const bMant = ethers.BigNumber.from(mantissa.toNumber())
  const encoded = bId.or(bExp).or(bMant)
  return encoded.toNumber()
}

// convert [
//   <price1>, <price2>, ... <price16>
// ] into [
//  0x<price1><price2>...<price8>,
//  0x<price9><price10>...<price16>
// ]
export function encodeMux3Prices(prices: Mux3Price[]): string[] {
  let uint32Array = prices.map((p) => {
    const encoded = encodeMux3Price(p)
    const padding = ethers.utils.hexZeroPad(ethers.utils.hexlify(encoded), 4)
    return padding
  })
  // convert uint32[] into uint256[]
  const uint256Array: string[] = []
  for (let i = 0; i < uint32Array.length; i += 8) {
    let uint256Hex = ethers.utils.hexConcat(uint32Array.slice(i, i + 8))
    uint256Hex = uint256Hex.padEnd(66, "0")
    uint256Array.push(uint256Hex)
  }
  return uint256Array
}

export function encodePoolMarketKey(prefix: string, marketId: string) {
  return ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(["bytes32", "bytes32"], [ethers.utils.id(prefix), marketId])
  )
}
