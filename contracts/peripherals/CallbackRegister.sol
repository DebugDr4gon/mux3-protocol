// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "../interfaces/ICallbackRegister.sol";

interface IMux3Tranche {
    function isProxy(address proxy) external view returns (bool);
}

contract CallbackRegister is Ownable2StepUpgradeable, ICallbackRegister {
    event SetMux3Tranche(address mux3Tranche);

    address public mux3Tranche;

    function initialize() external initializer {
        __Ownable2Step_init();
    }

    function isCallbackRegistered(address callback) external view returns (bool) {
        if (mux3Tranche != address(0) && IMux3Tranche(mux3Tranche).isProxy(callback)) {
            return true;
        }

        // add more projects here

        return false;
    }

    function setMux3Tranche(address _mux3Tranche) external onlyOwner {
        mux3Tranche = _mux3Tranche;
        emit SetMux3Tranche(_mux3Tranche);
    }
}
