// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./SafeBEP20.sol";
import "./Math.sol";
import "./IStrategy.sol";
import "./ICakeMasterChef.sol";
import "./PausableUpgradeable.sol";
import "./WhitelistUpgradeable.sol";
import "./IMinter.sol";
import "./IRouterV2.sol";
import "./IRouterPathFinder.sol";
import "./TokenAddresses.sol";

contract VaultCake is IStrategy, PausableUpgradeable, WhitelistUpgradeable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;
    using SafeMath for uint16;

    IBEP20 private cake;
    IBEP20 private global;
    ICakeMasterChef private cakeMasterChef;
    IMinter private minter;
    address private treasury;
    address private keeper;
    IRouterV2 private router;
    IRouterPathFinder private routerPathFinder;
    TokenAddresses private tokenAddresses;

    uint16 public constant MAX_WITHDRAWAL_FEES = 100; // 1%
    uint private constant DUST = 1000;
    address private constant GLOBAL_BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    uint256 public pid;
    uint public totalShares;
    mapping (address => uint) private _shares;
    mapping (address => uint) private _principal;
    mapping (address => uint) private _depositedAt;

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
        address _cake,
        address _global,
        address _cakeMasterChef,
        address _treasury,
        address _tokenAddresses,
        address _router,
        address _routerPathFinder,
        address _keeper
    ) public {
        pid = 0;
        cake = IBEP20(_cake);
        global = IBEP20(_global);
        cakeMasterChef = ICakeMasterChef(_cakeMasterChef);
        treasury = _treasury;
        keeper = _keeper;

        cake.safeApprove(_cakeMasterChef, uint(~0));

        __PausableUpgradeable_init();
        __WhitelistUpgradeable_init();

        setDefaultWithdrawalFees();
        setDefaultRewardFees();

        tokenAddresses = TokenAddresses(_tokenAddresses);
        router = IRouterV2(_router);
        routerPathFinder = IRouterPathFinder(_routerPathFinder);
    }

    // init minter
    function setMinter(address _minter) external {
        require(IMinter(_minter).isMinter(address(this)) == true, "This vault must be a minter in minter's contract");
        cake.safeApprove(_minter, 0);
        cake.safeApprove(_minter, uint(~0));
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

    // TODO: remove it, used for test only
    function isVaultMintable() external view returns (bool) {
        return address(minter) != address(0) && minter.isMinter(address(this));
    }

    function totalSupply() external view override returns (uint) {
        return totalShares;
    }

    function balance() public view override returns (uint amount) {
        (amount,) = cakeMasterChef.userInfo(pid, address(this));
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

    function rewardsToken() external view override returns (address) {
        return address(cake);
    }

    function deposit(uint _amount) public override onlyNonContract {
        _deposit(_amount, msg.sender);

        if (isWhitelist(msg.sender) == false) {
            _principal[msg.sender] = _principal[msg.sender].add(_amount);
            _depositedAt[msg.sender] = block.timestamp;
        }
    }

    function depositAll() external override onlyNonContract {
        deposit(cake.balanceOf(msg.sender));
    }

    function withdrawAll() external override onlyNonContract {
        uint amount = balanceOf(msg.sender);
        uint principal = principalOf(msg.sender);
        uint profit = amount > principal ? amount.sub(principal) : 0;

        uint cakeHarvested = _withdrawStakingToken(amount);

        handleWithdrawalFees(principal);
        handleRewards(profit);

        totalShares = totalShares.sub(_shares[msg.sender]);
        delete _shares[msg.sender];
        delete _principal[msg.sender];
        delete _depositedAt[msg.sender];

        _harvest(cakeHarvested);
    }

    function harvest() external override onlyNonContract {
        uint cakeHarvested = _withdrawStakingToken(0);
        _harvest(cakeHarvested);
    }

    function withdraw(uint shares) external override onlyWhitelisted onlyNonContract {
        uint amount = balance().mul(shares).div(totalShares);

        uint cakeHarvested = _withdrawStakingToken(amount);

        handleWithdrawalFees(amount);

        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);

        _harvest(cakeHarvested);
    }

    function withdrawUnderlying(uint _amount) external override onlyNonContract {
        uint amount = Math.min(_amount, _principal[msg.sender]);
        uint shares = Math.min(amount.mul(totalShares).div(balance()), _shares[msg.sender]);

        uint cakeHarvested = _withdrawStakingToken(amount);

        handleWithdrawalFees(amount);

        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);
        _principal[msg.sender] = _principal[msg.sender].sub(amount);

        _harvest(cakeHarvested);
    }

    function getReward() external override onlyNonContract {
        uint amount = earned(msg.sender);
        uint shares = Math.min(amount.mul(totalShares).div(balance()), _shares[msg.sender]);

        uint cakeHarvested = _withdrawStakingToken(amount);

        handleRewards(amount);

        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);
        _cleanupIfDustShares();

        _harvest(cakeHarvested);
    }

    function handleWithdrawalFees(uint _amount) private {
        if (_depositedAt[msg.sender].add(withdrawalFees.interval) < block.timestamp) {
            // No withdrawal fees
            cake.safeTransfer(msg.sender, _amount);
            emit Withdrawn(msg.sender, _amount, 0);
            return;
        }

        uint deadline = block.timestamp.add(2 hours);
        uint amountToBurn = _amount.mul(withdrawalFees.burn).div(10000);
        uint amountToTeam = _amount.mul(withdrawalFees.team).div(10000);
        uint amountToUser = _amount.sub(amountToTeam).sub(amountToBurn);

        address[] memory pathToGlobal = routerPathFinder.findPath(
            tokenAddresses.findByName(tokenAddresses.CAKE()),
            tokenAddresses.findByName(tokenAddresses.GLOBAL())
        );

        address[] memory pathToBusd = routerPathFinder.findPath(
            tokenAddresses.findByName(tokenAddresses.CAKE()),
            tokenAddresses.findByName(tokenAddresses.BUSD())
        );

        if (amountToBurn < DUST) {
            amountToUser = amountToUser.add(amountToBurn);
        } else {
            router.swapExactTokensForTokens(amountToBurn, 0, pathToGlobal, GLOBAL_BURN_ADDRESS, deadline);
        }

        if (amountToTeam < DUST) {
            amountToUser = amountToUser.add(amountToTeam);
        } else {
            router.swapExactTokensForTokens(amountToTeam, 0, pathToBusd, treasury, deadline);
        }

        cake.safeTransfer(msg.sender, amountToUser);
        emit Withdrawn(msg.sender, amountToUser, 0);
    }

    function handleRewards(uint _amount) private {
        if (_amount < DUST) {
            return; // No rewards
        }

        uint deadline = block.timestamp.add(2 hours);
        uint amountToUser = _amount.mul(rewards.toUser).div(10000);
        uint amountToOperations = _amount.mul(rewards.toOperations).div(10000);
        uint amountToBuyGlobal = _amount.mul(rewards.toBuyGlobal).div(10000);
        uint amountToBuyBNB = _amount.mul(rewards.toBuyBNB).div(10000);

        address[] memory pathToGlobal = routerPathFinder.findPath(
            tokenAddresses.findByName(tokenAddresses.CAKE()),
            tokenAddresses.findByName(tokenAddresses.GLOBAL())
        );

        address[] memory pathToBusd = routerPathFinder.findPath(
            tokenAddresses.findByName(tokenAddresses.CAKE()),
            tokenAddresses.findByName(tokenAddresses.BUSD())
        );

        address[] memory pathToBnb = routerPathFinder.findPath(
            tokenAddresses.findByName(tokenAddresses.CAKE()),
            tokenAddresses.findByName(tokenAddresses.BNB())
        );

        if (amountToOperations < DUST) {
            amountToUser = amountToUser.add(amountToOperations);
        } else {
            router.swapExactTokensForTokens(amountToOperations, 0, pathToBusd, treasury, deadline);
        }

        if (amountToBuyBNB < DUST) {
            amountToUser = amountToUser.add(amountToBuyBNB);
        } else {
            router.swapExactTokensForTokens(amountToBuyBNB, 0, pathToBnb, keeper, deadline);
        }

        if (amountToBuyGlobal < DUST) {
            amountToUser = amountToUser.add(amountToBuyGlobal);
        } else {
            uint beforeSwap = global.balanceOf(address(this));
            router.swapExactTokensForTokens(amountToBuyGlobal, 0, pathToGlobal, address(this), deadline);
            uint amountGlobalBought = global.balanceOf(address(this)).sub(beforeSwap);

            global.safeTransfer(keeper, amountGlobalBought); // To keeper as cake vault

            uint amountToMintGlobal = amountGlobalBought.mul(rewards.toMintGlobal).div(10000);
            uint beforeMint = global.balanceOf(address(this));
            minter.mintNativeTokens(amountToMintGlobal);
            uint amountGlobalMinted = global.balanceOf(address(this)).sub(beforeMint);
            global.safeTransfer(keeper, amountGlobalMinted); // TODO to keeper as user and not as cake vault
        }

        cake.safeTransfer(msg.sender, amountToUser);
        emit ProfitPaid(msg.sender, amountToUser);
    }

    function _depositStakingToken(uint amount) private returns(uint cakeHarvested) {
        uint before = cake.balanceOf(address(this));
        cakeMasterChef.enterStaking(amount);
        cakeHarvested = cake.balanceOf(address(this)).add(amount).sub(before);
    }

    function _withdrawStakingToken(uint amount) private returns(uint cakeHarvested) {
        uint before = cake.balanceOf(address(this));
        cakeMasterChef.leaveStaking(amount);
        cakeHarvested = cake.balanceOf(address(this)).sub(amount).sub(before);
    }

    function _harvest(uint cakeAmount) private {
        if (cakeAmount > 0) {
            emit Harvested(cakeAmount);
            cakeMasterChef.enterStaking(cakeAmount);
        }
    }

    function _deposit(uint _amount, address _to) private notPaused {
        cake.safeTransferFrom(msg.sender, address(this), _amount);

        uint shares = totalShares == 0 ? _amount : (_amount.mul(totalShares)).div(balance());
        totalShares = totalShares.add(shares);
        _shares[_to] = _shares[_to].add(shares);

        uint cakeHarvested = _depositStakingToken(_amount);
        emit Deposited(msg.sender, _amount);

        _harvest(cakeHarvested);
    }

    function _cleanupIfDustShares() private {
        uint shares = _shares[msg.sender];
        if (shares > 0 && shares < DUST) {
            totalShares = totalShares.sub(shares);
            delete _shares[msg.sender];
        }
    }

    // SALVAGE PURPOSE ONLY
    // @dev _stakingToken(CAKE) must not remain balance in this contract. So dev should be able to salvage staking token transferred by mistake.
    function recoverToken(address _token, uint amount) virtual external onlyOwner {
        IBEP20(_token).safeTransfer(owner(), amount);

        emit Recovered(_token, amount);
    }
}