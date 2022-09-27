// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import './Ownable.sol';

contract DepositoryRestriction is Ownable {
    mapping (address => bool) public depositories;

    modifier onlyDepositories() {
        require(depositories[msg.sender] == true, "Only depositories can perform this action");
        _;
    }

    function setDepositary(address _depository, bool _canDeposit) external onlyOwner {
        if (_canDeposit) {
            depositories[_depository] = _canDeposit;
        } else {
            delete depositories[_depository];
        }
    }
}