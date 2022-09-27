// SPDX-License-Identifier: Unlicensed
import '../Helpers/Context.sol';

pragma solidity 0.6.12;
// 
/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (a dev) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the dev with powers account will be the one that deploys the contract. This
 * can later be changed with {transferDevPower}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyDevPower`, which can be applied to your functions to restrict their use to
 * the dev with powers.
 */
contract DevPower is Context {
    address public _devPower;

    event DevPowerTransferred(address indexed previousDevPower, address indexed newDevPower);

    /**
     * @dev Initializes the contract setting the deployer as the initial dev with powers.
     */
    constructor() internal {
        address msgSender = _msgSender();
        _devPower = msgSender;
        emit DevPowerTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current dev with powers.
     */
    function GetDevPowerAddress() public view returns (address) {
        return _devPower;
    }

    /**
     * @dev Throws if called by any account other than the dev with powers.
     */
    modifier onlyDevPower() {
        require(_devPower == _msgSender(), 'DevPower: caller is not the dev with powers');
        _;
    }

    /**
     * @dev Leaves the contract without dev with powers. It will not be possible to call
     * `onlyDevPower` functions anymore. Can only be called by the current dev with powers.
     *
     * NOTE: Renouncing to have a dev account with powers will leave the contract without a manager,
     * thereby removing any functionality that is only available to the dev with powers.
     */
    function renounceDevPower() public onlyDevPower {
        emit DevPowerTransferred(_devPower, address(0));
        _devPower = address(0);
    }

    /**
     * @dev Transfers dev powers of the contract to a new account (`newDevPower`).
     * Can only be called by the current dev with powers.
     */
    function transferDevPower(address newDevPower) public onlyDevPower {
        _transferDevPower(newDevPower);
    }

    /**
     * @dev Transfers DevPower of the contract to a new account (`newDevPower`).
     */
    function _transferDevPower(address newDevPower) internal {
        require(newDevPower != address(0), 'DevPower: new dev with powers is the zero address');
        emit DevPowerTransferred(_devPower, newDevPower);
        _devPower = newDevPower;
    }
}