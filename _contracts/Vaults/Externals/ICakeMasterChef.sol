// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface ICakeMasterChef {
    function userInfo(uint _pid, address _account) view external returns(uint amount, uint rewardDebt);

    // Staking into CAKE pools (pid = 0)
    function enterStaking(uint256 _amount) external;
    function leaveStaking(uint256 _amount) external;

    // Staking other tokens or LP (pid != 0)
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
}