// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../Libraries/SafeBEP20.sol";
import "../Libraries/Math.sol";
import '../Helpers/IPathFinder.sol';
import "../Helpers/TokenAddresses.sol";
import "../Helpers/IMinter.sol";
import "../Modifiers/PausableUpgradeable.sol";
import "../Modifiers/WhitelistUpgradeable.sol";
import "../Tokens/IPair.sol";
import "../IRouterV2.sol";
import "./Interfaces/IStrategy.sol";
import "./Externals/ICakeMasterChef.sol";
import "./VaultVested.sol";
import './VaultDistribution.sol';
import 'hardhat/console.sol';

contract VaultCakeWBNBLP is IStrategy, PausableUpgradeable, WhitelistUpgradeable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;
    using SafeMath for uint16;

    IBEP20 public _stakingToken;
    IStrategy private _rewardsToken;
    IBEP20 public global;
    IBEP20 public cake;
    IBEP20 public wbnb;
    ICakeMasterChef public cakeMasterChef;
    IRouterV2 public cakeRouter;
    IMinter public minter;
    address public treasury;
    VaultVested public vaultVested;
    VaultDistribution public vaultDistribution;
    IRouterV2 public globalRouter;
    IPathFinder public pathFinder;
    TokenAddresses public tokenAddresses;

    uint16 public constant MAX_WITHDRAWAL_FEES = 100; // 1%
    uint public constant DUST = 1000;
    uint private constant SLIPPAGE = 9500;
    address public constant GLOBAL_BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    uint256 public pid;
    uint public periodFinish;
    uint public rewardRate;
    uint public rewardsDuration;
    uint public lastUpdateTime;
    uint public rewardPerTokenStored;

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;

    uint private _totalSupply;
    mapping(address => uint) private _balances;
    mapping(address => uint) private _depositedAt;

    struct WithdrawalFees {
        uint16 burn;      // % to burn (in Global)
        uint16 team;      // % to devs (in BUSD)
        uint256 interval; // Meanwhile, fees will be apply (timestamp)
    }

    struct Rewards {
        uint16 toUser;       // % to user
        uint16 toOperations; // % to treasury (in BUSD)
        uint16 toBuyGlobal;  // % to keeper as user (in Global)
        uint16 toBuyWBNB;    // % to keeper as vault (in WBNB)
        uint16 toMintGlobal; // % to mint global multiplier (relation to toBuyGlobal)
    }

    WithdrawalFees public withdrawalFees;
    Rewards public rewardsSetUp;

    event RewardAdded(uint reward);
    event RewardsDurationUpdated(uint newDuration);

    modifier onlyNonContract() {
        require(tx.origin == msg.sender);
        address a = msg.sender;
        uint32 size;
        assembly {
            size := extcodesize(a)
        }
        require(size == 0, "Contract calls not allowed");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(
        uint256 _pid,
        address _lpToken,
        address _global,
        address _cake,
        address _wbnb,
        address _cakeMasterChef,
        address _cakeRouter,
        address _treasury,
        address _tokenAddresses,
        address _globalRouter,
        address _pathFinder,
        address _vaultDistribution,
        address _vaultVested,
        address _vaultCake
    ) public {
        pid = _pid;
        _stakingToken = IBEP20(_lpToken);
        _rewardsToken = IStrategy(_vaultCake);
        global = IBEP20(_global);
        cake = IBEP20(_cake);
        wbnb = IBEP20(_wbnb);
        cakeMasterChef = ICakeMasterChef(_cakeMasterChef);
        cakeRouter = IRouterV2(_cakeRouter);
        treasury = _treasury;
        vaultVested = VaultVested(_vaultVested);
        vaultDistribution = VaultDistribution(_vaultDistribution);

        _stakingToken.safeApprove(_cakeMasterChef, uint(~0));

        __PausableUpgradeable_init();
        __WhitelistUpgradeable_init();

        setDefaultWithdrawalFees();
        setDefaultRewardFees();

        tokenAddresses = TokenAddresses(_tokenAddresses);
        globalRouter = IRouterV2(_globalRouter);
        pathFinder = IPathFinder(_pathFinder);

        IPair pair = IPair(tokenAddresses.findByName(tokenAddresses.CAKE_WBNB_LP()));
        _allowance(IBEP20(address(pair)), _cakeRouter);
        _allowance(cake, _globalRouter);
        _allowance(wbnb, _globalRouter);
        _allowance(cake, _vaultCake);
    }

    function setMinter(address _minter) external onlyOwner {
        require(IMinter(_minter).isMinter(address(this)) == true, "This vault must be a minter in minter's contract");
        _stakingToken.safeApprove(_minter, 0);
        _stakingToken.safeApprove(_minter, uint(~0));
        minter = IMinter(_minter);
    }

    function setWithdrawalFees(uint16 burn, uint16 team, uint256 interval) public onlyOwner {
        require(burn.add(team) <= MAX_WITHDRAWAL_FEES, "Withdrawal fees too high");

        withdrawalFees.burn = burn;
        withdrawalFees.team = team;
        withdrawalFees.interval = interval;
    }

    function setRewards(
        uint16 _toUser,
        uint16 _toOperations,
        uint16 _toBuyGlobal,
        uint16 _toBuyWBNB,
        uint16 _toMintGlobal
    ) public onlyOwner {
        require(_toUser.add(_toOperations).add(_toBuyGlobal).add(_toBuyWBNB) == 10000, "Rewards must add up to 100%");

        rewardsSetUp.toUser = _toUser;
        rewardsSetUp.toOperations = _toOperations;
        rewardsSetUp.toBuyGlobal = _toBuyGlobal;
        rewardsSetUp.toBuyWBNB = _toBuyWBNB;
        rewardsSetUp.toMintGlobal = _toMintGlobal;
    }

    function setDefaultWithdrawalFees() private {
        setWithdrawalFees(60, 10, 4 days);
    }

    function setDefaultRewardFees() private {
        setRewards(7500, 400, 600, 1500, 25000);
    }

    function canMint() internal view returns (bool) {
        return address(minter) != address(0) && minter.isMinter(address(this));
    }

    function totalSupply() external view override returns (uint) {
        return _totalSupply;
    }

    function balanceMC() override external view returns (uint) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint) {
        return _balances[account];
    }

    function sharesOf(address account) external view override returns (uint) {
        return _balances[account];
    }

    function principalOf(address account) external view override returns (uint) {
        return _balances[account];
    }

    function depositedAt(address account) external view override returns (uint) {
        return _depositedAt[account];
    }

    function withdrawableBalanceOf(address account) public view override returns (uint) {
        return _balances[account];
    }

    function stakingToken() external view returns (address) {
        return address(_stakingToken);
    }

    function rewardsToken() external view override returns (address) {
        return address(_rewardsToken);
    }

    function priceShare() external view override returns (uint) {
        return 1e18;
    }

    function lastTimeRewardApplicable() public view returns (uint) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
        rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
        );
    }

    function earned(address account) override public view returns (uint) {
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint) {
        return rewardRate.mul(rewardsDuration);
    }

    function deposit(uint amount) override onlyNonContract public {
        _deposit(amount, msg.sender);
    }

    function depositAll() override onlyNonContract external {
        deposit(_stakingToken.balanceOf(msg.sender));
    }

    function _deposit(uint amount, address _to) private notPaused updateReward(_to) {
        require(amount > 0, "Amount must be greater than zero");
        _totalSupply = _totalSupply.add(amount);
        _balances[_to] = _balances[_to].add(amount);
        _depositedAt[_to] = block.timestamp;
        _stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint cakeHarvested = _depositStakingToken(amount);
        emit Deposited(_to, amount);

        _harvest(cakeHarvested);
    }

    function withdraw(uint amount) override public onlyNonContract updateReward(msg.sender) {
        require(amount > 0, "Amount must be greater than zero");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        uint cakeHarvested = _withdrawStakingToken(amount);

        // Borrar esta linia
        uint withdrawalFee = 0;
        /*
        if (canMint()) {
            uint depositTimestamp = _depositedAt[msg.sender];
            withdrawalFee = _minter.withdrawalFee(amount, depositTimestamp);
            if (withdrawalFee > 0) {
                uint performanceFee = withdrawalFee.div(100);
                _minter.mintForV2(address(_stakingToken), withdrawalFee.sub(performanceFee), performanceFee, msg.sender, depositTimestamp);
                amount = amount.sub(withdrawalFee);
            }
        }
        */

        handleWithdrawalFees(amount);

        _stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, withdrawalFee);

        _harvest(cakeHarvested);
    }

    function withdrawAll() external override onlyNonContract {
        uint _withdraw = withdrawableBalanceOf(msg.sender);
        if (_withdraw > 0) {
            withdraw(_withdraw);
        }

        getReward();
    }

    function harvest() external override onlyNonContract {
        uint lpTokenHarvested = _withdrawStakingToken(0);
        _harvest(lpTokenHarvested);
    }

    function getReward() public override onlyNonContract updateReward(msg.sender) {
        uint reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            uint before = cake.balanceOf(address(this));
            _rewardsToken.withdraw(reward);
            uint cakeBalance = cake.balanceOf(address(this)).sub(before);


            uint performanceFee = 0;
            /*
            if (canMint()) {
                performanceFee = _minter.performanceFee(cakeBalance);
                _minter.mintForV2(CAKE, 0, performanceFee, msg.sender, _depositedAt[msg.sender]);
            }
            */

            handleRewards(reward);

            cake.safeTransfer(msg.sender, cakeBalance.sub(performanceFee));
            emit ProfitPaid(msg.sender, cakeBalance);
            //emit ProfitPaid(msg.sender, cakeBalance, performanceFee);
        }
    }

    // Receives lpToken as amount
    function handleWithdrawalFees(uint _amount) private {
        // Swaps lpToken to CAKE and BNB (remove liquidity)
        (uint amountCake, uint amountBNB) = cakeRouter.removeLiquidity(
            address(cake),
            address(wbnb),
            _amount,
            0,
            0,
            address(this),
            block.timestamp
        );

        // No withdrawal fees
        if (_depositedAt[msg.sender].add(withdrawalFees.interval) < block.timestamp) {
            // Swaps BNB to CAKE
            address[] memory pathToCake = pathFinder.findPath(address(wbnb), address(cake));
            uint[] memory amountsPredicted = globalRouter.getAmountsOut(amountBNB, pathToCake);
            uint[] memory amountsCake = globalRouter.swapExactTokensForTokens(
                amountBNB,
                (amountsPredicted[amountsPredicted.length-1].mul(SLIPPAGE)).div(10000),
                pathToCake,
                address(this),
                block.timestamp
            );

            uint amountCakeSwapped = amountsCake[amountsCake.length-1];

            cake.safeTransfer(msg.sender, amountCake.add(amountCakeSwapped));
            emit Withdrawn(msg.sender, amountCake.add(amountCakeSwapped), 0);
            return;
        }

        // Swaps CAKE to BNB
        address[] memory pathToBnb = pathFinder.findPath(address(cake), address(wbnb));
        uint[] memory amountsPredicted = globalRouter.getAmountsOut(amountCake, pathToBnb);
        uint[] memory amountsBNB = globalRouter.swapExactTokensForTokens(
            amountCake,
            (amountsPredicted[amountsPredicted.length-1].mul(SLIPPAGE)).div(10000),
            pathToBnb,
            address(this),
            block.timestamp
        );

        // Total BNB swapped amount + BNB
        uint totalAmountBNB = amountsBNB[amountsBNB.length-1].add(amountBNB);

        uint amountToBurn = totalAmountBNB.mul(withdrawalFees.burn).div(10000);
        uint amountToTeam = totalAmountBNB.mul(withdrawalFees.team).div(10000);
        uint amountToUser = totalAmountBNB.sub(amountToTeam).sub(amountToBurn);

        address[] memory pathToGlobal = pathFinder.findPath(address(wbnb), address(global));
        address[] memory pathToBusd = pathFinder.findPath(address(wbnb), tokenAddresses.findByName(tokenAddresses.BUSD()));

        // Swaps BNB to GLOBAL and burns GLOBAL
        if (amountToBurn < DUST) {
            amountToUser = amountToUser.add(amountToBurn);
        } else {
            uint[] memory amountsPredictedBNBGlobal = globalRouter.getAmountsOut(amountToBurn, pathToGlobal);
            globalRouter.swapExactTokensForTokens(
                amountToBurn,
                (amountsPredictedBNBGlobal[amountsPredictedBNBGlobal.length-1].mul(SLIPPAGE)).div(10000),
                pathToGlobal,
                GLOBAL_BURN_ADDRESS,
                block.timestamp
            );
        }

        // Swaps BNB to BUSD and sends BUSD to treasury
        if (amountToTeam < DUST) {
            amountToUser = amountToUser.add(amountToTeam);
        } else {
            uint[] memory amountsPredictedBNBBUSD = globalRouter.getAmountsOut(amountToTeam, pathToBusd);
            globalRouter.swapExactTokensForTokens(
                amountToTeam,
                (amountsPredictedBNBBUSD[amountsPredictedBNBBUSD.length-1].mul(SLIPPAGE)).div(10000),
                pathToBusd,
                treasury,
                block.timestamp
            );
        }

        // Swaps BNB to CAKE and sends CAKES to user
        address[] memory pathToCake = pathFinder.findPath(address(wbnb), address(cake));
        uint[] memory amountsPredictedToCake = globalRouter.getAmountsOut(amountToUser, pathToBnb);
        uint[] memory amountsCake = globalRouter.swapExactTokensForTokens(
            amountToUser,
            (amountsPredictedToCake[amountsPredictedToCake.length-1].mul(SLIPPAGE)).div(10000),
            pathToCake,
            address(this),
            block.timestamp
        );

        uint amountCakeSwapped = amountsCake[amountsCake.length-1];

        cake.safeTransfer(msg.sender, amountCakeSwapped);
        emit Withdrawn(msg.sender, amountCakeSwapped, 0);
    }

    // Receives cakes as amount
    function handleRewards(uint _amount) private {
        if (_amount < DUST) {
            return; // No rewards
        }

        // Swaps CAKE to BNB
        address[] memory pathToBnb = pathFinder.findPath(address(cake), address(wbnb));
        uint[] memory amountsPredicted = globalRouter.getAmountsOut(_amount, pathToBnb);
        uint[] memory amountsBNB = globalRouter.swapExactTokensForTokens(
            _amount,
            (amountsPredicted[amountsPredicted.length-1].mul(SLIPPAGE)).div(10000),
            pathToBnb,
            address(this),
            block.timestamp
        );

        uint amountBNB = amountsBNB[amountsBNB.length-1];

        uint deadline = block.timestamp;
        uint amountToUser = amountBNB.mul(rewardsSetUp.toUser).div(10000);
        uint amountToOperations = amountBNB.mul(rewardsSetUp.toOperations).div(10000);
        uint amountToBuyGlobal = amountBNB.mul(rewardsSetUp.toBuyGlobal).div(10000);
        uint amountToBuyWBNB = amountBNB.mul(rewardsSetUp.toBuyWBNB).div(10000);

        // Swaps BNB for BUSD and sends BUSD to treasury
        if (amountToOperations < DUST) {
            amountToUser = amountToUser.add(amountToOperations);
        } else {
            address[] memory pathToBusd = pathFinder.findPath(
                tokenAddresses.findByName(tokenAddresses.BNB()),
                tokenAddresses.findByName(tokenAddresses.BUSD())
            );
            uint[] memory amountsPredictedBNBBUSD = globalRouter.getAmountsOut(amountToOperations, pathToBusd);
            globalRouter.swapExactTokensForTokens(
                amountToOperations,
                (amountsPredictedBNBBUSD[amountsPredictedBNBBUSD.length-1].mul(SLIPPAGE)).div(10000),
                pathToBusd,
                treasury,
                deadline
            );
        }

        // Sends BNB to distribution vault
        if (amountToBuyWBNB < DUST) {
            amountToUser = amountToUser.add(amountToBuyWBNB);
        } else {
            wbnb.approve(address(vaultDistribution), amountToBuyWBNB);
            vaultDistribution.deposit(amountToBuyWBNB);
        }

        // Swaps BNB for GLOBAL and sends GLOBAL to vested vault (as user)
        // Mints GLOBAL and sends GLOBAL to vested vault (as user)
        if (amountToBuyGlobal < DUST) {
            amountToUser = amountToUser.add(amountToBuyGlobal);
        } else {
            address[] memory pathToGlobal = pathFinder.findPath(address(cake), address(global));
            uint[] memory amountsPredictedBNBGlobal = globalRouter.getAmountsOut(amountToBuyGlobal, pathToGlobal);
            uint[] memory amountsGlobal = globalRouter.swapExactTokensForTokens(
                amountToBuyGlobal,
                (amountsPredictedBNBGlobal[amountsPredictedBNBGlobal.length-1].mul(SLIPPAGE)).div(10000),
                pathToGlobal,
                address(this),
                deadline
            );

            uint amountGlobalBought = amountsGlobal[amountsGlobal.length-1];
            global.approve(address(vaultVested), amountGlobalBought);
            vaultVested.deposit(amountGlobalBought, msg.sender);

            uint amountToMintGlobal = amountGlobalBought.mul(rewardsSetUp.toMintGlobal).div(10000);
            minter.mintNativeTokens(amountToMintGlobal, address(this));
            global.approve(address(vaultVested), amountToMintGlobal);
            vaultVested.deposit(amountToMintGlobal, msg.sender);
        }

        // Swaps BNB to CAKE and sends CAKES to user
        address[] memory pathToCake = pathFinder.findPath(address(wbnb), address(cake));
        uint[] memory amountsPredictedToCake = globalRouter.getAmountsOut(amountToUser, pathToBnb);
        uint[] memory amountsCake = globalRouter.swapExactTokensForTokens(
            amountToUser,
            (amountsPredictedToCake[amountsPredictedToCake.length-1].mul(SLIPPAGE)).div(10000),
            pathToCake,
            address(this),
            block.timestamp
        );

        uint amountCakeSwapped = amountsCake[amountsCake.length-1];
        cake.safeTransfer(msg.sender, amountCakeSwapped);
        emit ProfitPaid(msg.sender, amountCakeSwapped);
    }

    function _depositStakingToken(uint amount) private returns (uint cakeHarvested) {
        uint before = cake.balanceOf(address(this));
        cakeMasterChef.deposit(pid, amount);
        cakeHarvested = cake.balanceOf(address(this)).sub(before);
    }

    function _withdrawStakingToken(uint amount) private returns (uint cakeHarvested) {
        uint before = cake.balanceOf(address(this));
        cakeMasterChef.withdraw(pid, amount);
        cakeHarvested = cake.balanceOf(address(this)).sub(before);
    }

    function _harvest(uint cakeAmount) private {
        uint _before = _rewardsToken.sharesOf(address(this));
        _rewardsToken.deposit(cakeAmount);
        uint amount = _rewardsToken.sharesOf(address(this)).sub(_before);
        if (amount > 0) {
            _notifyRewardAmount(amount);
            emit Harvested(amount);
        }
    }

    function _notifyRewardAmount(uint reward) private updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint remaining = periodFinish.sub(block.timestamp);
            uint leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint _balance = _rewardsToken.sharesOf(address(this));
        require(rewardRate <= _balance.div(rewardsDuration), "reward rate must be in the right range");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    function withdrawUnderlying(uint _amount) external override onlyNonContract {

    }

    function _allowance(IBEP20 _token, address _account) private {
        _token.safeApprove(_account, uint(0));
        _token.safeApprove(_account, uint(~0));
    }

    // SALVAGE PURPOSE ONLY
    // @dev _stakingToken() must not remain balance in this contract. So dev should be able to salvage staking token transferred by mistake.
    function recoverToken(address _token, uint amount) virtual external onlyOwner {
        IBEP20(_token).safeTransfer(owner(), amount);

        emit Recovered(_token, amount);
    }
}