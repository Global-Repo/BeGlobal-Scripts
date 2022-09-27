// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IMinter {
    function isMinter(address account) view external returns (bool);
    function setMinter(address minter, bool canMint) external;
    function mintNativeTokens(uint, address) external;
}