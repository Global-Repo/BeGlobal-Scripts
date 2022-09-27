// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../Libraries/SafeBEP20.sol";
import '../Modifiers/Ownable.sol';
import "./VaultLockedManual.sol";

contract VaultLockedManualWithdrawer is Ownable {
    using SafeBEP20 for IBEP20;

    IBEP20 public global;
    VaultLockedManual public vaultLockedManual;

    event DistributedWithdrawFees(address indexed _user, uint GLOBALAmount);

    constructor(
        address _global,
        address _vaultLockedManual
    ) public {
        vaultLockedManual = VaultLockedManual(_vaultLockedManual);
        global = IBEP20(_global);
    }

    function distributeWithdrawFees(uint firstUser, uint lastUser, uint amount) public onlyOwner {
        for (uint i=firstUser; i <= lastUser; i++) {
            global.transfer(vaultLockedManual.users(i),amount);
            emit DistributedWithdrawFees(vaultLockedManual.users(i),amount);
        }
    }
}