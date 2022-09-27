// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../Libraries/SafeBEP20.sol";
import "../Libraries/Math.sol";
import '../Modifiers/ReentrancyGuard.sol';
import '../Modifiers/DepositoryRestriction.sol';
import "../Modifiers/RewarderRestriction.sol";
import "../IGlobalMasterChef.sol";
import "./VaultLocked.sol";
import "./Interfaces/IDistributable.sol";

contract VaultVested is IDistributable, ReentrancyGuard, DepositoryRestriction, RewarderRestriction {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;
    using SafeMath for uint16;

    struct DepositInfo {
        uint amount;
        uint256 nextWithdraw;
    }

    mapping (address => DepositInfo[]) public depositInfo;

    IBEP20 public global;
    IBEP20 public bnb;
    IGlobalMasterChef public globalMasterChef;
    VaultLocked public vaultLocked;

    uint public constant DUST = 1000;
    uint256 public pid;

    uint public minTokenAmountToDistribute;
    uint public bnbBalance;

    address[] public users;
    mapping (address => uint) public bnbEarned;
    uint public totalSupply;

    struct PenaltyFees {
        uint16 fee;       // % to locked vault (in Global)
        uint256 interval; // Meanwhile, penalty fees will be apply (timestamp)
    }

    PenaltyFees public penaltyFees;

    event Deposited(address indexed _user, uint _amount);
    event Withdrawn(address indexed _user, uint _amount, uint _penaltyFees);
    event RewardPaid(address indexed _user, uint _amount);

    constructor(
        address _global,
        address _bnb,
        address _globalMasterChef,
        address _vaultLocked
    ) public {
        pid = 0;
        global = IBEP20(_global);
        bnb = IBEP20(_bnb);
        globalMasterChef = IGlobalMasterChef(_globalMasterChef);
        vaultLocked = VaultLocked(_vaultLocked);

        bnbBalance = 0;

        minTokenAmountToDistribute = 1e18; // 1 BEP20 Token

        penaltyFees.fee = 100; // 1%
        penaltyFees.interval = 99 days;

        _allowance(global, _globalMasterChef);
    }

    function triggerDistribute(uint _amount) external nonReentrant onlyRewarders override {
        bnbBalance = bnbBalance.add(_amount);

        _distribute();
    }

    function getUsersLength() public view returns (uint256) {
        return users.length;
    }

    function setMinTokenAmountToDistribute(uint _newAmount) external onlyOwner {
        require(_newAmount >= 0, "Min token amount to distribute must be greater than 0");
        minTokenAmountToDistribute = _newAmount;
    }

    function setPenaltyFees(uint16 _fee, uint _interval) external onlyOwner {
        penaltyFees.fee = _fee;
        penaltyFees.interval = _interval;
    }

    function balance() external view override returns (uint amount) {
        (amount,) = globalMasterChef.userInfo(pid, address(this));
    }

    function balanceOf(address _account) public view returns(uint) {
        if (totalSupply == 0) return 0;
        return amountOfUser(_account);
    }

    function earned(address _account) public view returns (uint) {
        if (amountOfUser(_account) > 0) {
            return bnbEarned[_account];
        } else {
            return 0;
        }
    }

    function stakingToken() external view returns (address) {
        return address(global);
    }

    function rewardsToken() external view returns (address) {
        return address(bnb);
    }

    function amountOfUser(address _user) public view returns (uint totalAmount)
    {
        totalAmount = 0;
        DepositInfo[] memory myDeposits =  depositInfo[_user];
        for(uint i=0; i < myDeposits.length; i++)
        {
            totalAmount=totalAmount.add(myDeposits[i].amount);
        }
    }

    // availableForWithdraw without fees
    function availableForWithdraw(uint256 _time, address _user) public view returns (uint totalAmount)
    {
        totalAmount = 0;
        DepositInfo[] memory myDeposits =  depositInfo[_user];
        for(uint i=0; i< myDeposits.length; i++)
        {
            if(myDeposits[i].nextWithdraw < _time)
            {
                totalAmount=totalAmount.add(myDeposits[i].amount);
            }
        }
    }

    // remove deposits with no fees
    function removeAvailableDeposits(address user) private
    {
        uint256 btimestamp = block.timestamp;

        while(depositInfo[user].length > 0 && depositInfo[user][0].nextWithdraw<btimestamp)
        {
            for (uint i = 0; i<depositInfo[user].length-1; i++)
            {
                depositInfo[user][i] = depositInfo[user][i+1];
            }
            depositInfo[user].pop();
        }
    }

    function removeAllDeposits(address user) private
    {
        delete depositInfo[user];
    }

    // Deposit globals.
    // Depository will deposit globals but the account tracking is for the user.
    function deposit(uint _amount, address _account) public onlyDepositories {
        bool userExists = false;
        global.safeTransferFrom(msg.sender, address(this), _amount);

        depositInfo[_account].push(DepositInfo({
            amount: _amount,
            nextWithdraw: block.timestamp.add(penaltyFees.interval)
        }));

        globalMasterChef.enterStaking(_amount);

        for (uint j = 0; j < users.length; j++) {
            if (users[j] == _account)
            {
                userExists = true;
                break;
            }
        }

        if (!userExists){
            users.push(_account);
        }

        totalSupply = totalSupply.add(_amount);

        if (earned(_account) == 0) {
            bnbEarned[_account] = 0;
        }

        emit Deposited(_account, _amount);
    }

    // Withdraw all
    function withdraw() external nonReentrant {
        uint amount = amountOfUser(msg.sender);
        uint amountWithoutFees = availableForWithdraw(block.timestamp, msg.sender);
        uint amountWithFees = amount.sub(amountWithoutFees);
        uint earnedAmount = earned(msg.sender);

        globalMasterChef.leaveStaking(amount);

        handlePenaltyFees(amountWithFees, amountWithoutFees);
        handleRewards(earnedAmount);

        totalSupply = totalSupply.sub(amount);
        removeAllDeposits(msg.sender);
        _deleteUser(msg.sender);
        delete bnbEarned[msg.sender];
    }

    // Withdraw the part without withdrawal fees.
    function withdrawWithoutFees() external nonReentrant {
        uint amountWithoutFees = availableForWithdraw(block.timestamp, msg.sender);
        require(amountWithoutFees > 0, "VaultVested: No tokens to withdraw without fees");
        uint earnedAmount = earned(msg.sender);

        globalMasterChef.leaveStaking(amountWithoutFees);

        handlePenaltyFees(0, amountWithoutFees);
        handleRewards(earnedAmount);

        totalSupply = totalSupply.sub(amountWithoutFees);
        removeAvailableDeposits(msg.sender);
        if (amountOfUser(msg.sender) == 0) {
            _deleteUser(msg.sender);
        }
        delete bnbEarned[msg.sender];
    }

    function getReward() external nonReentrant {
        uint earnedAmount = earned(msg.sender);

        handleRewards(earnedAmount);

        delete bnbEarned[msg.sender];
    }

    function handlePenaltyFees(uint _amountWithFees, uint _amountWithoutFees) private {
        uint totalPaidAmount = 0;
        uint totalFeesAmount = 0;

        // No penalty fees
        if (_amountWithoutFees > 0) {
            global.safeTransfer(msg.sender, _amountWithoutFees);

            totalPaidAmount = totalPaidAmount.add(_amountWithoutFees);
        }

        // Penalty fees
        if (_amountWithFees > 0) {
            uint amountToVaultLocked = _amountWithFees.mul(penaltyFees.fee).div(10000);
            uint amountToUser = _amountWithFees.sub(amountToVaultLocked);

            if (amountToVaultLocked < DUST) {
                amountToUser = amountToUser.add(amountToVaultLocked);
            } else {
                global.approve(address(vaultLocked), amountToVaultLocked);
                vaultLocked.depositRewards(amountToVaultLocked);
            }

            global.safeTransfer(msg.sender, amountToUser);

            totalPaidAmount = totalPaidAmount.add(amountToUser);
            totalFeesAmount = totalFeesAmount.add(amountToVaultLocked);
        }

        emit Withdrawn(msg.sender, totalPaidAmount, totalFeesAmount);
    }

    function handleRewards(uint _earned) private {
        if (_earned < DUST) {
            return; // No rewards
        }

        bnb.safeTransfer(msg.sender, _earned);

        emit RewardPaid(msg.sender, _earned);
    }

    function _allowance(IBEP20 _token, address _account) private {
        _token.safeApprove(_account, uint(0));
        _token.safeApprove(_account, uint(~0));
    }

    function _deleteUser(address _account) private {
        for (uint i = 0; i < users.length; i++) {
            if (users[i] == _account) {
                for (uint j = i; j<users.length-1; j++)
                {
                    users[j] = users[j+1];
                }
                users.pop();
            }
        }
    }

    function _distribute() private {
        uint bnbAmountToDistribute = bnbBalance;

        // Nothing to distribute.
        if (bnbAmountToDistribute < minTokenAmountToDistribute) {
            return;
        }

        // No users to distribute BNBs.
        if (users.length == 0) {
            return;
        }

        for (uint i = 0; i < users.length; i++) {
            uint userPercentage = amountOfUser(users[i]).mul(100).div(totalSupply);
            uint bnbToUser = bnbAmountToDistribute.mul(userPercentage).div(100);
            bnbBalance = bnbBalance.sub(bnbToUser);

            bnbEarned[users[i]] = bnbEarned[users[i]].add(bnbToUser);
        }

        emit Distributed(bnbAmountToDistribute.sub(bnbBalance));
    }
}