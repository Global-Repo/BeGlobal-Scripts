// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IBunnyPoolStrategy {
    function deposit(uint _amount) external;
    function withdraw(uint256 _amount) external;
    function getReward() external;
    function balanceOf(address account) external view returns (uint);
}
