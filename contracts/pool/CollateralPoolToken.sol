// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract CollateralPoolToken is ERC20Upgradeable {
    mapping(address => bool) private _trustedSpender;

    bytes32[50] private _gaps;

    event UpdateTrustedSpender(address spender, bool trusted);

    function __CollateralPoolToken_init(
        string memory name,
        string memory symbol
    ) internal onlyInitializing {
        __ERC20_init(name, symbol);
    }

    function _setTrustedSpender(address spender, bool trusted) internal {
        _trustedSpender[spender] = trusted;
        emit UpdateTrustedSpender(spender, trusted);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual override {
        if (_trustedSpender[spender]) {
            return;
        }
        super._spendAllowance(owner, spender, amount);
    }
}
