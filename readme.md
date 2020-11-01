## NFT contract
### 部署设置
1. 下载Dotenv安装包
``` 
npm install dotenv
``` 
2. 合约根目录下添加.env文件,在.env文件添加环境变量,进行部署账号配置
``` 
mnemonic_kovan = "助记词或者私钥";
```
3. 下载依赖的安装包
```
npm install openzeppelin-solidity
npm install truffle-hdwallet-provider
```
4. 部署合约
```
truffle migrate --network ropsten
```