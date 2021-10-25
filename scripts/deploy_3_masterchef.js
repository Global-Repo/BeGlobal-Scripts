const hre = require("hardhat");
require("@nomiclabs/hardhat-ethers");
const {ethers} = require("hardhat");
const {
    GLOBAL_TOKEN_ADDRESS,
    DEV_POWER_ADDRESS,
    TREASURY_MINT_ADDRESS,
    TREASURY_LP_ADDRESS,
    TOKEN_ADDRESSES_ADDRESS,
    ROUTER_ADDRESS,
} = require("./addresses");
const {
    deployPathFinder,
} = require("../test/helpers/singleDeploys");
const { bep20Amount } = require("../test/helpers/utils");

let pathFinder;
let masterChefInternal;
let masterchef;

let CURRENT_BLOCK;

async function main() {
    console.log("Starting deploy");
    console.log("Ensure you have proper addresses set up into addresses.js for: Router, TokenAddresses");

    [deployer] = await hre.ethers.getSigners();

    CURRENT_BLOCK = await ethers.provider.getBlockNumber();
    console.log("Current block is:", CURRENT_BLOCK);

    const NATIVE_TOKEN_PER_BLOCK = bep20Amount(125);
    const MASTERCHEF_START_BLOCK = 12405477; // timestamp 1636144200;

    // Start
    pathFinder = await deployPathFinder(TOKEN_ADDRESSES_ADDRESS);
    console.log("PathFinder deployed to:", TOKEN_ADDRESSES_ADDRESS);

    const MasterChefInternal = await ethers.getContractFactory("MasterChefInternal");
    masterChefInternal = await MasterChefInternal.deploy(TOKEN_ADDRESSES_ADDRESS, pathFinder.address);
    await masterChefInternal.deployed();
    console.log("Masterchef Internal deployed to:", masterChefInternal.address);

    const MasterChef = await ethers.getContractFactory("MasterChef");
    masterchef = await MasterChef.deploy(
        masterChefInternal.address,
        GLOBAL_TOKEN_ADDRESS,
        NATIVE_TOKEN_PER_BLOCK,
        MASTERCHEF_START_BLOCK,
        ROUTER_ADDRESS,
        TOKEN_ADDRESSES_ADDRESS,
        pathFinder.address
    );
    await masterchef.deployed();
    console.log("Masterchef deployed to:", masterchef.address);
    console.log("Globals per block: ", NATIVE_TOKEN_PER_BLOCK.toString());
    console.log("Masterchef start block", MASTERCHEF_START_BLOCK.toString());

    // Set up
    await masterchef.setTreasury(TREASURY_MINT_ADDRESS);
    console.log("Masterchef treasury address set up to:", TREASURY_MINT_ADDRESS);

    await masterchef.setTreasuryLP(TREASURY_LP_ADDRESS);
    console.log("Masterchef treasury LP address set up to:", TREASURY_LP_ADDRESS);

    await masterChefInternal.transferOwnership(masterchef.address);
    console.log("Masterchef internal ownership to masterchef:", masterchef.address);

    await pathFinder.transferOwnership(masterChefInternal.address);
    console.log("Path finder ownership to masterchef internal:", masterChefInternal.address);

    await masterchef.transferDevPower(DEV_POWER_ADDRESS);
    console.log("Masterchef dev power set to:", DEV_POWER_ADDRESS);

    // Verify
    await hre.run("verify:verify", {
        address: pathFinder.address,
        constructorArguments: [
            TOKEN_ADDRESSES_ADDRESS
        ],
    });

    await hre.run("verify:verify", {
        address: masterChefInternal.address,
        constructorArguments: [
            TOKEN_ADDRESSES_ADDRESS,
            pathFinder.address,
        ],
    });

    await hre.run("verify:verify", {
        address: masterchef.address,
        constructorArguments: [
            masterChefInternal.address,
            GLOBAL_TOKEN_ADDRESS,
            NATIVE_TOKEN_PER_BLOCK,
            MASTERCHEF_START_BLOCK,
            ROUTER_ADDRESS,
            TOKEN_ADDRESSES_ADDRESS,
            pathFinder.address
        ],
    });
    
    console.log("Current block is:", CURRENT_BLOCK);

    console.log("Deploy finished");
    console.log("Ensure you update PathFinder, Masterchef, address into addresses.js");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
