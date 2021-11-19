require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require('dotenv').config();

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    hardhat: {
      forking: {
        url:
          "https://eth-mainnet.alchemyapi.io/v2/" +
          process.env.ALCHEMY_API_KEY,
        blockNumber: 12794142,
      },
    },
    testnet: {
      url: process.env.MORALIS_BSC_TESTNET_ARCHIVE_URL || "",
      chainId: 97,
      accounts:
        process.env.MNEMONIC !== undefined
          ? { mnemonic: process.env.MNEMONIC }
          : [],
    },
    mainnet: {
      url: process.env.MORALIS_BSC_MAINNET_URL || "",
      chainId: 56,
      gasPrice: 20000000000,
      accounts:
        process.env.DEPLOYER001_PRIVATE_KEY !== undefined
          ? [process.env.DEPLOYER001_PRIVATE_KEY]
          : [],
    },
  },
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  abiExporter: {
    path: "./data/abi",
    clear: true,
    flat: true,
    only: [],
    spacing: 2,
  },
  etherscan: {
    apiKey: process.env.BSCSCAN_API_KEY,
  },
};
