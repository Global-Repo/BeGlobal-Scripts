// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../Libraries/SafeBEP20.sol";
import "../Libraries/Math.sol";
import '../Modifiers/Ownable.sol';
import '../Modifiers/ReentrancyGuard.sol';
import "../Modifiers/DepositoryRestriction.sol";
import "../Modifiers/RewarderRestriction.sol";
import "../IGlobalMasterChef.sol";
import "./Interfaces/IDistributable.sol";

contract VaultLocked is IDistributable, Ownable, ReentrancyGuard, DepositoryRestriction, RewarderRestriction {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;
    using SafeMath for uint16;

    struct DepositInfo {
        uint amount;
        uint256 nextWithdraw;
    }

    mapping (address=>DepositInfo[]) public depositInfo;
    address[] public users;

    IBEP20 public global;
    IBEP20 public bnb;
    IGlobalMasterChef public globalMasterChef;

    uint public constant DUST = 1000;
    uint256 public constant LOCKUP = 1814400; //default lockup of 30 days

    uint256 public pid;
    uint public minTokenAmountToDistribute;
    uint public minGlobalAmountToDistribute;
    mapping (address => uint) public bnbEarned;
    mapping (address => uint) public globalEarned;
    uint public totalSupply;
    uint256 public lastRewardEvent;
    uint256 public rewardInterval;
    uint public bnbBalance;
    uint public globalBalance;
    uint public lastDistributedGLOBALAmount;
    uint public lastDistributedBNBAmount;

    event RewardsDeposited(address indexed _account, uint _amount);
    event Deposited(address indexed _user, uint _amount);
    event Withdrawn(address indexed _user, uint _amount);
    event RewardPaid(address indexed _user, uint _amount, uint _amount2);
    event DistributedGLOBAL(uint GLOBALAmount);

    constructor(
        address _global,
        address _bnb,
        address _globalMasterChef,
        uint256 _rewardInterval
    ) public {
        pid = 0;

        global = IBEP20(_global);
        bnb = IBEP20(_bnb);

        globalMasterChef = IGlobalMasterChef(_globalMasterChef);

        minTokenAmountToDistribute = 1e18; // 1 BEP20 Token
        minGlobalAmountToDistribute = 100e18; // 100 BEP20 Token

        bnbBalance = 0;
        globalBalance = 0;
        lastDistributedGLOBALAmount = 0;
        lastDistributedBNBAmount = 0;

        rewardInterval = _rewardInterval;

        lastRewardEvent = block.timestamp;
    }

    function setRewardInterval(uint256 _rewardInterval) external onlyOwner {
        rewardInterval = _rewardInterval;
    }

    function setMinTokenAmountToDistribute(uint _newAmount) external onlyOwner {
        require(_newAmount >= 0, "Min token amount to distribute must be greater than 0");
        minTokenAmountToDistribute = _newAmount;
    }

    function setMinGlobalAmountToDistribute(uint _minGlobalAmountToDistribute) external onlyOwner {
        minGlobalAmountToDistribute = _minGlobalAmountToDistribute;
    }

    function getDepositInfoLengthForAddress(address addr) public view returns (uint256) {
        return depositInfo[addr].length;
    }

    function triggerDistribute(uint _amount) external nonReentrant onlyRewarders override {
        bnbBalance = bnbBalance.add(_amount);

        _distributeBNB();
    }

    function balance() external view override returns (uint amount) {
        (amount,) = globalMasterChef.userInfo(pid, address(this));
    }

    function balanceOf(address _account) public view returns(uint) {
        if (totalSupply == 0) return 0;
        return amountOfUser(_account);
    }

    function bnbToEarn(address _account) public view returns (uint) {
        if (amountOfUser(_account) > 0) {
            return bnbEarned[_account];
        } else {
            return 0;
        }
    }

    function globalToEarn(address _account) public view returns (uint) {
        if (amountOfUser(_account) > 0) {
            return globalEarned[_account];
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

    function getLastDistributedGLOBALAmount() external view returns (uint) {
        return lastDistributedGLOBALAmount;
    }

    function getLastDistributedBNBAmount() external view returns (uint) {
        return lastDistributedBNBAmount;
    }

    // Deposit globals as user.
    function deposit(uint _amount) public nonReentrant {
        bool userExists = false;
        global.safeTransferFrom(msg.sender, address(this), _amount);

        depositInfo[msg.sender].push(DepositInfo({
            amount: _amount,
            nextWithdraw: block.timestamp.add(LOCKUP)
        }));

        global.approve(address(globalMasterChef), _amount);
        globalMasterChef.enterStaking(_amount);

        for (uint j = 0; j < users.length; j++) {
            if (users[j] == msg.sender)
            {
                userExists = true;
                break;
            }
        }
        if (!userExists){
            users.push(msg.sender);
        }

        totalSupply = totalSupply.add(_amount);

        if (bnbToEarn(msg.sender) == 0) {
            bnbEarned[msg.sender] = 0;
        }

        if (globalToEarn(msg.sender) == 0) {
            globalEarned[msg.sender] = 0;
        }

        emit Deposited(msg.sender, _amount);
    }

    // Globals coming from vault vested (as depository)
    function depositRewards(uint _amount) public onlyDepositories {
        global.safeTransferFrom(msg.sender, address(this), _amount);
        globalBalance = globalBalance.add(_amount);

        _distributeGLOBAL();

        emit RewardsDeposited(msg.sender, _amount);
    }

    function amountOfUser(address _user) public view returns (uint totalAmount)
    {
        totalAmount = 0;
        DepositInfo[] memory myDeposits =  depositInfo[_user];
        for(uint i=0; i< myDeposits.length; i++)
        {
            totalAmount=totalAmount.add(myDeposits[i].amount);
        }
    }

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

    function removeAvailableDeposits(address user) private
    {
        uint256 btimestamp = block.timestamp;

        while(depositInfo[user].length > 0 && depositInfo[user][0].nextWithdraw< btimestamp)
        {
            for (uint i = 0; i<depositInfo[user].length-1; i++)
            {
                depositInfo[user][i] = depositInfo[user][i+1];
            }
            depositInfo[user].pop();
        }
    }

    // Withdraw all only
    function withdraw() external nonReentrant{
        uint amount = availableForWithdraw(block.timestamp,msg.sender);
        require(amount > 0, "VaultLocked: you have no tokens to withdraw!");
        uint earnedBNB = bnbToEarn(msg.sender);
        uint earnedGLOBAL = globalToEarn(msg.sender);

        removeAvailableDeposits(msg.sender);

        globalMasterChef.leaveStaking(amount);
        global.safeTransfer(msg.sender, amount);
        handleRewards(earnedBNB, earnedGLOBAL);
        totalSupply = totalSupply.sub(amount);
        _deleteUser(msg.sender);
        delete bnbEarned[msg.sender];
        delete globalEarned[msg.sender];
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() external nonReentrant {
        uint earnedBNB = bnbToEarn(msg.sender);
        uint earnedGLOBAL = globalToEarn(msg.sender);
        handleRewards(earnedBNB, earnedGLOBAL);
        delete bnbEarned[msg.sender];
        delete globalEarned[msg.sender];
    }

    function handleRewards(uint _earnedBNB, uint _earnedGLOBAL) private {
        if (_earnedBNB > DUST) {
            bnb.safeTransfer(msg.sender, _earnedBNB);
        } else {
            _earnedBNB = 0;
        }

        if (_earnedGLOBAL > DUST) {
            global.safeTransfer(msg.sender, _earnedGLOBAL);
        } else {
            _earnedGLOBAL = 0;
        }

        emit RewardPaid(msg.sender, _earnedBNB, _earnedGLOBAL);
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

    function _distributeBNB() private {
        uint bnbAmountToDistribute = bnbBalance;

        if (bnbAmountToDistribute < minTokenAmountToDistribute) {
            // Nothing to distribute.
            return;
        }

        for (uint i=0; i < users.length; i++) {
            uint userPercentage = amountOfUser(users[i]).mul(100).div(totalSupply);
            uint bnbToUser = bnbAmountToDistribute.mul(userPercentage).div(100);
            bnbBalance = bnbBalance.sub(bnbToUser);

            bnbEarned[users[i]] = bnbEarned[users[i]].add(bnbToUser);
        }

        lastDistributedBNBAmount = bnbAmountToDistribute.sub(bnbBalance);

        emit Distributed(lastDistributedBNBAmount);
    }

    function _distributeGLOBAL() private {
        uint globalAmountToDistribute = globalBalance;
        uint globalBalanceLocal = globalBalance;
        if(lastRewardEvent.add(rewardInterval)<=block.timestamp && globalAmountToDistribute >= minGlobalAmountToDistribute)
        {
            lastRewardEvent = block.timestamp;
            for (uint i=0; i < users.length; i++) {
                uint userPercentage = amountOfUser(users[i]).mul(100).div(totalSupply);
                uint globalToUser = globalAmountToDistribute.mul(userPercentage).div(100).div(20);
                globalBalanceLocal = globalBalanceLocal.sub(globalToUser);

                globalEarned[users[i]] = globalEarned[users[i]].add(globalToUser);
            }

            lastDistributedGLOBALAmount = globalAmountToDistribute.sub(globalBalanceLocal);

            globalBalance = globalBalanceLocal;

            emit DistributedGLOBAL(lastDistributedGLOBALAmount);
        }
    }
}