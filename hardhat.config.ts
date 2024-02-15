import 'dotenv/config';
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter"
import 'hardhat-deploy';

const config: HardhatUserConfig = {
  gasReporter: {
    enabled: true,
    currency: 'USD',
    coinmarketcap: process.env.CMC_API_KEY,
    gasPriceApi: 'https://api.etherscan.io/api?module=proxy&action=eth_gasPrice'
  },
  namedAccounts: {
    deployer: 0
  },
  networks: {
    hardhat: {
			forking: {
				url: process.env.MAINNET_RPC_URL || '',
    	},
		},
		buildbear: {
			url: process.env.BUILDBEAR_RPC_URL || '',
			accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
		},
		mainnet: {
			url: process.env.MAINNET_RPC_URL || '',
			accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
			gasPrice: 100000000000,
		},
	},
  solidity: {
    version: "0.8.23",
    settings: {
      optimizer: {
        enabled: true,
        runs: 3000,       
      },
    },
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || "",
    }
  },
};

export default config;
