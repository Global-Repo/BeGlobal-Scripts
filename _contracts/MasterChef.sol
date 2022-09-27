// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import './Helpers/Context.sol';
import "./Helpers/IMinter.sol";
import "./Helpers/TokenAddresses.sol";
import "./Helpers/IPathFinder.sol";
import "./Helpers/IMintNotifier.sol";
import './Modifiers/Ownable.sol';
import './Modifiers/Trusted.sol';
import './Modifiers/DevPower.sol';
import './Modifiers/ReentrancyGuard.sol';
import './Libraries/Address.sol';
import './Libraries/SafeBEP20.sol';
import './Libraries/SafeMath.sol';
import './Tokens/IBEP20.sol';
import './Tokens/BEP20.sol';
import './Tokens/NativeToken.sol';
import './Tokens/IPair.sol';
import './IRouterV2.sol';
import "./MasterChefInternal.sol";

// We hope code is bug-free. For everyone's life savings.
contract MasterChef is Ownable, DevPower, ReentrancyGuard, IMinter, Trusted {
    using SafeMath for uint16;
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 rewardLockedUp;
        uint256 nextHarvestUntil;
        uint256 withdrawalOrPerformanceFees;
        bool whitelisted;
    }

    struct PoolInfo {
        IBEP20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accNativeTokenPerShare;
        uint256 harvestInterval;
        uint256 maxWithdrawalInterval;
        uint16 withDrawalFeeOfLpsBurn;
        uint16 withDrawalFeeOfLpsTeam;
        uint16 performanceFeesOfNativeTokensBurn;
        uint16 performanceFeesOfNativeTokensToLockedVault;
    }

    IRouterV2 public routerGlobal;

    NativeToken public nativeToken;

    TokenAddresses public tokenAddresses;

    bool public safu = true;

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address public nativeTokenLockedVaultAddr;
    address public treasury;
    address public treasuryLP;

    uint256 public nativeTokenPerBlock;

    uint256 public BONUS_MULTIPLIER = 1;

    uint256 public constant MAX_INTERVAL = 30 days;
    uint16 public constant MAX_FEE_PERFORMANCE = 500;

    uint16 public constant MAX_FEE_LPS = 150;

    PoolInfo[] public poolInfo;

    uint256 public totalFeesToBurn = 0;

    uint256 public totalFeesToBoostLocked = 0;

    uint16 public counterForTransfers = 0;

    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    uint256 public totalAllocPoint = 0;

    uint256 public startBlock;

    uint256 public totalLockedUpRewards;

    mapping(address => bool) public _minters;

    IPathFinder public pathFinder;
    IMintNotifier public mintNotifier;
    MasterChefInternal public masterChefInternal;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, uint256 finalAmount);
    event EmissionRateUpdated(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event RewardLockedUp(address indexed user, uint256 indexed pid, uint256 amountLockedUp);

    mapping(IBEP20 => bool) public poolExistence;
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    constructor(
        address _masterChefInternal,
        NativeToken _nativeToken,
        uint256 _nativeTokenPerBlock,
        uint256 _startBlock,
        address _routerGlobal,
        address _tokenAddresses,
        address _pathFinder
    ) public {
        masterChefInternal = MasterChefInternal(_masterChefInternal);
        nativeToken = _nativeToken;
        nativeTokenPerBlock = _nativeTokenPerBlock;
        startBlock = _startBlock;
        treasury = msg.sender;
        treasuryLP = msg.sender;
        routerGlobal = IRouterV2(_routerGlobal);
        tokenAddresses = TokenAddresses(_tokenAddresses);
        pathFinder = IPathFinder(_pathFinder);

        poolInfo.push(PoolInfo({
            lpToken: _nativeToken,
            allocPoint: 0,
            lastRewardBlock: _startBlock,
            accNativeTokenPerShare: 0,
            harvestInterval: 0,
            maxWithdrawalInterval: 0,
            withDrawalFeeOfLpsBurn: 0,
            withDrawalFeeOfLpsTeam: 0,
            performanceFeesOfNativeTokensBurn: 0,
            performanceFeesOfNativeTokensToLockedVault: 0
        }));
    }

    function setRouter(address _router) public onlyOwner {
        routerGlobal = IRouterV2(_router);
    }

    function setPathFinder(address _pathFinder) public onlyOwner {
        pathFinder = IPathFinder(_pathFinder);
        masterChefInternal.setInternalPathFinder(_pathFinder);
    }

    function addRouteToPathFinder(
        address _token, address _tokenRoute, bool _directBNB
    ) public onlyOwner {
        masterChefInternal.addRouteToPathFinder(_token,_tokenRoute, _directBNB);
    }

    function removeRouteToPathFinder(
        address _token
    ) public onlyOwner {
        masterChefInternal.removeRouteToPathFinder(_token);
    }

    function setLockedVaultAddress(address _newLockedVault) external onlyOwner{
        require(_newLockedVault != address(0), "(f) SetLockedVaultAddress: you can't set the locked vault address to 0.");
        nativeTokenLockedVaultAddr = _newLockedVault;
    }

    function getLockedVaultAddress() external view returns(address){
        return nativeTokenLockedVaultAddr;
    }

    function setSAFU(bool _safu) external onlyDevPower{
        safu = _safu;
    }
    function isSAFU() public view returns(bool){
        return safu;
    }

    function setWhitelistedUser(uint256 _pid, address _user, bool isWhitelisted) external onlyOwner {
        userInfo[_pid][_user].whitelisted = isWhitelisted;
    }
    function isWhitelistedUser(uint256 _pid, address _user) view external returns (bool) {
        return userInfo[_pid][_user].whitelisted;
    }

    function setMintNotifier(address _mintNotifier) public onlyOwner {
        mintNotifier = IMintNotifier(_mintNotifier);
    }

    function getMintNotifierAddress() view external returns (address) {
        return address(mintNotifier);
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function setMinter(address minter, bool canMint) external override onlyOwner {
        if (canMint) {
            _minters[minter] = canMint;
        } else {
            delete _minters[minter];
        }
    }

    modifier onlyMinter {
        require(_minters[msg.sender] == true, "[f] OnlyMinter: caller is not the minter.");
        _;
    }

    function isMinter(address account) view external override returns (bool) {
        if (nativeToken.getOwner() != address(this)) {
            return false;
        }

        return _minters[account];
    }

    function mintNativeTokens(uint _quantityToMint, address userFor) external override onlyMinter {
        nativeToken.mints(treasury, _quantityToMint.div(10));

        nativeToken.mints(msg.sender, _quantityToMint);

        if(address(mintNotifier) != address(0))
        {
            mintNotifier.notify(msg.sender, userFor, _quantityToMint);
        }
    }

    function nativeTokenAddBlacklisted(address account) external onlyOwner() {
        nativeToken.addBlacklisted(account);
    }

    function nativeTokenRemoveBlacklisted(address account) external onlyOwner() {
        nativeToken.removeBlacklisted(account);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function addPool(
        uint256 _allocPoint,
        IBEP20 _lpToken,
        uint256 _harvestInterval,
        uint256 _maxWithdrawalInterval,
        uint16 _withDrawalFeeOfLpsBurn,
        uint16 _withDrawalFeeOfLpsTeam,
        uint16 _performanceFeesOfNativeTokensBurn,
        uint16 _performanceFeesOfNativeTokensToLockedVault
    ) public onlyOwner nonDuplicated(_lpToken) {
        require(_harvestInterval <= MAX_INTERVAL, "[f] Add: invalid harvest interval");
        require(_maxWithdrawalInterval <= MAX_INTERVAL, "[f] Add: invalid withdrawal interval. Owner, there is a limit! Check your numbers.");
        require(_withDrawalFeeOfLpsTeam.add(_withDrawalFeeOfLpsBurn) <= MAX_FEE_LPS, "[f] Add: invalid withdrawal fees. Owner, you are trying to charge way too much! Check your numbers.");
        require(_performanceFeesOfNativeTokensBurn.add(_performanceFeesOfNativeTokensToLockedVault) <= MAX_FEE_PERFORMANCE, "[f] Add: invalid performance fees. Owner, you are trying to charge way too much! Check your numbers.");
        require(masterChefInternal.checkTokensRoutes(_lpToken), "[f] Add: token/s not connected to WBNB");

        massUpdatePools();

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;

        poolInfo.push(PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accNativeTokenPerShare: 0,
        harvestInterval: _harvestInterval,
        maxWithdrawalInterval: _maxWithdrawalInterval,
        withDrawalFeeOfLpsBurn: _withDrawalFeeOfLpsBurn,
        withDrawalFeeOfLpsTeam: _withDrawalFeeOfLpsTeam,
        performanceFeesOfNativeTokensBurn: _performanceFeesOfNativeTokensBurn,
        performanceFeesOfNativeTokensToLockedVault: _performanceFeesOfNativeTokensToLockedVault
        }));
    }

    function setPool(
        uint256 _pid,
        uint256 _allocPoint,
        uint256 _harvestInterval,
        uint256 _maxWithdrawalInterval,
        uint16 _withDrawalFeeOfLpsBurn,
        uint16 _withDrawalFeeOfLpsTeam,
        uint16 _performanceFeesOfNativeTokensBurn,
        uint16 _performanceFeesOfNativeTokensToLockedVault
    ) public onlyOwner {
        require(_harvestInterval <= MAX_INTERVAL, "[f] Set: invalid harvest interval");
        require(_maxWithdrawalInterval <= MAX_INTERVAL, "[f] Set: invalid withdrawal interval. Owner, there is a limit! Check your numbers.");
        require(_withDrawalFeeOfLpsTeam.add(_withDrawalFeeOfLpsBurn) <= MAX_FEE_LPS, "[f] Set: invalid withdrawal fees. Owner, you are trying to charge way too much! Check your numbers.");
        require(_performanceFeesOfNativeTokensBurn.add(_performanceFeesOfNativeTokensToLockedVault) <= MAX_FEE_PERFORMANCE, "[f] Set: invalid performance fees. Owner, you are trying to charge way too much! Check your numbers.");

        massUpdatePools();

        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].harvestInterval = _harvestInterval;
        poolInfo[_pid].maxWithdrawalInterval = _maxWithdrawalInterval;
        poolInfo[_pid].withDrawalFeeOfLpsBurn = _withDrawalFeeOfLpsBurn;
        poolInfo[_pid].withDrawalFeeOfLpsTeam = _withDrawalFeeOfLpsTeam;
        poolInfo[_pid].performanceFeesOfNativeTokensBurn = _performanceFeesOfNativeTokensBurn;
        poolInfo[_pid].performanceFeesOfNativeTokensToLockedVault = _performanceFeesOfNativeTokensToLockedVault;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending native tokens on frontend.
    function pendingNativeToken(uint256 _pid, address _user) external view returns (uint256) {
        if (_pid == 0) return 0;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accNativeTokenPerShare = pool.accNativeTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        bool performanceFee = withdrawalOrPerformanceFee(_pid, _user);

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 nativeTokenReward = multiplier.mul(nativeTokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

            accNativeTokenPerShare = accNativeTokenPerShare.add(nativeTokenReward.mul(1e12).div(lpSupply));
        }

        uint256 pending = user.amount.mul(accNativeTokenPerShare).div(1e12).sub(user.rewardDebt);

        pending = pending.add(user.rewardLockedUp);

        if (performanceFee && !user.whitelisted){
            pending = pending.sub(pending.mul(pool.performanceFeesOfNativeTokensBurn.add(pool.performanceFeesOfNativeTokensToLockedVault)).div(10000));
        }

        return pending;
    }

    // View function to see if user can harvest.
    function canHarvest(uint256 _pid, address _user) public view returns (bool) {
        UserInfo storage user = userInfo[_pid][_user];
        return block.timestamp >= user.nextHarvestUntil || user.whitelisted;
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        // We do not want to update pool 0
        if (_pid == 0) return;

        PoolInfo storage pool = poolInfo[_pid];

        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);

        uint256 nativeTokenReward = multiplier.mul(nativeTokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

        nativeToken.mints(treasury, nativeTokenReward.div(10));

        nativeToken.mints(address(this), nativeTokenReward);

        pool.accNativeTokenPerShare = pool.accNativeTokenPerShare.add(nativeTokenReward.mul(1e12).div(lpSupply));

        pool.lastRewardBlock = block.number;
    }

    function payOrLockupPendingNativeToken(uint256 _pid) internal returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        bool performanceFee = withdrawalOrPerformanceFee(_pid, msg.sender);

        if (user.nextHarvestUntil == 0) {
            user.nextHarvestUntil = block.timestamp.add(pool.harvestInterval);
        }

        uint256 pending = user.amount.mul(pool.accNativeTokenPerShare).div(1e12).sub(user.rewardDebt);

        if (canHarvest(_pid, msg.sender)) {

            if (pending > 0 || user.rewardLockedUp > 0) {

                uint256 totalRewards = pending.add(user.rewardLockedUp);

                totalLockedUpRewards = totalLockedUpRewards.sub(user.rewardLockedUp);
                user.rewardLockedUp = 0;

                user.nextHarvestUntil = block.timestamp.add(pool.harvestInterval);

                if (!user.whitelisted){

                        counterForTransfers++;

                        if (performanceFee){
                            totalFeesToBurn = totalFeesToBurn.add((totalRewards.mul(pool.performanceFeesOfNativeTokensBurn)).div(10000));
                            totalFeesToBoostLocked = totalFeesToBoostLocked.add((totalRewards.mul(pool.performanceFeesOfNativeTokensToLockedVault)).div(10000));
                            totalRewards = totalRewards.sub(totalRewards.mul(pool.performanceFeesOfNativeTokensBurn.add(pool.performanceFeesOfNativeTokensToLockedVault)).div(10000));
                        }
                        else
                        {
                            totalFeesToBurn = totalFeesToBurn.add((totalRewards.mul(pool.performanceFeesOfNativeTokensBurn).mul(2)).div(10000));
                            totalFeesToBoostLocked = totalFeesToBoostLocked.add((totalRewards.mul(pool.performanceFeesOfNativeTokensToLockedVault).mul(2)).div(10000));
                            totalRewards = totalRewards.sub(totalRewards.mul(pool.performanceFeesOfNativeTokensBurn.add(pool.performanceFeesOfNativeTokensToLockedVault)).mul(2).div(10000));
                        }

                        if (counterForTransfers > 25){

                            counterForTransfers = 0;

                            SafeNativeTokenTransfer(BURN_ADDRESS, totalFeesToBurn);
                            totalFeesToBurn = 0;

                            SafeNativeTokenTransfer(nativeTokenLockedVaultAddr, totalFeesToBoostLocked);

                            totalFeesToBoostLocked = 0;
                        }
                }

                SafeNativeTokenTransfer(msg.sender, totalRewards);
            }

        } else if (pending > 0) {

            user.rewardLockedUp = user.rewardLockedUp.add(pending);

            totalLockedUpRewards = totalLockedUpRewards.add(pending);

            emit RewardLockedUp(msg.sender, _pid, pending);
        }

        return performanceFee;
    }

    function deposit(uint256 _pid, uint256 _amount) public nonReentrant{
        require (_pid != 0, 'deposit GLOBAL by staking');
        require (_pid < poolInfo.length, 'This pool does not exist yet');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        payOrLockupPendingNativeToken(_pid);

        if (_amount > 0) {

            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

            user.amount = user.amount.add(_amount);

            user.withdrawalOrPerformanceFees = block.timestamp.add(pool.maxWithdrawalInterval);
        }

        user.rewardDebt = user.amount.mul(pool.accNativeTokenPerShare).div(1e12);

        emit Deposit(msg.sender, _pid, _amount);


    }

    function getLPFees(uint256 _pid, uint256 _amount) private returns(uint256){
        PoolInfo storage pool = poolInfo[_pid];

        uint256 finalAmount = _amount.sub(
            _amount.mul(pool.withDrawalFeeOfLpsBurn.add(pool.withDrawalFeeOfLpsTeam)).div(10000)
        );

        if (finalAmount != _amount)
        {
            IBEP20(pool.lpToken).safeTransfer(treasuryLP, _amount.mul(pool.withDrawalFeeOfLpsBurn.add(pool.withDrawalFeeOfLpsTeam)).div(10000));
        }

        return finalAmount;
    }

    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant{
        require (_pid != 0, 'withdraw GLOBAL by unstaking');
        require (_pid < poolInfo.length, 'This pool does not exist yet');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "[f] Withdraw: you are trying to withdraw more tokens than you have. Cheeky boy. Try again.");

        uint256 finalAmount = _amount;

        updatePool(_pid);

        bool performancefeeTaken = payOrLockupPendingNativeToken(_pid);

        if(_amount > 0){
            if (!performancefeeTaken && !user.whitelisted){ 
                finalAmount = getLPFees(_pid, _amount);
            }

            user.amount = user.amount.sub(_amount);

            pool.lpToken.safeTransfer(address(msg.sender), finalAmount);
        }

        user.rewardDebt = user.amount.mul(pool.accNativeTokenPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function enterStaking(uint256 _amount) public onlyWhitelisted nonReentrant{
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accNativeTokenPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                SafeNativeTokenTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accNativeTokenPerShare).div(1e12);

        emit Deposit(msg.sender, 0, _amount);
    }

    function leaveStaking(uint256 _amount) public onlyWhitelisted nonReentrant{
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accNativeTokenPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            SafeNativeTokenTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accNativeTokenPerShare).div(1e12);

        emit Withdraw(msg.sender, 0, _amount);
    }

    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.amount == 0){
            return;
        }

        uint256 finalAmount = user.amount;
        PoolInfo storage pool = poolInfo[_pid];

        if (safu && !withdrawalOrPerformanceFee(_pid, msg.sender) && !user.whitelisted){
            finalAmount = getLPFees(_pid, user.amount);
        }

        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardLockedUp = 0;
        user.nextHarvestUntil = 0;
        user.withdrawalOrPerformanceFees = 0;
        pool.lpToken.safeTransfer(address(msg.sender), finalAmount);
        emit EmergencyWithdraw(msg.sender, _pid, amount, finalAmount);
    }

    function withdrawalOrPerformanceFee(uint256 _pid, address _user) public view returns (bool) {
        UserInfo storage user = userInfo[_pid][_user];
        return block.timestamp >= user.withdrawalOrPerformanceFees;
    }

    function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0), "[f] Dev: _treasury can't be address(0).");
        treasury = _treasury;
    }

    function setTreasuryLP(address _treasuryLP) public onlyOwner {
        require(_treasuryLP != address(0), "[f] Dev: _treasuryLP can't be address(0).");
        treasuryLP = _treasuryLP;
    }

    function SafeNativeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 nativeTokenBal = nativeToken.balanceOf(address(this));
        if (_amount > nativeTokenBal) {
            nativeToken.transfer(_to, nativeTokenBal);
        } else {
            nativeToken.transfer(_to, _amount);
        }
    }

    function updateEmissionRate(uint256 _nativeTokenPerBlock) public onlyOwner {
        massUpdatePools();
        emit EmissionRateUpdated(msg.sender, nativeTokenPerBlock, _nativeTokenPerBlock);
        nativeTokenPerBlock = _nativeTokenPerBlock;
    }
}