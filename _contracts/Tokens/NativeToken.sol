// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import '../Modifiers/Ownable.sol';
import '../Modifiers/DevPower.sol';
import '../Libraries/SafeMath.sol';
import '../Libraries/Address.sol';
import './BEP20.sol';
import './IBEP20.sol';

contract NativeToken is BEP20{

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    mapping (address => bool) private blacklisted;
    bool tradingOpen = false;
    uint256 launchTime;
    uint16 public constant MAX_ANTIWHALE = 1500;
    mapping(address => bool) private _antiWhaleWhiteList;
    uint16 public antiWhalePercent = MAX_ANTIWHALE;
    address private _mainDevWallet;

    event MaxTransferAntiWhale(address indexed devPower, uint256 oldAntiWhalePercent, uint256 newAntiWhalePercent);

    constructor() public BEP20('Global', 'GLB'){
        _antiWhaleWhiteList[msg.sender] = true;
        _antiWhaleWhiteList[address(this)] = true;
        _antiWhaleWhiteList[BURN_ADDRESS] = true;
        _antiWhaleWhiteList[address(0)] = true;
    }

    function GetIfExcludedFromAntiWhale(address addr) public view returns (bool) {
        return _antiWhaleWhiteList[addr];
    }

    function setExcludedFromAntiWhale(address addr, bool _excluded) public onlyDevPower {
        _antiWhaleWhiteList[addr] = _excluded;
    }

    function maxTokensTransferAmountAntiWhaleMethod() public view returns (uint256) {
        return totalSupply().mul(antiWhalePercent).div(10000);
    }

    function updateMaxTransferAntiWhale(uint16 _newAntiWhalePercent) public onlyDevPower {
        require(_newAntiWhalePercent <= MAX_ANTIWHALE, "[!] Antiwhale method triggered. You are trying to set a % which is too high Check MAX_ANTIWHALE in the SC.");
        emit MaxTransferAntiWhale(msg.sender, antiWhalePercent, _newAntiWhalePercent);
        antiWhalePercent = _newAntiWhalePercent;
    }

    modifier antiWhale(address origen, address destinataria, uint256 q) {
        if (maxTokensTransferAmountAntiWhaleMethod() > 0) {
            if (_antiWhaleWhiteList[origen] == false && _antiWhaleWhiteList[destinataria] == false)
            {
                require(q <= maxTokensTransferAmountAntiWhaleMethod(), "[!] Antiwhale method triggered. You are trying to transfer too many tokens. Calm down and don't panic sell bro.");
            }
        }
        _;
    }

    function openTrading() external onlyOwner() {
        tradingOpen = true;
        launchTime = block.timestamp;
    }

    function closeTrading() external onlyOwner() {
        tradingOpen = false;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override antiWhale(sender, recipient, amount) {
        require(!blacklisted[sender], "You have no power here!");
        require(!blacklisted[recipient], "You have no power here!");
        if (block.timestamp == launchTime) {
            blacklisted[recipient] = true;
        }
        require(tradingOpen || msg.sender == owner(),"The market is closed");
        super._transfer(sender, recipient, amount);
    }

    function mints(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
        _moveDelegates(address(0), _delegates[_to], _amount);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    /// @dev A record of each accounts delegate
    mapping (address => address) internal _delegates;

    /// @dev A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @dev A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @dev The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @dev The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @dev of states for signing / validating signatures
    mapping (address => uint) public nonces;

    /// @dev An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @dev An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /**
     * @dev Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator) external view returns (address)
    {
        return _delegates[delegator];
    }

    /**
     * @dev votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @dev Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint nonce,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
    external
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "GLOBAL::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "GLOBAL::delegateBySig: invalid nonce");
        require(now <= expiry, "GLOBAL::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account)
    external
    view
    returns (uint256)
    {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber)
    external
    view
    returns (uint256)
    {
        require(blockNumber < block.number, "GLOBAL::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee)
    internal
    {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator); // balance of underlying NativeTokens (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    )
    internal
    {
        uint32 blockNumber = safe32(block.number, "GLOBAL::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function isBlacklisted(address account) public view returns (bool) {
        return blacklisted[account];
    }

    function addBlacklisted(address account) external onlyOwner() {
        require(!blacklisted[account], "Account is already blacklisted");
        blacklisted[account] = true;
    }

    function removeBlacklisted(address account) external onlyOwner() {
        require(blacklisted[account], "Account is not blacklisted");
        blacklisted[account] = false;
    }
}