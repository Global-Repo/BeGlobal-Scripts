// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

/*

import "../Tokens/BEP20.sol";
import "../Libraries/SafeMath.sol";
import "../Libraries/SafeBEP20.sol";
import "../IGlobalMasterChef.sol";

contract GlobalMasterChefMock {
    using SafeMath for uint256;
    using SafeBEP20 for BEP20;

    BEP20 private globalToken;

    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    mapping(address => UserInfo) private userInfoInternal;

    uint private defaultReward = 0;

    constructor(address _global) public {
        globalToken = BEP20(_global);
    }

    function userInfo(uint _pid, address _account) view external returns (uint amount, uint rewardDebt) {
        return (userInfoInternal[_account].amount, userInfoInternal[_account].rewardDebt);
    }

    function enterStaking(uint256 _amount) external {
        _enterStaking(_amount);
    }

    function leaveStaking(uint256 _amount) external {
        _leaveStaking(_amount);
    }

    function deposit(uint256 _pid, uint256 _amount) external {
        _enterStaking(_amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) external {
        _leaveStaking(_amount);
    }

    // Always 1 token of reward when stacking
    function _enterStaking(uint256 _amount) private {
        UserInfo storage user = userInfoInternal[msg.sender];

        globalToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.rewardDebt.add(defaultReward);
    }

    function _leaveStaking(uint256 _amount) private {
        UserInfo storage user = userInfoInternal[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        globalToken.safeTransfer(address(msg.sender), _amount.add(user.rewardDebt));

        user.rewardDebt = 0;
        user.amount = user.amount.sub(_amount);
    }
}
*/