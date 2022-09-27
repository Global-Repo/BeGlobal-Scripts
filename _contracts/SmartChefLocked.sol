// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import './Modifiers/Ownable.sol';
import './Modifiers/ReentrancyGuard.sol';
import './Libraries/SafeBEP20.sol';
import './Libraries/SafeMath.sol';
import 'hardhat/console.sol';

contract SmartChefLocked is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    uint256 public depositsInterval = 3 days;
    uint256 public lockUp = 30 days;
    bool public openWithdraws = false;

    struct DepositInfo {
        uint amount;
        uint256 depTime;
        uint256 nextWithdraw;
    }

    mapping (address=>DepositInfo[]) public depositInfo;

    // The address of the smart chef factory
    address public SMART_CHEF_FACTORY;

    // Whether a limit is set for users
    bool public hasUserLimit;

    // Whether it is initialized
    bool public isInitialized;

    // Accrued token per share
    uint256 public accTokenPerShare;

    // The block number when GLOBAL mining ends.
    uint256 public bonusEndBlock;

    // The block number when GLOBAL mining starts.
    uint256 public startBlock;

    // The block number of the last pool update
    uint256 public lastRewardBlock;

    // The pool limit (0 if none)
    uint256 public poolLimitPerUser;

    // GLOBAL tokens created per block.
    uint256 public rewardPerBlock;

    // The precision factor
    uint256 public PRECISION_FACTOR;

    // The reward token
    IBEP20 public rewardToken;

    // The staked token
    IBEP20 public stakedToken;

    uint256 stakedTokenSupply;

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => UserInfo) public userInfo;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
    }

    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event NewRewardPerBlock(uint256 rewardPerBlock);
    event NewPoolLimit(uint256 poolLimitPerUser);
    event RewardsStop(uint256 blockNumber);
    event Withdraw(address indexed user, uint256 amount);

    constructor() public {
        SMART_CHEF_FACTORY = msg.sender;
    }

    /*
     * @notice Initialize the contract
     * @param _stakedToken: staked token address
     * @param _rewardToken: reward token address
     * @param _rewardPerBlock: reward per block (in rewardToken)
     * @param _startBlock: start block
     * @param _bonusEndBlock: end block
     * @param _poolLimitPerUser: pool limit per user in stakedToken (if any, else 0)
     * @param _admin: admin address with ownership
     */
    function initialize(
        IBEP20 _stakedToken,
        IBEP20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _poolLimitPerUser,
        address _admin
    ) external {
        require(!isInitialized, "Already initialized");
        require(msg.sender == SMART_CHEF_FACTORY, "Not factory");
        require(_startBlock < _bonusEndBlock, "Start block must be before than bonus end block");

        // Make this contract initialized
        isInitialized = true;

        stakedToken = _stakedToken;
        stakedTokenSupply = 0;
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        if (_poolLimitPerUser > 0) {
            hasUserLimit = true;
            poolLimitPerUser = _poolLimitPerUser;
        }

        uint256 decimalsRewardToken = uint256(rewardToken.decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(10**(uint256(30).sub(decimalsRewardToken)));

        // Set the lastRewardBlock as the startBlock
        lastRewardBlock = startBlock;

        // Transfer ownership to the admin address who becomes owner of the contract
        transferOwnership(_admin);
    }

    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function deposit(address _user, uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[_user];

        if (hasUserLimit) {
            require(_amount.add(user.amount) <= poolLimitPerUser, "User amount above limit");
        }

        _updatePool();

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
            if (pending > 0) {
                rewardToken.safeTransfer(_user, pending);
            }
        }

        if (_amount > 0) {
            if(depositInfo[_user].length==0 || depositInfo[_user][depositInfo[_user].length-1].depTime.add(depositsInterval)<block.timestamp)
            {
                depositInfo[_user].push(DepositInfo({
                    amount: _amount,
                    depTime: block.timestamp,
                    nextWithdraw: block.timestamp.add(lockUp)
                }));
            }
            else
            {
                depositInfo[_user][depositInfo[_user].length-1].amount = depositInfo[_user][depositInfo[_user].length-1].amount.add(_amount);
                depositInfo[_user][depositInfo[_user].length-1].nextWithdraw = block.timestamp.add(lockUp);
            }
            user.amount = user.amount.add(_amount);
            stakedTokenSupply = stakedTokenSupply.add(_amount);
            stakedToken.safeTransferFrom(address(_user), address(this), _amount);
        }

        user.rewardDebt = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR);

        emit Deposit(_user, _amount);
    }

    function availableForWithdraw(uint256 _time, address _user) public view returns (uint totalAmount)
    {
        if(openWithdraws)
        {
            totalAmount = userInfo[_user].amount;
        }
        else
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
    }

    function removeAvailableDeposits(address user) private
    {
        if(openWithdraws)
        {
            delete depositInfo[user];
        }
        else
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
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function withdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint amount = availableForWithdraw(block.timestamp,msg.sender);

        _updatePool();

        uint256 pending = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
        if (amount > 0) {
            user.amount = user.amount.sub(amount);
            stakedTokenSupply = stakedTokenSupply.sub(amount);
            stakedToken.safeTransfer(address(msg.sender), amount);
            removeAvailableDeposits(msg.sender);
        }

        if (pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }

        user.rewardDebt = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR);

        emit Withdraw(msg.sender, amount);
    }

    /*
     * @notice Withdraw staked tokens without caring about rewards rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amountToTransfer = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        delete depositInfo[msg.sender];

        if (amountToTransfer > 0) {
            stakedTokenSupply = stakedTokenSupply.sub(amountToTransfer);
            stakedToken.safeTransfer(address(msg.sender), amountToTransfer);
        }

        emit EmergencyWithdraw(msg.sender, amountToTransfer);
    }

    function setOpenWithdraws(bool _openWithdraws) external onlyOwner {
        openWithdraws = _openWithdraws;
    }

    function setDepositsInterval(uint256 _depositsInterval) external onlyOwner {
        depositsInterval = _depositsInterval;
    }

    function setLockUp(uint256 _lockUp) external onlyOwner {
        lockUp = _lockUp;
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(_amount <= rewardToken.balanceOf(address(this)).sub(stakedTokenSupply),"Cannot withdraw more than the deposited rewards");
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(stakedToken), "Cannot be staked token");
        require(_tokenAddress != address(rewardToken), "Cannot be reward token");

        IBEP20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner
     */
    function stopReward() external onlyOwner {
        require(bonusEndBlock > block.number, "Can't be stopped");
        bonusEndBlock = block.number;
    }

    /*
     * @notice Update pool limit per user
     * @dev Only callable by owner.
     * @param _hasUserLimit: whether the limit remains forced
     * @param _poolLimitPerUser: new pool limit per user
     */
    function updatePoolLimitPerUser(bool _hasUserLimit, uint256 _poolLimitPerUser) external onlyOwner {
        require(hasUserLimit, "Must be set");
        if (_hasUserLimit) {
            require(_poolLimitPerUser > poolLimitPerUser, "New limit must be higher");
            poolLimitPerUser = _poolLimitPerUser;
        } else {
            hasUserLimit = _hasUserLimit;
            poolLimitPerUser = 0;
        }
        emit NewPoolLimit(poolLimitPerUser);
    }

    /*
     * @notice Update reward per block
     * @dev Only callable by owner.
     * @param _rewardPerBlock: the reward per block
     */
    function updateRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        _updatePool();
        rewardPerBlock = _rewardPerBlock;
        emit NewRewardPerBlock(_rewardPerBlock);
    }

    /**
     * @notice It allows the admin to update start and end blocks
     * @dev This function is only callable by owner.
     * @param _startBlock: the new start block
     * @param _bonusEndBlock: the new end block
     */
    function updateStartAndEndBlocks(uint256 _startBlock, uint256 _bonusEndBlock) external onlyOwner {
        require(_startBlock < _bonusEndBlock, "New startBlock must be lower than new endBlock");

        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        // Set the lastRewardBlock as the startBlock
        lastRewardBlock = startBlock;

        emit NewStartAndEndBlocks(_startBlock, _bonusEndBlock);
    }

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        if (block.number > lastRewardBlock && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 globalReward = multiplier.mul(rewardPerBlock);
            uint256 adjustedTokenPerShare =
            accTokenPerShare.add(globalReward.mul(PRECISION_FACTOR).div(stakedTokenSupply));
            return user.amount.mul(adjustedTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
        } else {
            return user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
        }
    }

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }


        if (stakedTokenSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        uint256 globalReward = multiplier.mul(rewardPerBlock);
        accTokenPerShare = accTokenPerShare.add(globalReward.mul(PRECISION_FACTOR).div(stakedTokenSupply));
        lastRewardBlock = block.number;
    }

    /*
     * @notice Return reward multiplier over the given _from to _to block.
     * @param _from: block to start
     * @param _to: block to finish
     */
    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_from > startBlock && _to < bonusEndBlock) return _to.sub(_from);
        if (_from <= startBlock && _to >= bonusEndBlock) return bonusEndBlock.sub(startBlock);
        if (_from > startBlock && _from < bonusEndBlock && _to >= bonusEndBlock) return bonusEndBlock.sub(_from);
        if (_to > startBlock && _to < bonusEndBlock && _from <= startBlock) return _to.sub(startBlock);
        else return 0;
    }
}