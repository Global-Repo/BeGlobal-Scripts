// SPDX-License-Identifier: Unlicensed
pragma solidity >= 0.6.12;

import "../Modifiers/Ownable.sol";
import "../Libraries/SafeMath.sol";

contract SwapReward is Ownable
{
    using SafeMath for uint256;

    uint public constant DAYS = 30;

    mapping (address => uint[DAYS]) public swappedRegistry;
    mapping (address => bool) public usersMap;
    address[] public usersList;

    constructor() public {

    }

    function getUserData(address user) public view returns (uint[DAYS] memory) {
        return swappedRegistry[user];
    }

    function getUserData(address user, uint day) public view returns (uint) {
        return swappedRegistry[user][day];
    }

    function checkUser(address user) internal
    {
        if (usersMap[user] == false) {
            usersMap[user] = true;
            usersList.push(user);
        }
    }

    function deleteUser(address user) external onlyOwner
    {
        usersMap[user] = false;

        for (uint i = 0; i < usersList.length; i++) {
            if (usersList[i] == user) {
                usersList[i] = usersList[usersList.length-1];
                usersList.pop();
                break;
            }
        }
    }

    function RegisterUsers(uint day, address[] calldata users, uint[] calldata amounts) external onlyOwner
    {
        require(users.length == amounts.length, "Different sizes");
        for (uint256 i = 0; i < users.length; i++)
        {
            checkUser(users[i]);
            swappedRegistry[users[i]][day] = amounts[i];
        }
    }

    function UpdateUsers(uint day, address[] calldata users, uint[] calldata amounts) external onlyOwner
    {
        require(users.length == amounts.length, "Different sizes");
        for (uint256 i = 0; i < users.length; i++)
        {
            checkUser(users[i]);
            swappedRegistry[users[i]][day] = amounts[i].add(swappedRegistry[users[i]][day]);
        }
    }

    function RegisterUser(uint day, address user, uint amount) external onlyOwner
    {
        checkUser(user);
        swappedRegistry[user][day] = amount;
    }

    function UpdateUser(uint day, address user, uint amount) external onlyOwner
    {
        checkUser(user);
        swappedRegistry[user][day] = amount.add(swappedRegistry[user][day]);
    }

    function RegisterUser(address user, uint[] calldata amount) external onlyOwner
    {
        checkUser(user);
        for (uint256 i = 0; i < DAYS; i++)
        {
            swappedRegistry[user][i] = amount[i];
        }
    }

    function UpdateUser(address user, uint[] calldata amount) external onlyOwner
    {
        checkUser(user);
        for (uint256 i = 0; i < DAYS; i++)
        {
            swappedRegistry[user][i] = amount[i].add(swappedRegistry[user][i]);
        }
    }
}
