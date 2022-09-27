// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../Libraries/SafeBEP20.sol";
import "../Modifiers/Ownable.sol";
import "../Modifiers/DepositoryRestriction.sol";
import './Interfaces/IDistributable.sol';

contract VaultDistribution is Ownable, DepositoryRestriction {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint;

    IBEP20 public distributionToken; // BNB
    IBEP20 public beneficiaryToken;  // Global
    address[] public beneficiaries;
    uint public minTokenAmountToDistribute;
    uint public distributionPercentage;
    uint256 public distributionInterval;
    uint256 public lastDistributedEvent;

    event Deposited(address depository, uint amount);
    event Distributed(uint distributedAmount, uint numberOfBeneficiaries);

    modifier distributeTokens() {
        _;
        _distribute();
    }

    constructor(address _distributionToken, address _beneficiaryToken) public {
        distributionToken = IBEP20(_distributionToken);
        beneficiaryToken = IBEP20(_beneficiaryToken);
        minTokenAmountToDistribute = 1e18; // 1 BEP20 Token
        distributionPercentage = 10000;    // 100%
        distributionInterval = 12 hours;
        lastDistributedEvent = block.timestamp;
    }

    function getBeneficiariesLength() public view returns(uint) {
        return beneficiaries.length;
    }

    function setMinTokenAmountToDistribute(uint _newAmount) external onlyOwner {
        require(_newAmount >= 0, "Min token amount to distribute must be greater than 0");
        minTokenAmountToDistribute = _newAmount;
    }

    function setDistributionPercentage(uint16 _newPercentage) external onlyOwner {
        require(_newPercentage <= 10000, "Distribution percentage must not be greater than 100%");
        require(_newPercentage > 0, "Distribution percentage must not be smaller than 0%");
        distributionPercentage = _newPercentage;
    }

    function setDistributionInterval(uint _distributionInterval) external onlyOwner {
        distributionInterval = _distributionInterval;
    }

    function addBeneficiary(address _beneficiary) external onlyOwner {
        for (uint i = 0; i < beneficiaries.length; i++) {
            if (beneficiaries[i] == _beneficiary) {
                // Beneficiary exists already.
                return;
            }
        }

        // It checks beneficiary has triggerDistribute method before to add it.
        IDistributable(_beneficiary).triggerDistribute(0);
        beneficiaries.push(_beneficiary);
    }

    function removeBeneficiary(address _beneficiary) external onlyOwner {
        for (uint i = 0; i < beneficiaries.length; i++) {
            if (beneficiaries[i] == _beneficiary) {
                for (uint j = i; j<beneficiaries.length-1; j++)
                {
                    beneficiaries[j] = beneficiaries[j+1];
                }
                beneficiaries.pop();
            }
        }
    }

    function isBeneficiary(address _beneficiary) external view returns (bool) {
        for (uint i = 0; i < beneficiaries.length; i++) {
            if (beneficiaries[i] == _beneficiary) {
                return true;
            }
        }

        return false;
    }

    function deposit(uint _amount) public onlyDepositories distributeTokens {
        distributionToken.transferFrom(msg.sender, address(this), _amount);

        emit Deposited(msg.sender, _amount);
    }

    function _distribute() private {
        uint currentDistributionTokenAmount = distributionToken.balanceOf(address(this));

        // Too early to distribute.
        if (lastDistributedEvent.add(distributionInterval) > block.timestamp) {
            return;
        }

        if (currentDistributionTokenAmount < minTokenAmountToDistribute) {
            // Nothing to distribute.
            return;
        }

        uint totalDistributionTokenAmountToDistribute = currentDistributionTokenAmount.mul(distributionPercentage).div(10000);

        uint totalBeneficiaryTokens = 0;
        for (uint i = 0; i < beneficiaries.length; i++) {
            totalBeneficiaryTokens = totalBeneficiaryTokens.add(IDistributable(beneficiaries[i]).balance());
        }

        for (uint i = 0; i < beneficiaries.length; i++) {
            uint beneficiaryDistributionPercentage = IDistributable(beneficiaries[i]).balance().mul(100).div(totalBeneficiaryTokens);
            uint amountForBeneficiary = totalDistributionTokenAmountToDistribute.mul(beneficiaryDistributionPercentage).div(100);
            if (amountForBeneficiary > 0) {
                distributionToken.safeTransfer(beneficiaries[i], amountForBeneficiary);
                IDistributable(beneficiaries[i]).triggerDistribute(amountForBeneficiary);
            }
        }

        lastDistributedEvent = block.timestamp;

        emit Distributed(totalDistributionTokenAmountToDistribute, beneficiaries.length);
    }
}