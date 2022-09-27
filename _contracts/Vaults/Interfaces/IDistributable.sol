// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IDistributable {
    function triggerDistribute(uint _amount) external;
    function balance() external view returns (uint amount);
    event Distributed(uint _distributedAmount);
}