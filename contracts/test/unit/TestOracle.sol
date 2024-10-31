// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../orderbook/providers/ChainlinkStreamProvider.sol";
import "../../orderbook/providers/MuxPriceProvider.sol";
import "../../core/management/Pricing.sol";

import "../TestSuit.sol";
import "../SimplePriceProvider.sol";
import "../integration/MockChainlinkVerifier.sol";
import "../MockERC20.sol";

contract TestOracle is Pricing, TestSuit {
    address chainlinkVerifier = 0x478Aa2aC9F6D65F84e09D9185d126c3a17c2a93C;
    address chainlinkFeeToken = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;

    ChainlinkStreamProvider public csp;
    MuxPriceProvider public mpp;

    function setup() external {
        csp = new ChainlinkStreamProvider();
        mpp = new MuxPriceProvider();
    }

    function test_setPrice() external {
        SimplePriceProvider spp = new SimplePriceProvider();
        _oracleProviders[address(spp)] = true;

        bytes32 marketId0 = bytes32(uint256(0x1));
        bytes32 marketId1 = bytes32(uint256(0x2));

        _setPrice(marketId0, address(spp), abi.encode(uint256(100e18)));
        assertEq(_priceOf(marketId0), 100e18, "E01");

        _setPrice(marketId0, address(spp), abi.encode(uint256(125e18)));
        assertEq(_priceOf(marketId0), 125e18, "E02");

        _setPrice(marketId1, address(spp), abi.encode(uint256(2000e18)));
        assertEq(_priceOf(marketId1), 2000e18, "E01");

        _setPrice(marketId1, address(spp), abi.encode(uint256(2500e18)));
        assertEq(_priceOf(marketId0), 125e18, "E02");
        assertEq(_priceOf(marketId1), 2500e18, "E02");
    }

    function test_chainlinkStreamProvider() external {
        csp.initialize(chainlinkVerifier);
        assertEq(csp.chainlinkVerifier(), chainlinkVerifier, "E01");
        csp.setChainlinkVerifier(address(this));
        assertEq(csp.chainlinkVerifier(), address(this), "E02");
        csp.setChainlinkVerifier(chainlinkVerifier);

        csp.setPriceExpirationSeconds(86400);
        csp.setFeedId(
            bytes32(uint256(0x1)),
            bytes32(0x000362205e10b3a147d02792eccee483dca6c7b44ecce7012cb8c6e0b68b3ae9)
        );
        csp.setCallerWhitelist(address(this), true);
        IERC20(chainlinkFeeToken).transfer(address(csp), 10e18);

        (uint256 price, uint256 timestamp) = csp.getOraclePrice(
            bytes32(uint256(0x1)),
            hex"0006f100c86a0007ed73322d6e26606c9985fd511be9d92cf5af6b3dda8143c7000000000000000000000000000000000000000000000000000000001776b104000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000030001010100010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000362205e10b3a147d02792eccee483dca6c7b44ecce7012cb8c6e0b68b3ae90000000000000000000000000000000000000000000000000000000066f3ff850000000000000000000000000000000000000000000000000000000066f3ff8500000000000000000000000000000000000000000000000000006edc3ebcc3f0000000000000000000000000000000000000000000000000005c3fa829afad580000000000000000000000000000000000000000000000000000000066f5510500000000000000000000000000000000000000000000008e50f0a3b931bf000000000000000000000000000000000000000000000000008e4fea41ec43e37f8000000000000000000000000000000000000000000000008e52306fc7e5cfaf200000000000000000000000000000000000000000000000000000000000000006b95cb002271f070416f0883861bd78ec8366108fa1a1a3df22da1ff4719f0532747d1e6e2f91aa80ba2934b8ecde4cd36685f34ce8f9f034dba4a446f075dd2b833c1b0f3aa3b7ff736c0b0fff6801a9168ae37c9cde10656a7d77112c1822f0efa45d3aa16cc444ff3a3756589bbc9d5a6e26c285bea4475cd74fbada59dec044f6dae94269cd71cdb13c17663ff87d6aaf6a7c158f3058aaa4061a245b0cd9c56f1b9fedfba0a8ea408e3d089f566df109cf5f9594ec80a4769288da24a6b50000000000000000000000000000000000000000000000000000000000000006429df6834bec8448dec37e8f0601f4f3612c9ff11f4713cae0b3d69196a5960d48d9e4d8b3a003a193a5583fe2cad648e0bb0997b5eaf14a2c8b951b0d07fbaa15008825a8c6970e1491c6e9364572489eeff97bb314c6bad59d02dd92a72f7225954ee824a98357611f586a1a7aebc5256b614611e23cd7a7117fbad9053e470fc0604b18c1891acd60ee95fa75e7b138b04232c403bd0a50b772def8bfe4c9021eb9a5d4fed254a89d5d874314c71bc0e5008e029009561dd0f69bca1d3066"
        );
        assertEq(price, 2625270000000000000000, "E01");
        assertEq(timestamp, 1727266693, "E02");
    }

    function test_muxPriceProvider(address signer, bytes memory signature) external {
        mpp.initialize(signer); // signer

        MuxPriceProvider.OracleData memory data = MuxPriceProvider.OracleData({
            priceId: bytes32(uint256(0x1234)),
            sequence: 12,
            price: 2000e18,
            timestamp: 17295938660,
            signature: signature
        });
        (uint256 price, uint256 timestamp) = mpp.getOraclePrice(bytes32(uint256(0x1234)), abi.encode(data));
        assertEq(price, 2000e18, "E01");
        assertEq(timestamp, 17295938660, "E02");
    }

    function test_muxPriceProvider_error(address signer, bytes memory signature) external {
        mpp.initialize(signer); // signer
        MuxPriceProvider.OracleData memory data = MuxPriceProvider.OracleData({
            priceId: bytes32(uint256(0x1234)),
            sequence: 12,
            price: 2000e18,
            timestamp: 17295938660,
            signature: signature
        });
        mpp.getOraclePrice(bytes32(uint256(0x1234)), abi.encode(data));

        mpp.setOracleSigner(address(this));
        mpp.getOraclePrice(bytes32(uint256(0x1234)), abi.encode(data));
    }

    function test_mockChainlinkStreamProvider() external {
        MockERC20 feeToken = new MockERC20("Fee Token", "FT", 18);
        MockFeeManager feeManager = new MockFeeManager();
        feeManager.setFeeToken(address(feeToken));
        MockChainlinkVerifier mockVerifier = new MockChainlinkVerifier();
        mockVerifier.setFeeManager(address(feeManager));

        csp.initialize(address(mockVerifier));
        assertEq(csp.chainlinkVerifier(), address(mockVerifier), "E01");

        csp.setChainlinkVerifier(address(this));
        assertEq(csp.chainlinkVerifier(), address(this), "E02");
        csp.setCallerWhitelist(address(this), true);

        csp.setChainlinkVerifier(address(mockVerifier));
        csp.setPriceExpirationSeconds(86400);
        csp.setFeedId(bytes32(uint256(0x1)), bytes32(uint256(0x1234)));
        feeToken.mint(address(csp), 10e18);

        mockVerifier.setMockReport(bytes32(uint256(0x1234)), uint32(block.timestamp), uint32(block.timestamp), 1000e18);
        (uint256 price, uint256 timestamp) = csp.getOraclePrice(
            bytes32(uint256(0x1)),
            hex"0006f100c86a0007ed73322d6e26606c9985fd511be9d92cf5af6b3dda8143c7000000000000000000000000000000000000000000000000000000001776b104000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000030001010100010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000362205e10b3a147d02792eccee483dca6c7b44ecce7012cb8c6e0b68b3ae90000000000000000000000000000000000000000000000000000000066f3ff850000000000000000000000000000000000000000000000000000000066f3ff8500000000000000000000000000000000000000000000000000006edc3ebcc3f0000000000000000000000000000000000000000000000000005c3fa829afad580000000000000000000000000000000000000000000000000000000066f5510500000000000000000000000000000000000000000000008e50f0a3b931bf000000000000000000000000000000000000000000000000008e4fea41ec43e37f8000000000000000000000000000000000000000000000008e52306fc7e5cfaf200000000000000000000000000000000000000000000000000000000000000006b95cb002271f070416f0883861bd78ec8366108fa1a1a3df22da1ff4719f0532747d1e6e2f91aa80ba2934b8ecde4cd36685f34ce8f9f034dba4a446f075dd2b833c1b0f3aa3b7ff736c0b0fff6801a9168ae37c9cde10656a7d77112c1822f0efa45d3aa16cc444ff3a3756589bbc9d5a6e26c285bea4475cd74fbada59dec044f6dae94269cd71cdb13c17663ff87d6aaf6a7c158f3058aaa4061a245b0cd9c56f1b9fedfba0a8ea408e3d089f566df109cf5f9594ec80a4769288da24a6b50000000000000000000000000000000000000000000000000000000000000006429df6834bec8448dec37e8f0601f4f3612c9ff11f4713cae0b3d69196a5960d48d9e4d8b3a003a193a5583fe2cad648e0bb0997b5eaf14a2c8b951b0d07fbaa15008825a8c6970e1491c6e9364572489eeff97bb314c6bad59d02dd92a72f7225954ee824a98357611f586a1a7aebc5256b614611e23cd7a7117fbad9053e470fc0604b18c1891acd60ee95fa75e7b138b04232c403bd0a50b772def8bfe4c9021eb9a5d4fed254a89d5d874314c71bc0e5008e029009561dd0f69bca1d3066"
        );
        assertEq(price, 1000e18, "E03");
        assertEq(timestamp, block.timestamp, "E04");
    }

    function test_mockChainlinkStreamProvider_error() external {
        MockERC20 feeToken = new MockERC20("Fee Token", "FT", 18);
        MockFeeManager feeManager = new MockFeeManager();
        feeManager.setFeeToken(address(feeToken));
        MockChainlinkVerifier mockVerifier = new MockChainlinkVerifier();
        mockVerifier.setFeeManager(address(feeManager));

        csp.initialize(address(mockVerifier));
        assertEq(csp.chainlinkVerifier(), address(mockVerifier), "E01");

        csp.setChainlinkVerifier(address(this));
        assertEq(csp.chainlinkVerifier(), address(this), "E02");

        csp.setChainlinkVerifier(address(mockVerifier));
        csp.setPriceExpirationSeconds(86400);
        csp.setFeedId(bytes32(uint256(0x1)), bytes32(uint256(0x1234)));
        feeToken.mint(address(csp), 10e18);

        mockVerifier.setMockReport(bytes32(uint256(0x1234)), uint32(block.timestamp), uint32(block.timestamp), 1000e18);
        (uint256 price, uint256 timestamp) = csp.getOraclePrice(
            bytes32(uint256(0x1)),
            hex"0006f100c86a0007ed73322d6e26606c9985fd511be9d92cf5af6b3dda8143c7000000000000000000000000000000000000000000000000000000001776b104000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000030001010100010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000362205e10b3a147d02792eccee483dca6c7b44ecce7012cb8c6e0b68b3ae90000000000000000000000000000000000000000000000000000000066f3ff850000000000000000000000000000000000000000000000000000000066f3ff8500000000000000000000000000000000000000000000000000006edc3ebcc3f0000000000000000000000000000000000000000000000000005c3fa829afad580000000000000000000000000000000000000000000000000000000066f5510500000000000000000000000000000000000000000000008e50f0a3b931bf000000000000000000000000000000000000000000000000008e4fea41ec43e37f8000000000000000000000000000000000000000000000008e52306fc7e5cfaf200000000000000000000000000000000000000000000000000000000000000006b95cb002271f070416f0883861bd78ec8366108fa1a1a3df22da1ff4719f0532747d1e6e2f91aa80ba2934b8ecde4cd36685f34ce8f9f034dba4a446f075dd2b833c1b0f3aa3b7ff736c0b0fff6801a9168ae37c9cde10656a7d77112c1822f0efa45d3aa16cc444ff3a3756589bbc9d5a6e26c285bea4475cd74fbada59dec044f6dae94269cd71cdb13c17663ff87d6aaf6a7c158f3058aaa4061a245b0cd9c56f1b9fedfba0a8ea408e3d089f566df109cf5f9594ec80a4769288da24a6b50000000000000000000000000000000000000000000000000000000000000006429df6834bec8448dec37e8f0601f4f3612c9ff11f4713cae0b3d69196a5960d48d9e4d8b3a003a193a5583fe2cad648e0bb0997b5eaf14a2c8b951b0d07fbaa15008825a8c6970e1491c6e9364572489eeff97bb314c6bad59d02dd92a72f7225954ee824a98357611f586a1a7aebc5256b614611e23cd7a7117fbad9053e470fc0604b18c1891acd60ee95fa75e7b138b04232c403bd0a50b772def8bfe4c9021eb9a5d4fed254a89d5d874314c71bc0e5008e029009561dd0f69bca1d3066"
        );
    }
}
