import { ethers } from "hardhat"
import { expect } from "chai"
import { createContract } from "../scripts/deployUtils"
import { TestMux3Roles } from "../typechain"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"

describe("LibMux3Roles", () => {
  let mock: TestMux3Roles
  let defaultAdmin: SignerWithAddress
  let authorized: SignerWithAddress
  let other: SignerWithAddress

  const DEFAULT_ADMIN_ROLE = "0x0000000000000000000000000000000000000000000000000000000000000000"
  const ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ROLE"))

  before(async () => {
    const accounts = await ethers.getSigners()
    defaultAdmin = accounts[0]
    authorized = accounts[1]
    other = accounts[2]
  })

  beforeEach(async () => {
    mock = (await createContract("TestMux3Roles")) as TestMux3Roles
  })

  it("deployer has default admin role", async function () {
    expect(await mock.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin.address)).to.be.true
    expect(await mock.hasRole(DEFAULT_ADMIN_ROLE, authorized.address)).to.be.false
    expect(await mock.getRoleMemberCount(DEFAULT_ADMIN_ROLE)).to.be.equal(1)
    expect(await mock.getRoleMember(DEFAULT_ADMIN_ROLE, 0)).to.be.equal(defaultAdmin.address)
  })

  describe("granting", function () {
    beforeEach(async function () {
      await expect(mock.grantRole(ROLE, authorized.address))
        .to.emit(mock, "RoleGranted")
        .withArgs(ROLE, authorized.address, defaultAdmin.address)
      expect(await mock.getRoleMemberCount(DEFAULT_ADMIN_ROLE)).to.be.equal(1)
      expect(await mock.getRoleMemberCount(ROLE)).to.be.equal(1)
      expect(await mock.getRoleMember(ROLE, 0)).to.be.equal(authorized.address)
    })

    it("non-admin cannot grant role to other accounts", async function () {
      await expect(mock.connect(other).grantRole(ROLE, authorized.address)).to.be.revertedWith("is missing role")
    })

    it("accounts can be granted a role multiple times", async function () {
      await mock.grantRole(ROLE, authorized.address)
      await mock.grantRole(ROLE, authorized.address)
      expect(await mock.getRoleMemberCount(ROLE)).to.be.equal(1)
      expect(await mock.getRoleMember(ROLE, 0)).to.be.equal(authorized.address)
    })
  })

  describe("revoking", function () {
    it("roles that are not had can be revoked", async function () {
      expect(await mock.hasRole(ROLE, authorized.address)).to.be.false

      await mock.revokeRole(ROLE, authorized.address)
    })

    describe("with granted role", function () {
      beforeEach(async function () {
        await mock.grantRole(ROLE, authorized.address)
      })

      it("admin can revoke role", async function () {
        await expect(mock.revokeRole(ROLE, authorized.address))
          .to.emit(mock, "RoleRevoked")
          .withArgs(ROLE, authorized.address, defaultAdmin.address)

        expect(await mock.hasRole(ROLE, authorized.address)).to.be.false

        expect(await mock.getRoleMemberCount(DEFAULT_ADMIN_ROLE)).to.be.equal(1)
        expect(await mock.getRoleMemberCount(ROLE)).to.be.equal(0)
      })

      it("non-admin cannot revoke role", async function () {
        await expect(mock.connect(authorized).revokeRole(ROLE, authorized.address)).to.be.revertedWith(
          "is missing role"
        )
        await expect(mock.connect(other).revokeRole(ROLE, authorized.address)).to.be.revertedWith("is missing role")
      })

      it("a role can be revoked multiple times", async function () {
        await mock.revokeRole(ROLE, authorized.address)
        await mock.revokeRole(ROLE, authorized.address)
        expect(await mock.getRoleMemberCount(ROLE)).to.be.equal(0)
      })
    })
  })
})
