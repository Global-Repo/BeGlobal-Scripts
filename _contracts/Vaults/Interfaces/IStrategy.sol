// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IStrategy {
    function deposit(uint _amount) external;
    function depositAll() external;
    function withdraw(uint _amount) external;
    function withdrawAll() external;
    function withdrawUnderlying(uint _amount) external;
    function getReward() external;
    function harvest() external;

    function totalSupply() external view returns (uint);
    function balanceMC() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function sharesOf(address account) external view returns (uint);
    function principalOf(address account) external view returns (uint);
    function earned(address account) external view returns (uint);
    function withdrawableBalanceOf(address account) external view returns (uint);
    function priceShare() external view returns (uint);

    function depositedAt(address account) external view returns (uint);
    function rewardsToken() external view returns (address);

    event Deposited(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount, uint withdrawalFee);
    event ProfitPaid(address indexed user, uint amount);
    event Harvested(uint profit);
    event Recovered(address token, uint amount);
}