import { ethers, network } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import {
    toWei,
    createContract,
    OrderType,
    PositionOrderFlags,
    toBytes32,
    encodePositionId,
    toUnit,
    zeroAddress,
} from "../scripts/deployUtils"

describe("TestConfigMap", () => {
    let tester: any
    let user0: any

    before(async () => {
        user0 = (await ethers.getSigners())[0]

    })

    beforeEach(async () => {
        tester = await createContract("TestConfigMap", [])
    })


    it("test_set", async () => {
        await tester.test_setUint256()
    })

})
