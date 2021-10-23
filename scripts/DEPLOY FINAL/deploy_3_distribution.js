const hre = require("hardhat");
require("@nomiclabs/hardhat-ethers");

const {
    GLOBAL_TOKEN_ADDRESS,
    WETH_ADDRESS,
    MASTERCHEF_ADDRESS
} = require("addresses.js");

const {
    deployVaultDistribution,
} = require("../../test/helpers/singleDeploys.js");
const { timestampNHours, timestampNDays, bep20Amount } = require("../test/helpers/utils.js");

const VAULT_DISTRIBUTION_MIN_BNB_TO_DISTRIBUTE = bep20Amount(1); // 1 BNB
const VAULT_DISTRIBUTION_DISTRIBUTE_PERCENTAGE = 10000; // 100%
const VAULT_DISTRIBUTION_DISTRIBUTE_INTERVAL = timestampNHours(12); // 12h
const VAULT_LOCKED_DISTRIBUTE_GLOBAL_INTERVAL = timestampNHours(12); // 12h, Hours to distribute Globals from last distribution event.

let CURRENT_BLOCK;
let vaultDistribution;

async function main() {
    console.log("Starting deploy");
    console.log("You do not need dependencies for it");

    [deployer] = await hre.ethers.getSigners();

    CURRENT_BLOCK = await ethers.provider.getBlockNumber();
    console.log("Current block is:", CURRENT_BLOCK);

    // Start
    vaultDistribution = await deployVaultDistribution(WETH_ADDRESS, GLOBAL_TOKEN_ADDRESS);
    console.log("Vault distribution deployed to:", vaultDistribution.address);

    // Verify
    await hre.run("verify:verify", {
        address: vaultDistribution.address,
        constructorArguments: [
            GLOBAL_TOKEN_ADDRESS,
            WETH_ADDRESS,
            MASTERCHEF_ADDRESS,
            VAULT_LOCKED_DISTRIBUTE_GLOBAL_INTERVAL
        ],
    });

    // Set up
    await vaultDistribution.setMinTokenAmountToDistribute(VAULT_DISTRIBUTION_MIN_BNB_TO_DISTRIBUTE);
    console.log("Min BNB to distribute set to: ", VAULT_DISTRIBUTION_MIN_BNB_TO_DISTRIBUTE.toString());
    await vaultDistribution.setDistributionPercentage(VAULT_DISTRIBUTION_DISTRIBUTE_PERCENTAGE);
    console.log("Distribute percentage set to: ", VAULT_DISTRIBUTION_DISTRIBUTE_PERCENTAGE.toString());
    await vaultDistribution.setDistributionInterval(VAULT_DISTRIBUTION_DISTRIBUTE_INTERVAL);
    console.log("Distribution interval set to: ", VAULT_DISTRIBUTION_DISTRIBUTE_INTERVAL.toString());

    console.log("Current block is:", CURRENT_BLOCK);

    console.log("Deploy finished");
    console.log("Ensure you update VaultDistribution address into addresses.js");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
