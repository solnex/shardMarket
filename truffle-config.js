const dotenv = require('dotenv');
const result = dotenv.config();
if (result.error) {
  throw result.error;
}
console.log(result.parsed);

//var NonceTrackerSubprovider = require("web3-provider-engine/subproviders/nonce-tracker");
var HDWalletProvider = require("truffle-hdwallet-provider");

/*访问https://infura.io/注册后获取的api-key*/
var infura_apikey = "89da3e2e7a1b4cc08fc6887c6496dc75";

/*读取.env文件配置的助记词*/
var mnemonic_kovan = process.env.mnemonic_kovan;
//var mnemonic_mainnet = process.env.mnemonic_mainnet;
module.exports = {



  networks: {
    development: {
      host: "127.0.0.1",     // Localhost (default: none)
      port: 8545,            // Standard Ethereum port (default: none)
      network_id: "*",       // Any network (default: none)
      gas: 5002388,
      gasPrice: 30000000000
    },
    kovan: {
      provider: new HDWalletProvider(mnemonic_kovan, "https://kovan.infura.io/v3/" + infura_apikey),
      network_id: 42,
      gas: 3012388,
      gasPrice: 30000000000
    }
  },

  compilers: {
    solc: {
      version: "0.6.12",
      settings: {
        //evmVersion: 'byzantium', // Default: "petersburg"
        optimizer: {
          enabled: true,
          runs: 1500
        }
      }
    },
  },
  plugins: [
    'truffle-plugin-verify'
  ],
  api_keys: {
    etherscan: process.env.ETHERSCAN_API_KEY
  }
};
