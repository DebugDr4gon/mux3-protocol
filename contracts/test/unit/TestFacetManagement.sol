// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../../core/management/FacetManagement.sol";
import "../MockERC20.sol";

import "../TestSuit.sol";

contract TestFacetManagement is FacetManagement, TestSuit {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    ERC20 public d6;
    ERC20 public d18;

    function setup() external {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        d6 = new MockERC20("D6", "D6", 6);
        d18 = new MockERC20("D18", "D18", 18);
    }

    function test_CollateralManager_retrieveDecimals() external view {
        assertEq(_retrieveDecimals(address(d6), 6), 6, "E01");
        assertEq(_retrieveDecimals(address(d18), 18), 18, "E02");
        // token without decimals
        assertEq(_retrieveDecimals(address(this), 4), 4, "E03");
    }

    function test_CollateralManager_addCollateralToken() external {
        assertEq(_isCollateralExists(address(d6)), false, "E01");
        assertEq(_isCollateralEnabled(address(d6)), false, "E02");
        assertEq(_isCollateralExists(address(d18)), false, "E03");
        assertEq(_isCollateralEnabled(address(d18)), false, "E04");

        _addCollateralToken(address(d6), 6);
        assertEq(_isCollateralExists(address(d6)), true, "E05");
        assertEq(_isCollateralEnabled(address(d6)), true, "E06");
        assertEq(_isCollateralExists(address(d18)), false, "E07");
        assertEq(_isCollateralEnabled(address(d18)), false, "E08");

        _addCollateralToken(address(d18), 18);
        assertEq(_isCollateralExists(address(d6)), true, "E08");
        assertEq(_isCollateralEnabled(address(d6)), true, "E10");
        assertEq(_isCollateralExists(address(d18)), true, "E11");
        assertEq(_isCollateralEnabled(address(d18)), true, "E12");

        _setCollateralTokenEnabled(address(d6), false);
        assertEq(_isCollateralExists(address(d6)), true, "E13");
        assertEq(_isCollateralEnabled(address(d6)), false, "E14");

        _setCollateralTokenEnabled(address(d6), true);
        assertEq(_isCollateralExists(address(d6)), true, "E15");
        assertEq(_isCollateralEnabled(address(d6)), true, "E16");
    }

    function test_MarketManager_createMarket() external {
        address fakePool0 = address(new FakeCollateralPool());
        address fakePool1 = address(new FakeCollateralPool());
        address fakePool2 = address(new FakeCollateralPool());
        {
            // inject fake pools
            _collateralPoolList.add(fakePool0);
            _collateralPoolList.add(fakePool1);
            _collateralPoolList.add(fakePool2);
        }

        bytes32 marketId0 = bytes32(uint256(0x1));
        bytes32 marketId1 = bytes32(uint256(0x2));
        {
            assertEq(_isMarketExists(marketId0), false, "E01");
            address[] memory pools = new address[](2);
            pools[0] = fakePool0;
            pools[1] = fakePool1;
            _createMarket(marketId0, "M0", true);
            _appendBackedPoolsToMarket(marketId0, pools);
            assertEq(_isMarketExists(marketId0), true, "E02");
        }
        {
            assertEq(_isMarketExists(marketId1), false, "E03");
            address[] memory pools = new address[](2);
            pools[0] = fakePool1;
            pools[1] = fakePool2;
            _createMarket(marketId1, "M1", false);
            _appendBackedPoolsToMarket(marketId1, pools);
            assertEq(_isMarketExists(marketId1), true, "E04");
        }
        assertEq(_markets[marketId0].pools.length, 2, "E05");
        assertEq(_markets[marketId0].pools[0].backedPool, fakePool0, "E06");
        assertEq(_markets[marketId0].pools[1].backedPool, fakePool1, "E07");
        assertEq(_markets[marketId1].pools.length, 2, "E08");
        assertEq(_markets[marketId1].pools[0].backedPool, fakePool1, "E09");
        assertEq(_markets[marketId1].pools[1].backedPool, fakePool2, "E10");

        {
            bytes32[] memory markets = ICollateralPool(fakePool0).markets();
            assertEq(markets.length, 1, "E11");
            assertEq(markets[0], keccak256(abi.encode(marketId0, true)), "E12");
        }
        {
            bytes32[] memory markets = ICollateralPool(fakePool1).markets();
            assertEq(markets.length, 2, "E13");
            assertEq(markets[0], keccak256(abi.encode(marketId0, true)), "E14");
            assertEq(markets[1], keccak256(abi.encode(marketId1, false)), "E15");
        }
        {
            bytes32[] memory markets = ICollateralPool(fakePool2).markets();
            assertEq(markets.length, 1, "E16");
            assertEq(markets[0], keccak256(abi.encode(marketId1, false)), "E17");
        }
    }

    function test_MarketManager_setMarketConfig() external {
        bytes32 marketId0 = bytes32(uint256(0x1));
        bytes32 marketId1 = bytes32(uint256(0x2));

        _createMarket(marketId0, "M0", true);
        _createMarket(marketId1, "M1", false);

        assertEq(_marketPositionFeeRate(marketId0), 0, "E01");
        assertEq(_marketInitialMarginRate(marketId0), 0, "E02");
        assertEq(_marketMaintenanceMarginRate(marketId0), 0, "E03");
        assertEq(_marketLotSize(marketId0), 0, "E04");

        _setMarketConfig(marketId0, MM_POSITION_FEE_RATE, bytes32(uint256(5e15)));
        _setMarketConfig(marketId0, MM_INITIAL_MARGIN_RATE, bytes32(uint256(6e16)));
        _setMarketConfig(marketId0, MM_MAINTENANCE_MARGIN_RATE, bytes32(uint256(7e17)));
        _setMarketConfig(marketId0, MM_LOT_SIZE, bytes32(uint256(8e18)));

        assertEq(_marketPositionFeeRate(marketId0), 5e15, "E05");
        assertEq(_marketInitialMarginRate(marketId0), 6e16, "E06");
        assertEq(_marketMaintenanceMarginRate(marketId0), 7e17, "E07");
        assertEq(_marketLotSize(marketId0), 8e18, "E08");
    }
}

contract FakeCollateralPool {
    bytes32[] _markets;

    function markets() external view returns (bytes32[] memory) {
        return _markets;
    }

    function setMarket(bytes32 marketId, bool isLong) external {
        _markets.push(keccak256(abi.encode(marketId, isLong)));
    }
}
