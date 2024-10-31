// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../MockERC20.sol";
import "../../core/management/FacetManagement.sol";
import "../../pool/CollateralPool.sol";
import "../TestSuit.sol";

contract TestMux3FacetBase is FacetManagement, TestSuit {
    address pool;

    function setup() external {
        ERC20 fakeCore = new MockERC20("fakeCore", "fakeCore", 18);
        ERC20 fakeBook = new MockERC20("fakeBook", "fakeBook", 18);
        pool = address(new CollateralPool(address(fakeCore), address(fakeBook)));
        _setImplementation(pool);
    }

    function test_isPoolExist() external {
        ERC20 fakeToken = new MockERC20("fakeToken", "fakeToken", 18);

        address poolAddress = _getPoolAddress("fakePool", "fakePool", address(fakeToken));
        assertEq(_isPoolExist(poolAddress), false, "E01");
        _createCollateralPool("fakePool", "fakePool", address(fakeToken));
        assertEq(_isPoolExist(poolAddress), true, "E02");
    }

    function test_isOracleProvider() external {
        address oracleProvider = address(this);
        assertEq(_isOracleProvider(oracleProvider), false, "E01");
        _setOracleProvider(oracleProvider, true);
        assertEq(_isOracleProvider(oracleProvider), true, "E02");
    }

    function test_collateralToWad() external {
        address token6 = address(new MockERC20("T6", "T6", 6));
        address token8 = address(new MockERC20("T8", "T8", 8));
        address token18 = address(new MockERC20("T18", "T18", 18));
        address token30 = address(new MockERC20("T30", "T30", 30));

        _addCollateralToken(token6, 6);
        _addCollateralToken(token8, 8);
        _addCollateralToken(token18, 18);
        _addCollateralToken(token30, 30);

        assertEq(_collateralToWad(token6, 1e6), 1e18, "E01");
        assertEq(_collateralToWad(token8, 1e8), 1e18, "E02");
        assertEq(_collateralToWad(token18, 1e18), 1e18, "E03");
        assertEq(_collateralToWad(token30, 1e30), 1e18, "E04");
    }

    function test_collateralToRaw() external {
        address token6 = address(new MockERC20("T6", "T6", 6));
        address token8 = address(new MockERC20("T8", "T8", 8));
        address token18 = address(new MockERC20("T18", "T18", 18));
        address token30 = address(new MockERC20("T30", "T30", 30));

        _addCollateralToken(token6, 6);
        _addCollateralToken(token8, 8);
        _addCollateralToken(token18, 18);
        _addCollateralToken(token30, 30);

        assertEq(_collateralToRaw(token6, 1e18), 1e6, "E01");
        assertEq(_collateralToRaw(token8, 1e18), 1e8, "E02");
        assertEq(_collateralToRaw(token18, 1e18), 1e18, "E03");
        assertEq(_collateralToRaw(token30, 1e18), 1e30, "E04");
    }
}
