// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./Modifiers/Ownable.sol";
import "./Helpers/IMinter.sol";
import './Tokens/IBEP20.sol';

contract MinterVested is Ownable {
    IMinter public minter;
    IBEP20 public global;

    constructor(address _minter,
                address _global
    ) public {
        minter = IMinter(_minter);
        global = IBEP20(_global);
    }

    function canMint() internal view returns (bool) {
        return address(minter) != address(0) && minter.isMinter(address(this));
    }

    function callMintNativeTokens(uint _quantityToMint, address userFor) external onlyOwner {
        require(canMint(), "This contract must have a minter defined");
        minter.mintNativeTokens(_quantityToMint, userFor);
        global.transfer(userFor, _quantityToMint);
    }
}