const { expect } = require("chai");
const { bep20Amount } = require("../../helpers/utils.js");
const {
  deploy,
  getNativeToken,
  getBnb,
  getVaultDistribution,
} = require("../../helpers/vaultDistributionDeploy");

const MIN_BNB_AMOUNT_TO_DISTRIBUTE = bep20Amount(6);

beforeEach(async function () {
  await deploy();
  const INITIAL_SUPPLY = bep20Amount(100);
  await getBnb().mint(INITIAL_SUPPLY);
  await getNativeToken().mint(INITIAL_SUPPLY);
});

describe("VaultDistribution: Distribute", function () {
  it("Distributes BNBs between Global's depositories equitably", async function () {
    const bnbAmountPerDepositary = bep20Amount(5);
    const globalAmountBeneficiary1 = bep20Amount(5);
    const globalAmountBeneficiary2 = bep20Amount(3);
    const globalAmountBeneficiary3 = bep20Amount(2);

    // Set up globals and bnb between depositories and beneficiaries.
    await getBnb().connect(owner).transfer(depositary1.address, bnbAmountPerDepositary);
    await getBnb().connect(owner).transfer(depositary2.address, bnbAmountPerDepositary);
    await getNativeToken().connect(owner).transfer(beneficiary1.address, globalAmountBeneficiary1);
    await getNativeToken().connect(owner).transfer(beneficiary2.address, globalAmountBeneficiary2);
    await getNativeToken().connect(owner).transfer(beneficiary3.address, globalAmountBeneficiary3);

    // Set up vault preferences
    await getVaultDistribution().connect(devPower).setMinTokenAmountToDistribute(MIN_BNB_AMOUNT_TO_DISTRIBUTE);
    await getBnb().connect(depositary1).approve(getVaultDistribution().address, bnbAmountPerDepositary);
    await getBnb().connect(depositary2).approve(getVaultDistribution().address, bnbAmountPerDepositary);
    await getVaultDistribution().connect(devPower).setDepositary(depositary1.address, true);
    await getVaultDistribution().connect(devPower).setDepositary(depositary2.address, true);
    await getVaultDistribution().connect(devPower).addBeneficiary(beneficiary1.address);
    await getVaultDistribution().connect(devPower).addBeneficiary(beneficiary2.address);
    await getVaultDistribution().connect(devPower).addBeneficiary(beneficiary3.address);
    expect(await getBnb().balanceOf(getVaultDistribution().address)).equal(0);

    // Starting test.
    // First deposit of 5bnb does not trigger distribution process because of the minimum configured is 6bnb
    await getVaultDistribution().connect(depositary1).deposit(bnbAmountPerDepositary);
    expect(await getBnb().balanceOf(getVaultDistribution().address)).equal(bnbAmountPerDepositary);
    expect(await getBnb().balanceOf(beneficiary1.address)).equal(0);
    expect(await getBnb().balanceOf(beneficiary2.address)).equal(0);
    expect(await getBnb().balanceOf(beneficiary3.address)).equal(0);

    // Second deposit of 5bnb make vault to have 10bnb so it runs the distribution process between 3 beneficiaries.
    await expect(getVaultDistribution().connect(depositary2).deposit(bnbAmountPerDepositary))
        .to.emit(getVaultDistribution(), 'Distributed')
        .withArgs(bnbAmountPerDepositary.mul(2), 3);

    // Because vault have 10bnb and there are 10globals between beneficiaries so distribution is gonna be 1bnb per global
    const expectedBnbAmountForBeneficiary1 = globalAmountBeneficiary1;
    const expectedBnbAmountForBeneficiary2 = globalAmountBeneficiary2;
    const expectedBnbAmountForBeneficiary3 = globalAmountBeneficiary3;

    expect(await getBnb().balanceOf(beneficiary1.address)).equal(expectedBnbAmountForBeneficiary1);
    expect(await getBnb().balanceOf(beneficiary2.address)).equal(expectedBnbAmountForBeneficiary2);
    expect(await getBnb().balanceOf(beneficiary3.address)).equal(expectedBnbAmountForBeneficiary3);
    expect(await getBnb().balanceOf(getVaultDistribution().address)).equal(0);
  });
});