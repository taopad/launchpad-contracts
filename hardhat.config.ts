import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter"

const config: HardhatUserConfig = {
  gasReporter: {
    enabled: true,
    currency: 'USD',
    coinmarketcap: process.env.CMC_API_KEY,
    gasPriceApi: 'https://api.etherscan.io/api?module=proxy&action=eth_gasPrice'
  },
  solidity: {
    version: "0.8.23",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 1000,
        details: {
          yul: true,
          yulDetails: {
            optimizerSteps: "u",
          },
        },
      },
    },
  },
};

export default config;
