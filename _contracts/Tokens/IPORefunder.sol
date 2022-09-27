// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../Libraries/SafeBEP20.sol";
import "../Libraries/Math.sol";
import '../Modifiers/Ownable.sol';
import "./IPO.sol";
import "./IPancakeERC20.sol";

contract IPORefunder is Ownable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;
    using SafeMath for uint16;

    IPO public ipo;
    IPancakeERC20 public lp;

    event RefundedLPs(uint i, address indexed _user, uint GLOBALAmount);

    constructor(
        address _ipo,
        address _lp
    ) public {
        ipo = IPO(_ipo);
        lp = IPancakeERC20(_lp);
    }

    function recoverRewardTokens() external onlyOwner {
        lp.transfer(address(msg.sender), lp.balanceOf(address(this)));
    }

    function refund(uint firstUser, uint lastUser) public onlyOwner {
        uint lpToUser;
        address actualUser;
        for (uint i=firstUser; i <= lastUser; i++) {
            actualUser = ipo.addressList(i);
            (lpToUser,) = ipo.userInfo(actualUser);

            lp.transfer(actualUser,lpToUser);

            emit RefundedLPs(i,actualUser,lpToUser);
        }
    }

    function estimateTotalRefund(uint firstUser, uint lastUser) public view returns (uint) {
        uint lpToUser;
        uint totalLpToUser;
        address actualUser;
        for (uint i=firstUser; i <= lastUser; i++) {
            actualUser = ipo.addressList(i);
            (lpToUser,) = ipo.userInfo(actualUser);
            totalLpToUser=totalLpToUser.add(lpToUser);
        }
        return totalLpToUser;
    }
}