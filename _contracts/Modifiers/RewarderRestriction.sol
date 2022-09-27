// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import './Ownable.sol';

contract RewarderRestriction is Ownable {
    mapping (address => bool) rewarders;

    modifier onlyRewarders() {
        require(rewarders[msg.sender] == true, "Only rewarders can perform this action");
        _;
    }

    function setRewarder(address _rewarder, bool _canReward) external onlyOwner {
        if (_canReward) {
            rewarders[_rewarder] = _canReward;
        } else {
            delete rewarders[_rewarder];
        }
    }
}