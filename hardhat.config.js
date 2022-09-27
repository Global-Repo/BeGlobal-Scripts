require("@nomiclabs/hardhat-waffle"); // Includes hardhat-ethers
require("@nomiclabs/hardhat-etherscan");
require("hardhat-gas-reporter");
require("@nomiclabs/hardhat-web3");

const fs = require('fs');
//const secrets = fs.readFileSync(".secret").toString().trim().split(/\n/);
const secretsDeployer = fs.readFileSync(".secret_deployer_dd3").toString().trim().split(/\n/);
//const mnemonicTest = secrets[0].trim();
const mnemonicDeployer = secretsDeployer[0].trim();
const apiKeyBSC = secretsDeployer[1].trim();

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    hardhat: {
      allowUnlimitedContractSize: true
    },
    testnet: {
      allowUnlimitedContractSize: true,
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: 97,
      gasPrice: 20000000000,
      accounts: {mnemonic: mnemonicDeployer},
    },
    mainnet: {
      allowUnlimitedContractSize: true,
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      gasPrice: 20000000000,
      accounts: {mnemonic: mnemonicDeployer}
    }
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://bscscan.com/
    apiKey: apiKeyBSC
  },
  solidity: {
    compilers: [
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.4.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.5.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.6.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.8.1",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.8.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 20000
  },
  gasReporter: {
    token: 'BNB',
    gasPriceApi: 'https://api.bscscan.com/api?module=proxy&action=eth_gasPrice',
    coinmarketcap: 'GU38I82Y86NWHD3UEQPE9V8B9K6PJBKCWI',
    enabled: true
  }
}