// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
/*

import "../Libraries/SafeBEP20.sol";
import "../Libraries/Math.sol";
import "../Helpers/IMinter.sol";
import "../Helpers/IPathFinder.sol";
import "../Helpers/TokenAddresses.sol";
import "../Modifiers/PausableUpgradeable.sol";
import "../Modifiers/WhitelistUpgradeable.sol";
import "../IRouterV2.sol";
import "./Interfaces/IStrategy.sol";
import "./Externals/IBunnyPoolStrategy.sol";
import './VaultVested.sol';
import './VaultDistribution.sol';
import 'hardhat/console.sol';

contract VaultBunny is IStrategy, PausableUpgradeable, WhitelistUpgradeable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;
    using SafeMath for uint16;

    IBEP20 public bunny;
    IBEP20 public global;
    IBEP20 public wbnb;
    IBunnyPoolStrategy public pool;
    IMinter public minter;
    address public treasury;
    address public keeper;
    VaultDistribution public vaultDistribution;
    VaultVested public vaultVested;
    IRouterV2 public globalRouter;
    IRouterV2 public cakeRouter;
    IPathFinder public pathFinder;
    TokenAddresses public tokenAddresses;

    uint16 public constant MAX_WITHDRAWAL_FEES = 100; // 1%
    uint public constant DUST = 1000;
    uint public constant SLIPPAGE = 9500;
    address public constant GLOBAL_BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    uint public totalShares;
    mapping (address => uint) public _shares;
    mapping (address => uint) public _principal;
    mapping (address => uint) public _depositedAt;

    struct WithdrawalFees {
        uint16 burn;      // % to burn (in Global)
        uint16 team;      // % to devs (in BUSD)
        uint256 interval; // Meanwhile, fees will be apply (timestamp)
    }

    struct Rewards {
        uint16 toUser;       // % to user
        uint16 toOperations; // % to treasury (in BUSD)
        uint16 toBuyGlobal;  // % to keeper as user (in Global)
        uint16 toBuyBNB;     // % to keeper as vault (in BNB)
        uint16 toMintGlobal; // % to mint global multiplier (relation to toBuyGlobal)
    }

    WithdrawalFees public withdrawalFees;
    Rewards public rewards;

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

    constructor(
        address _bunny,
        address _global,
        address _wbnb,
        address _pool,
        address _treasury,
        address _tokenAddresses,
        address _globalRouter,
        address _pathFinder,
        address _vaultDistribution,
        address _vaultVested,
        address _cakeRouter
    ) public {
        bunny = IBEP20(_bunny);
        global = IBEP20(_global);
        wbnb = IBEP20(_wbnb);
        pool = IBunnyPoolStrategy(_pool);
        treasury = _treasury;
        vaultVested = VaultVested(_vaultVested);
        vaultDistribution = VaultDistribution(_vaultDistribution);

        _allowance(bunny, _pool);

        __PausableUpgradeable_init();
        __WhitelistUpgradeable_init();

        setDefaultWithdrawalFees();
        setDefaultRewardFees();

        tokenAddresses = TokenAddresses(_tokenAddresses);
        globalRouter = IRouterV2(_globalRouter);
        cakeRouter = IRouterV2(_cakeRouter);
        pathFinder = IPathFinder(_pathFinder);
    }

    function setMinter(address _minter) external onlyOwner {
        require(IMinter(_minter).isMinter(address(this)) == true, "This vault must be a minter in minter's contract");
        bunny.safeApprove(_minter, 0);
        bunny.safeApprove(_minter, uint(~0));
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
        uint16 _toBuyBNB,
        uint16 _toMintGlobal
    ) public onlyOwner {
        require(_toUser.add(_toOperations).add(_toBuyGlobal).add(_toBuyBNB) == 10000, "Rewards must add up to 100%");

        rewards.toUser = _toUser;
        rewards.toOperations = _toOperations;
        rewards.toBuyGlobal = _toBuyGlobal;
        rewards.toBuyBNB = _toBuyBNB;
        rewards.toMintGlobal = _toMintGlobal;
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
        return totalShares;
    }

    function balance() public view override returns (uint) {
        return pool.balanceOf(address(this));
    }

    function balanceOf(address account) public view override returns(uint) {
        if (totalShares == 0) return 0;
        return balance().mul(sharesOf(account)).div(totalShares);
    }

    function withdrawableBalanceOf(address account) public view override returns (uint) {
        return balanceOf(account);
    }

    function sharesOf(address account) public view override returns (uint) {
        return _shares[account];
    }

    function principalOf(address account) public view override returns (uint) {
        return _principal[account];
    }

    function earned(address account) public view override returns (uint) {
        if (balanceOf(account) >= principalOf(account) + DUST) {
            return balanceOf(account).sub(principalOf(account));
        } else {
            return 0;
        }
    }

    function priceShare() external view override returns(uint) {
        if (totalShares == 0) return 1e18;
        return balance().mul(1e18).div(totalShares);
    }

    function depositedAt(address account) external view override returns (uint) {
        return _depositedAt[account];
    }

    function stakingToken() external view returns (address) {
        return address(bunny);
    }

    function rewardsToken() external view override returns (address) {
        return address(wbnb);
    }

    function deposit(uint _amount) public override onlyNonContract {
        _deposit(_amount, msg.sender);
        _principal[msg.sender] = _principal[msg.sender].add(_amount);
        _depositedAt[msg.sender] = block.timestamp;
    }

    function depositAll() external override onlyNonContract {
        deposit(bunny.balanceOf(msg.sender));
    }

    function withdrawAll() external override onlyNonContract {
        uint amount = balanceOf(msg.sender);
        uint principal = principalOf(msg.sender);

        (uint bunnyHarvested, uint withdrawFromPoolAmount) = _withdrawStakingToken(amount);

        uint profit = withdrawFromPoolAmount > principal ? withdrawFromPoolAmount.sub(principal) : 0;
        uint withdrawAmount = withdrawFromPoolAmount > principal ? withdrawFromPoolAmount.sub(profit) : withdrawFromPoolAmount;

        handleWithdrawalFees(withdrawAmount);
        handleRewards(profit);

        totalShares = totalShares.sub(_shares[msg.sender]);
        delete _shares[msg.sender];
        delete _principal[msg.sender];
        delete _depositedAt[msg.sender];

        _harvest(bunnyHarvested);
    }

    function harvest() external override onlyNonContract {
        (uint bunnyHarvested,) = _withdrawStakingToken(0);
        _harvest(bunnyHarvested);
    }

    function _harvest(uint _bunnyHarvested) private {
        if (_bunnyHarvested > 0) {
            pool.deposit(_bunnyHarvested);
            emit Harvested(_bunnyHarvested);
        }
    }

    function withdraw(uint shares) external override onlyWhitelisted onlyNonContract {
        require(balance() > 0, "Nothing to withdraw");
        uint amount = balance().mul(shares).div(totalShares);

        (uint bunnyHarvested, uint withdrawFromPoolAmount) = _withdrawStakingToken(amount);

        handleWithdrawalFees(withdrawFromPoolAmount);

        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);
        _principal[msg.sender] = _principal[msg.sender].sub(amount);

        _harvest(bunnyHarvested);
    }

    function withdrawUnderlying(uint _amount) external override onlyNonContract {
        require(balance() > 0, "Nothing to withdraw");
        uint amount = Math.min(_amount, _principal[msg.sender]);
        uint shares = Math.min(amount.mul(totalShares).div(balance()), _shares[msg.sender]);

        (uint bunnyHarvested, uint withdrawFromPoolAmount) = _withdrawStakingToken(amount);

        handleWithdrawalFees(withdrawFromPoolAmount);

        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);
        _principal[msg.sender] = _principal[msg.sender].sub(amount);

        _harvest(bunnyHarvested);
    }

    function getReward() external override onlyNonContract {
        uint amount = earned(msg.sender);
        uint shares = Math.min(amount.mul(totalShares).div(balance()), _shares[msg.sender]);

        (uint bunnyHarvested, uint withdrawFromPoolAmount) = _withdrawStakingToken(amount);

        handleRewards(withdrawFromPoolAmount);

        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);
        _cleanupIfDustShares();

        _harvest(bunnyHarvested);
    }

    function handleWithdrawalFees(uint _amount) private {
        if (_amount == 0) {
            emit Withdrawn(msg.sender, _amount, 0);
            return;
        }

        if (_depositedAt[msg.sender].add(withdrawalFees.interval) < block.timestamp) {
            // No withdrawal fees
            bunny.safeTransfer(msg.sender, _amount);
            emit Withdrawn(msg.sender, _amount, 0);
            return;
        }

        uint amountToBurn = _amount.mul(withdrawalFees.burn).div(10000);
        uint amountToTeam = _amount.mul(withdrawalFees.team).div(10000);
        uint amountToUser = _amount.sub(amountToTeam).sub(amountToBurn);

        address[] memory pathToGlobal = pathFinder.findPath(
            tokenAddresses.findByName(tokenAddresses.BNB()),
            tokenAddresses.findByName(tokenAddresses.GLOBAL())
        );

        address[] memory pathToBusd = pathFinder.findPath(
            tokenAddresses.findByName(tokenAddresses.BUNNY()),
            tokenAddresses.findByName(tokenAddresses.BUSD())
        );

        address[] memory pathToBNB = pathFinder.findPath(
            tokenAddresses.findByName(tokenAddresses.BUNNY()),
            tokenAddresses.findByName(tokenAddresses.BNB())
        );

        if (amountToBurn < DUST) {
            amountToUser = amountToUser.add(amountToBurn);
        } else {
            uint[] memory amountsToBNBPredicted = cakeRouter.getAmountsOut(amountToBurn, pathToBNB);
            uint[] memory amountsBNB = cakeRouter.swapExactTokensForTokens(
                amountToBurn,
                (amountsToBNBPredicted[amountsToBNBPredicted.length-1].mul(SLIPPAGE)).div(10000),
                pathToBNB,
                address(this),
                block.timestamp.add(2 hours)
            );

            uint amountInBNB = amountsBNB[amountsBNB.length-1];

            uint[] memory amountsToGlobalPredicted = globalRouter.getAmountsOut(amountInBNB, pathToGlobal);
            globalRouter.swapExactTokensForTokens(
                amountInBNB,
                (amountsToGlobalPredicted[amountsToGlobalPredicted.length-1].mul(SLIPPAGE)).div(10000),
                pathToGlobal,
                GLOBAL_BURN_ADDRESS,
                block.timestamp.add(2 hours)
            );
        }

        // Swaps BUNNY for BNB and BNB for BUSD and sends BUSD to treasury.
        if (amountToTeam < DUST) {
            amountToUser = amountToUser.add(amountToTeam);
        } else {
            uint[] memory amountsToBNBPredicted = cakeRouter.getAmountsOut(amountToTeam, pathToBNB);
            uint[] memory amountsBNB = cakeRouter.swapExactTokensForTokens(
                amountToTeam,
                (amountsToBNBPredicted[amountsToBNBPredicted.length-1].mul(SLIPPAGE)).div(10000),
                pathToBNB,
                address(this),
                block.timestamp.add(2 hours)
            );

            uint amountInBNB = amountsBNB[amountsBNB.length-1];

            uint[] memory amountsPredicted = globalRouter.getAmountsOut(amountInBNB, pathToBusd);
            globalRouter.swapExactTokensForTokens(
                amountInBNB,
                (amountsPredicted[amountsPredicted.length-1].mul(SLIPPAGE)).div(10000),
                pathToBusd,
                treasury,
                block.timestamp.add(2 hours)
            );
        }

        // Sends BUNNY to user.
        bunny.safeTransfer(msg.sender, amountToUser);
        emit Withdrawn(msg.sender, amountToUser, 0);
    }

    function handleRewards(uint _amount) private {
        if (_amount < DUST) {
            return; // No rewards
        }

        address[] memory pathToBNB = pathFinder.findPath(
            tokenAddresses.findByName(tokenAddresses.BUNNY()),
            tokenAddresses.findByName(tokenAddresses.BNB())
        );

        // Swaps BUNNY to BNB
        uint[] memory amountsToBNBPredicted = cakeRouter.getAmountsOut(_amount, pathToBNB);
        uint[] memory amountsBNB = cakeRouter.swapExactTokensForTokens(
            _amount,
            (amountsToBNBPredicted[amountsToBNBPredicted.length-1].mul(SLIPPAGE)).div(10000),
            pathToBNB,
            address(this),
            block.timestamp.add(2 hours)
        );

        uint amountInBNB = amountsBNB[amountsBNB.length-1];

        uint amountToUser = amountInBNB.mul(rewards.toUser).div(10000);
        uint amountToOperations = amountInBNB.mul(rewards.toOperations).div(10000);
        uint amountToBuyGlobal = amountInBNB.mul(rewards.toBuyGlobal).div(10000);
        uint amountToBuyBNB = amountInBNB.mul(rewards.toBuyBNB).div(10000);

        address[] memory pathToGlobal = pathFinder.findPath(
            tokenAddresses.findByName(tokenAddresses.BNB()),
            tokenAddresses.findByName(tokenAddresses.GLOBAL())
        );

        address[] memory pathToBusd = pathFinder.findPath(
            tokenAddresses.findByName(tokenAddresses.BNB()),
            tokenAddresses.findByName(tokenAddresses.BUSD())
        );

        // Swaps BNB for BUSD and sends BUSD to treasury.
        if (amountToOperations < DUST) {
            amountToUser = amountToUser.add(amountToOperations);
        } else {
            uint[] memory amountsPredicted = globalRouter.getAmountsOut(amountToOperations, pathToBusd);
            globalRouter.swapExactTokensForTokens(
                amountToOperations,
                (amountsPredicted[amountsPredicted.length-1].mul(SLIPPAGE)).div(10000),
                pathToBusd,
                treasury,
                block.timestamp.add(2 hours)
            );
        }

        // Swaps BNB and sends BNB to distribution vault
        if (amountToBuyBNB < DUST) {
            amountToUser = amountToUser.add(amountToBuyBNB);
        } else {
            wbnb.approve(address(vaultDistribution), amountToBuyBNB);
            vaultDistribution.deposit(amountToBuyBNB);
        }

        // Swaps BNB for GLOBAL and sends GLOBAL to vested vault (as user)
        // Mints GLOBAL and sends GLOBAL to vested vault (as user)
        if (amountToBuyGlobal < DUST) {
            amountToUser = amountToUser.add(amountToBuyGlobal);
        } else {
            uint[] memory amountsPredicted = globalRouter.getAmountsOut(amountToBuyGlobal, pathToGlobal);
            uint[] memory amounts = globalRouter.swapExactTokensForTokens(
                amountToBuyGlobal,
                (amountsPredicted[amountsPredicted.length-1].mul(SLIPPAGE)).div(10000),
                pathToGlobal,
                address(this),
                block.timestamp.add(2 hours)
            );

            uint amountGlobalBought = amounts[amounts.length-1];
            global.approve(address(vaultVested), amountGlobalBought);
            vaultVested.deposit(amountGlobalBought, msg.sender);

            uint amountToMintGlobal = amountGlobalBought.mul(rewards.toMintGlobal).div(10000);
            minter.mintNativeTokens(amountToMintGlobal, address(this));
            global.approve(address(vaultVested), amountToMintGlobal);
            vaultVested.deposit(amountToMintGlobal, msg.sender);
        }

        // Sends BNB to the user.
        wbnb.safeTransfer(msg.sender, amountToUser);
        emit ProfitPaid(msg.sender, amountToUser);
    }

    function _deposit(uint _amount, address _to) private notPaused {
        bunny.safeTransferFrom(msg.sender, address(this), _amount);

        uint shares = totalShares == 0 ? _amount : (_amount.mul(totalShares)).div(balance());
        totalShares = totalShares.add(shares);
        _shares[_to] = _shares[_to].add(shares);

        uint bunnyHarvested = _depositStakingToken(_amount);
        emit Deposited(_to, _amount);

        _harvest(bunnyHarvested);
    }

    function _depositStakingToken(uint amount) private returns(uint bunnyHarvested) {
        uint before = bunny.balanceOf(address(this));
        pool.deposit(amount);
        bunnyHarvested = bunny.balanceOf(address(this)).add(amount).sub(before);
    }

    // Bunny pool could discount withdrawal fees
    function _withdrawStakingToken(uint _amount) private returns(uint bunnyHarvested, uint amount) {
        uint before = bunny.balanceOf(address(this));
        pool.withdraw(_amount);
        uint amountAfter = bunny.balanceOf(address(this));

        // Discount pool withdrawal fees to user's amount
        if (amountAfter < before.add(_amount) ) {
            amount = amountAfter.sub(before);
            bunnyHarvested = 0;
        } else {
            amount = _amount;
        }

        bunnyHarvested = amountAfter.sub(_amount).sub(before);
    }

    function _cleanupIfDustShares() private {
        uint shares = _shares[msg.sender];
        if (shares > 0 && shares < DUST) {
            totalShares = totalShares.sub(shares);
            delete _shares[msg.sender];
        }
    }

    function _allowance(IBEP20 _token, address _account) private {
        _token.safeApprove(_account, uint(0));
        _token.safeApprove(_account, uint(~0));
    }

    // SALVAGE PURPOSE ONLY
    // @dev _stakingToken(token) must not remain balance in this contract. So dev should be able to salvage staking token transferred by mistake.
    function recoverToken(address _token, uint amount) virtual external onlyOwner {
        IBEP20(_token).safeTransfer(owner(), amount);

        emit Recovered(_token, amount);
    }
}*/