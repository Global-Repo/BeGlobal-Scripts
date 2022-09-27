// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;


import "./Ownable.sol";
import '../Helpers/Context.sol';
import 'hardhat/console.sol';


/**
 * @title Trusted
 * @dev The Trusted contract has a whitelist of addresses, and provides basic authorization control functions.
 * @dev This simplifies the implementation of "user permissions".
 */
contract Trusted is Context, Ownable {
    mapping(address => bool) public whitelist;

    event WhitelistedAddressAdded(address addr);
    event WhitelistedAddressRemoved(address addr);

    /**
     * @dev Throws if called by any account that's not whitelisted.
     */
    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], 'You are not trusted: you are not in the whitelist');
        _;
    }

    /**
     * @dev Throws if called by any account that's not human.
     */
    modifier onlyHuman() {
        require(msg.sender == tx.origin && !isContract(msg.sender), 'You are not trusted: you are not human');
        _;
    }

    /**
     * @dev checks address extcodesize
     * @param account address
     * @return success true if the size is bigger than 0,
     * false if size is 0
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Throws if called by any account that's not whitelisted.
     */
    modifier onlyWhitelistedOrHuman() {
        require(whitelist[msg.sender] || (msg.sender == tx.origin && !isContract(msg.sender)), 'You are not trusted: you are not human and not in the whitelist');
        _;
    }

    /**
     * @dev add an address to the whitelist
     * @param addr address
     * @return success true if the address was added to the whitelist, false if the address was already in the whitelist
     */
    function isAddressWhitelisted(address addr) onlyOwner public view returns(bool success) {
        success = whitelist[addr];
    }

    /**
     * @dev add an address to the whitelist
     * @param addr address
     * @return success true if the address was added to the whitelist, false if the address was already in the whitelist
     */
    function addAddressToWhitelist(address addr) onlyOwner public returns(bool success) {
        if (!whitelist[addr]) {
            whitelist[addr] = true;
            emit WhitelistedAddressAdded(addr);
            success = true;
        }
    }

    /**
     * @dev add addresses to the whitelist
     * @param addrs addresses
     * @return success true if at least one address was added to the whitelist,
     * false if all addresses were already in the whitelist
     */
    function addAddressesToWhitelist(address[] calldata addrs) onlyOwner public returns(bool success) {
        for (uint256 i = 0; i < addrs.length; i++) {
            if (addAddressToWhitelist(addrs[i])) {
                success = true;
            }
        }
    }

    /**
     * @dev remove an address from the whitelist
     * @param addr address
     * @return success true if the address was removed from the whitelist,
     * false if the address wasn't in the whitelist in the first place
     */
    function removeAddressFromWhitelist(address addr) onlyOwner public returns(bool success) {
        if (whitelist[addr]) {
            whitelist[addr] = false;
            emit WhitelistedAddressRemoved(addr);
            success = true;
        }
    }

    /**
     * @dev remove addresses from the whitelist
     * @param addrs addresses
     * @return success true if at least one address was removed from the whitelist,
     * false if all addresses weren't in the whitelist in the first place
     */
    function removeAddressesFromWhitelist(address[] calldata addrs) onlyOwner public returns(bool success) {
        for (uint256 i = 0; i < addrs.length; i++) {
            if (removeAddressFromWhitelist(addrs[i])) {
                success = true;
            }
        }
    }

}