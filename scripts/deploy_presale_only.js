const hre = require("hardhat");
const { deployMasterChef } = require("../test/helpers/singleDeploys.js");
const { BigNumber } = require("@ethersproject/bignumber");
require("@nomiclabs/hardhat-ethers");
const {ethers} = require("hardhat");

const {timestampNDays, timestampNow} = require("../test/helpers/utils");

let nativeToken;
let presale;

const TOKEN_DECIMALS = 18;
const BIG_NUMBER_TOKEN_DECIMALS_MULTIPLIER = BigNumber.from(10).pow(TOKEN_DECIMALS);

const NATIVE_TOKEN_TO_MINT = BigNumber.from(1000000).mul(BIG_NUMBER_TOKEN_DECIMALS_MULTIPLIER);

async function main() {
    [owner, ...addrs] = await hre.ethers.getSigners();

    const NativeToken = await ethers.getContractFactory("NativeToken");
    nativeToken = await NativeToken.deploy();
    await nativeToken.deployed();

    const Presale = await ethers.getContractFactory("Presale");
    const whiteTime = (await timestampNow()/*+await timestampNDays(2)*/);
    const publicTime = (await timestampNow()+await timestampNDays(9));
    presale = await Presale.deploy(nativeToken.address, whiteTime, publicTime);
    await presale.deployed();

    await nativeToken.mint(NATIVE_TOKEN_TO_MINT);
    await nativeToken.transfer(presale.address,NATIVE_TOKEN_TO_MINT);
    await nativeToken.transferOwnership(presale.address);

    console.log("NativeToken deployed to:", nativeToken.address);
    console.log("Presale deployed to:", presale.address);
    console.log("whiteTime:", whiteTime);
    console.log("publicTime:", publicTime);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
