// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.6.12;

/*

import "../Tokens/BEP20.sol";
import "../Libraries/SafeMath.sol";
import "../Libraries/SafeBEP20.sol";
import "../Vaults/Externals/IBunnyPoolStrategy.sol";

contract BunnyPoolMock is IBunnyPoolStrategy {
    using SafeMath for uint256;
    using SafeBEP20 for BEP20;

    BEP20 private bunnyToken;

    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    mapping(address => UserInfo) private userInfoInternal;

    uint private defaultReward = 1e18;

    constructor(address _bunny) public {
        bunnyToken = BEP20(_bunny);
    }

    function balanceOf(address _user) external view override returns (uint amount) {
        return userInfoInternal[_user].amount;
    }

    // Always 1 token of reward when stacking
    function deposit(uint _amount) external override {
        UserInfo storage user = userInfoInternal[msg.sender];

        bunnyToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.rewardDebt.add(defaultReward);
    }

    function withdraw(uint256 _amount) external override {
        UserInfo storage user = userInfoInternal[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        bunnyToken.mint(user.rewardDebt);
        bunnyToken.safeTransfer(address(msg.sender), _amount.add(user.rewardDebt));

        user.rewardDebt = 0;
        user.amount = user.amount.sub(_amount);
    }

    function getReward() external override {

    }
}
*/