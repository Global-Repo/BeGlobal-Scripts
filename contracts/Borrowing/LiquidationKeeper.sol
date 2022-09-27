// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IController {
    function isCollateralized(address user, address gToken) external view returns (bool);

    function maxLiquidatableAmount(address borrower) external view returns (uint256);

    function getPrice(address gToken) external view returns (uint256);

    function totalDebts(address user) external view returns (uint256 total);
}

interface IGToken {
    function assetUSDValue(address user) external view returns (uint256);

    function debts(address user) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function liquidateBorrowMax(address borrower, address gTokenCollateral) external;
}

contract LiquidationKeeper is Ownable {
    using SafeERC20 for IERC20;

    // Whitelisted wallet to modify borrowersList Array.
    // At this moment we keep this variable as public with betatesting purposes.
    address public liquidatorManager;

    struct borrowedData {
        bool isCollateralized;
        uint256 assetUSDValue;
        uint256 borrowedUSDValue;
    }

    // Already deployed contracts addresses.
    address constant CONTROLLER_CONTRACT = 0xF6b58e14EC4074B118ae56d54C6943e61385f429;
    address constant G_ETH_CONTRACT = 0x8009c10964e1711ADa8f012F59492279d3E33B67;
    address constant G_BTC_CONTRACT = 0x205A69E74dB750e05fB3be0A2f9b8CcbaEcD4B0E;
    address constant G_BUSD_CONTRACT = 0x549f9dcA699217A4FC009d3a654a60Df08c7cfDb;

    address constant ETH_CONTRACT = 0x403cFf141a1DD3103712975A8Efdb6e763139a0f;
    address constant BTC_CONTRACT = 0x1dA539d42466e61976992385eC5137A9e8ba393c;
    address constant BUSD_CONTRACT = 0x6D61b4b740128907fBA2B71dB297d96893248171;

    // Max integer
    uint256 constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    // External contracts declarations.
    IController immutable controller;
    IGToken immutable gBUSD;
    IGToken immutable gBTC;
    IGToken immutable gETH;

    constructor(address _liquidatorManager) {
        // Borrowers list manager
        liquidatorManager = _liquidatorManager;

        // External contracts declarations.
        controller = IController(CONTROLLER_CONTRACT);
        gBUSD = IGToken(G_BUSD_CONTRACT);
        gBTC = IGToken(G_BTC_CONTRACT);
        gETH = IGToken(G_ETH_CONTRACT);
    }

    // BEP20 Tokens contracts
    // BUSD => 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56
    // BTC  => 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c
    // ETH  => 0x2170Ed0880ac9A755fd29B2688956BD959F933F8

    // OnlyListManager modifier
    modifier onlyLiquidatorManager() {
        require(msg.sender == liquidatorManager, "Operation not allowed");
        _;
    }

    function allowanceLiquidator() public onlyOwner {
        // Approve the liquidator´s tokens to repay the borrows
        // Only neccesay to run it once for the whole contract life
        IERC20(BUSD_CONTRACT).approve(G_BUSD_CONTRACT, MAX_INT);
        IERC20(BTC_CONTRACT).approve(G_BTC_CONTRACT, MAX_INT);
        IERC20(ETH_CONTRACT).approve(G_ETH_CONTRACT, MAX_INT);
    }

    function withdrawERC20Tokens(address _tokenAddress, uint256 _tokenAmount) public onlyOwner {
        IERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);
    }

    function getBorrowerTotalDebts(address _borrower) public view onlyLiquidatorManager returns (uint256) {
        return controller.totalDebts(_borrower);
    }

    function changeLiquidatorManager(address _newManager) public onlyOwner {
        liquidatorManager = _newManager;
    }

    function getMaxLiquidatableAmount(address _borrower) public view onlyLiquidatorManager returns (uint256) {
        return controller.maxLiquidatableAmount(_borrower);
    }

    function getLiquidatableBorrowerData(address borrower)
        public
        view
        onlyLiquidatorManager
        returns (
            address,
            address,
            address
        )
    {
        //Borrowed data struct
        borrowedData memory gETHBorrowedData;
        borrowedData memory gBTCBorrowedData;
        borrowedData memory gBUSDBorrowedData;

        gETHBorrowedData.borrowedUSDValue = (gETH.debts(borrower) * controller.getPrice(G_ETH_CONTRACT)) / 1e8;
        gBTCBorrowedData.borrowedUSDValue = (gBTC.debts(borrower) * controller.getPrice(G_BTC_CONTRACT)) / 1e8;
        gBUSDBorrowedData.borrowedUSDValue = (gBUSD.debts(borrower) * controller.getPrice(G_BUSD_CONTRACT)) / 1e8;

        gETHBorrowedData.assetUSDValue = gETH.assetUSDValue(borrower);
        gBTCBorrowedData.assetUSDValue = gBTC.assetUSDValue(borrower);
        gBUSDBorrowedData.assetUSDValue = gBUSD.assetUSDValue(borrower);

        // Pick up the Collateral with highest USD value
        address collateral;
        uint256[3] memory collaterals;

        gETHBorrowedData.isCollateralized = controller.isCollateralized(borrower, G_ETH_CONTRACT);
        gBTCBorrowedData.isCollateralized = controller.isCollateralized(borrower, G_BTC_CONTRACT);
        gBUSDBorrowedData.isCollateralized = controller.isCollateralized(borrower, G_BUSD_CONTRACT);

        if (gETHBorrowedData.isCollateralized) {
            collaterals[0] = gETHBorrowedData.assetUSDValue;
        }
        if (gBTCBorrowedData.isCollateralized) {
            collaterals[1] = gBTCBorrowedData.assetUSDValue;
        }
        if (gBUSDBorrowedData.isCollateralized) {
            collaterals[2] = gBUSDBorrowedData.assetUSDValue;
        }

        if ((collaterals[0] > collaterals[1]) && (collaterals[0] > collaterals[2])) {
            collateral = G_ETH_CONTRACT;
        } else if ((collaterals[1] > collaterals[0]) && (collaterals[1] > collaterals[2])) {
            collateral = G_BTC_CONTRACT;
        } else {
            collateral = G_BUSD_CONTRACT;
        }

        // Pick up the borrowed with highest USD value to liquidate it.
        address gTokenToLiquidate;
        if ((gETHBorrowedData.borrowedUSDValue > gBTCBorrowedData.borrowedUSDValue) && (gETHBorrowedData.borrowedUSDValue > gBUSDBorrowedData.borrowedUSDValue)) {
            gTokenToLiquidate = G_ETH_CONTRACT;
        } else if ((gBTCBorrowedData.borrowedUSDValue > gETHBorrowedData.borrowedUSDValue) && (gBTCBorrowedData.borrowedUSDValue > gBUSDBorrowedData.borrowedUSDValue)) {
            gTokenToLiquidate = G_BTC_CONTRACT;
        } else {
            gTokenToLiquidate = G_BUSD_CONTRACT;
        }

        return (borrower, collateral, gTokenToLiquidate);
    }

    ////////////////////////////
    /////   Liquidation   //////
    ////////////////////////////

    function liquidateBorrower(
        address borrower,
        address collateral,
        address gTokenToLiquidate
    ) public returns (bool) {
        if (gTokenToLiquidate == G_ETH_CONTRACT) {
            gETH.liquidateBorrowMax(borrower, collateral);
        }
        if (gTokenToLiquidate == G_BTC_CONTRACT) {
            gBTC.liquidateBorrowMax(borrower, collateral);
        }
        if (gTokenToLiquidate == G_BUSD_CONTRACT) {
            gBUSD.liquidateBorrowMax(borrower, collateral);
        }

        //Success
        return true;
    }

    receive() external payable {}

    fallback() external payable {}
}
