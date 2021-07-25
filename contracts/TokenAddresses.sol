// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

contract TokenAddresses {
    string public constant GLOBAL = "GLOBAL";
    string public constant CAKE = "CAKE";
    string public constant BNB = "BNB";
    string public constant BUSD = "BUSD";

    mapping (string => address) private tokens;

    function findByName(string memory _tokenName) external view returns (address) {
        require(tokens[_tokenName] != address(0), "Token does not exists.");
        return tokens[_tokenName];
    }

    function addToken(string memory _tokenName, address _tokenAddress) external {
        require(tokens[_tokenName] == address(0), "Token already exists.");
        tokens[_tokenName] = _tokenAddress;
    }
}