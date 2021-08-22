// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./SafeBEP20.sol";
import "./Math.sol";
import "./IGlobalMasterChef.sol";
import "./IDistributable.sol";
import "./VaultLocked.sol";


contract VaultStaked is IDistributable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;
    using SafeMath for uint16;

    IBEP20 private global;
    IBEP20 private bnb;
    IGlobalMasterChef private globalMasterChef;
    VaultLocked private vaultLocked;

    uint private constant DUST = 1000;

    uint256 public pid;
    uint public minTokenAmountToDistribute;
    address[] public users;
    mapping (address => uint) private principal;
    mapping (address => uint) private depositedAt;
    mapping (address => uint) private bnbEarned;
    uint public totalSupply;

    event Deposited(address indexed _user, uint _amount);
    event Withdrawn(address indexed _user, uint _amount);
    event RewardPaid(address indexed _user, uint _amount);

    constructor(
        address _global,
        address _bnb,
        address _globalMasterChef
    ) public {
        // Pid del vault.
        pid = 1;

        // Li passem el address de global
        global = IBEP20(_global);

        // Li passem el address de bnb
        bnb = IBEP20(_bnb);

        // Li passem el address del masterchef a on es depositaràn els GLOBALs
        globalMasterChef = IGlobalMasterChef(_globalMasterChef);

        // Es repartirà 1bnb com a mínim. En cas contrari, no repartirem.
        minTokenAmountToDistribute = 1e18; // 1 BEP20 Token

        //
        _allowance(global, _globalMasterChef);
    }

    function triggerDistribute() external override {
        _distribute();
    }

    function balance() public view returns (uint amount) {
        (amount,) = globalMasterChef.userInfo(pid, address(this));
    }

    function balanceOf(address _account) public view returns(uint) {
        if (totalSupply == 0) return 0;
        return principalOf(_account);
    }

    function principalOf(address _account) public view returns (uint) {
        return principal[_account];
    }

    function earned(address _account) public view returns (uint) {
        if (principalOf(_account) > 0) {
            return bnbEarned[_account];
        } else {
            return 0;
        }
    }

    function rewardsToken() external view returns (address) {
        return address(bnb);
    }

    // Deposit globals.
    function deposit(uint _amount) public {
        global.safeTransferFrom(msg.sender, address(this), _amount);

        globalMasterChef.enterStaking(_amount);

        if (depositedAt[msg.sender] == 0) {
            users.push(msg.sender);
        }

        depositedAt[msg.sender] = block.timestamp;
        totalSupply = totalSupply.add(_amount);
        principal[msg.sender] = principal[msg.sender].add(_amount);

        if (earned(msg.sender) == 0) {
            bnbEarned[msg.sender] = 0;
        }

        emit Deposited(msg.sender, _amount);
    }

    // Withdraw all only
    function withdraw() external {
        uint amount = balanceOf(msg.sender);
        uint earnedU = earned(msg.sender);

        globalMasterChef.leaveStaking(amount);
        handleRewards(earnedU);
        totalSupply = totalSupply.sub(amount);
        delete depositedAt[msg.sender];
        _deleteUser(msg.sender);
        delete principal[msg.sender];
        delete bnbEarned[msg.sender];
    }

    function getReward() external {
        uint earnedU = earned(msg.sender);
        handleRewards(earnedU);
        delete bnbEarned[msg.sender];
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
        for (uint8 i = 0; i < users.length; i++) {
            if (users[i] == _account) {
                delete users[i];
            }
        }
    }

    function _distribute() private {
        uint currentBNBAmount = bnb.balanceOf(address(this));

        if (currentBNBAmount < minTokenAmountToDistribute) {
            // Nothing to distribute.
            return;
        }

        for (uint i=0; i < users.length; i++) {
            uint userPercentage = principalOf(users[i]).mul(100).div(totalSupply);
            uint bnbToUser = currentBNBAmount.mul(userPercentage).div(100);

            bnbEarned[users[i]] = bnbEarned[users[i]].add(bnbToUser);
        }

        emit Distributed(currentBNBAmount);
    }
}