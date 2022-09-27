// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../Libraries/SafeBEP20.sol";
import "../Libraries/Math.sol";
import '../Modifiers/Ownable.sol';
import "./VaultLockedManual.sol";

contract VaultLockedManualRewarder is Ownable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;
    using SafeMath for uint16;

    IBEP20 public global;
    VaultLockedManual public vaultLockedManual;

    event DistributedREWARDS(uint i, address indexed _user, uint GLOBALAmount);

    constructor(
        address _global,
        address _vaultLockedManual
    ) public {
        vaultLockedManual = VaultLockedManual(_vaultLockedManual);
        global = IBEP20(_global);
    }

    function recoverRewardTokens() external onlyOwner {
        global.transfer(address(msg.sender), global.balanceOf(address(this)));
    }

    function distributeRewards(uint firstUser, uint lastUser, uint amount) public onlyOwner {
        address actualUser;
        uint globalToUser;
        for (uint i=firstUser; i <= lastUser; i++) {
            actualUser = vaultLockedManual.users(i);
            globalToUser = amount.mul(vaultLockedManual.amountOfUser(actualUser)).div(vaultLockedManual.totalSupply());

            global.transfer(actualUser,globalToUser);

            emit DistributedREWARDS(i,actualUser,globalToUser);
        }
    }
}