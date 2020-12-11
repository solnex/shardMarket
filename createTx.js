
const NFTToken = artifacts.require('NFTToken');
const ShardsMarket = artifacts.require('ShardsMarket');
const MockWETH = artifacts.require('MockWETH');
const MockFactory = artifacts.require('UniswapV2Factory');
const Router = artifacts.require('UniswapV2Router02');
const ShardToken = artifacts.require('ShardToken');
const Pair = artifacts.require('UniswapV2Pair');
const MockERC20Token = artifacts.require('mockERCToken');
// account address
var account1 = "0x2E7c4EfdFA6680e34988dcBD70F6a31b4CC28219";
var account2 = "0x3734C8fA3A75F21C025E874B9193602bd1414D3a";
var account3 = "0x914B8Cf1eB707c477e9d9Bf5F9E38D85D00Ac329";
var account4 = "0x63079128D91804978921703F67421e62D7246848";
var accountAdmin = "0x2E7c4EfdFA6680e34988dcBD70F6a31b4CC28219";

// contract address
var NFTTokenAddress = "0x8549996Db3EC43558fE051fF63E8382f77EAb37c";
var ShardsMarketAddress = "0x6cBA5138D292EE871F10e81E551bdD100Ad25B9B";
var wantTokenAddress = "0xB5685232b185cAdF7C5F58217722Ac40BC4ec45e";

// parameter
var tokenId = 31110006;
var poolId = 1;
var proposalId = 1;
var name = "Shard0";
var minPrice = "1000000000000000000";
var stakeAmount1 = "1000000000000000000";
var stakeAmount2 = "2000000000000000000";
var stakeAmount3 = "100000000000000000";
var stakeAmount4 = "200000000000000000";
var stakeAmount5 = "7000000000000000000";
var applyForBuyoutAmount = "200000000000000000000";
function sleep(milliSeconds) {
    var startTime = new Date().getTime();
    console.log("waiting...")
    while (new Date().getTime() < startTime + milliSeconds) {
        //console.log(new Date().getTime());
    }//暂停一段时间 10000=1S。
    console.log("time ready!")
}


//0xfEBCE3845Cb04d2C3d3C7724b02a0ddcFe35bc7B
module.exports = async function (callback) {

    this.NFTToken = await NFTToken.at(NFTTokenAddress);
    this.ShardsMarket = await ShardsMarket.at(ShardsMarketAddress);
    this.MockERC20Token = await MockERC20Token.at(wantTokenAddress);
    //认购中：
    console.log("认购中状态创建:");
    await this.NFTToken.mint(tokenId, { from: account1 });
    await this.NFTToken.approve(ShardsMarketAddress, tokenId, { from: account1 });
    var result = await this.ShardsMarket.createShard(NFTTokenAddress, tokenId, name + "0", name + "0", minPrice, wantTokenAddress, { from: account1 });
    console.log("address", result);

    result = await this.MockERC20Token.approve(ShardsMarketAddress, stakeAmount1, { from: account2 });
    console.log("approved:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, stakeAmount2, { from: account3 });
    console.log("approved", result);
    result = await this.ShardsMarket.stake(poolId, stakeAmount1, { from: account2 });
    console.log("approved", result);
    result = await this.ShardsMarket.stake(poolId, stakeAmount2, { from: account3 });
    console.log("approved", result);


    //认购成功：
    console.log("认购成功状态创建:");
    tokenId++;
    console.log("tokenId:", tokenId);
    poolId++;
    console.log("poolId:", poolId);
    result = await this.NFTToken.mint(tokenId, { from: account1 });
    console.log("minted:", result);
    result = await this.NFTToken.approve(ShardsMarketAddress, tokenId, { from: account1 });
    console.log("minted:", result);

    result = await this.ShardsMarket.setDeadlineForRedeem(10, { from: accountAdmin });
    console.log("setDeadlineForRedeem:", result);
    result = await this.ShardsMarket.createShard(NFTTokenAddress, tokenId, name + "1", name + "1", minPrice, wantTokenAddress, { from: account1 });
    console.log("createShard:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, stakeAmount1, { from: account2 });
    console.log("approved:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, stakeAmount2, { from: account3 });
    console.log("approved", result);
    result = await this.ShardsMarket.stake(poolId, stakeAmount1, { from: account2 });
    console.log("stake:", result);
    result = await this.ShardsMarket.stake(poolId, stakeAmount2, { from: account3 });
    console.log("stake:", result);
    sleep(10000);
    result = await this.ShardsMarket.settle(poolId, { from: account1, gas: 6000000 });
    console.log("settle:", result);

    // //认购失败：
    console.log("认购失败状态创建:");
    tokenId++;
    console.log("tokenId:", tokenId);
    poolId++;
    console.log("poolId:", poolId);

    result = await this.NFTToken.mint(tokenId, { from: account1 });
    console.log("minted:", result);
    result = await this.NFTToken.approve(ShardsMarketAddress, tokenId, { from: account1 });
    console.log("minted:", result);

    await this.ShardsMarket.setDeadlineForRedeem(10, { from: accountAdmin });
    console.log("setDeadlineForRedeem:", result);
    result = await this.ShardsMarket.createShard(NFTTokenAddress, tokenId, name + "2", name + "2", minPrice, wantTokenAddress, { from: account1 });
    console.log("createShard:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, stakeAmount3, { from: account2 });
    console.log("approved:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, stakeAmount4, { from: account3 });
    console.log("approved", result);
    result = await this.ShardsMarket.stake(poolId, stakeAmount3, { from: account2 });
    console.log("stake:", result);
    result = await this.ShardsMarket.stake(poolId, stakeAmount4, { from: account3 });
    console.log("stake:", result);
    sleep(10000);
    result = await this.ShardsMarket.settle(poolId, { from: account1, gas: 6000000 });
    console.log("settle:", result);

    result = await this.ShardsMarket.setDeadlineForRedeem(604800, { from: accountAdmin });
    console.log("setDeadlineForRedeem:", result);

    //买断申请
    console.log("买断申请状态创建:");
    tokenId++;
    console.log("tokenId:", tokenId);
    poolId++;
    console.log("poolId:", poolId);
    proposalId++;
    result = await this.NFTToken.mint(tokenId, { from: account1 });
    console.log("minted:", result);
    result = await this.NFTToken.approve(ShardsMarketAddress, tokenId, { from: account1 });
    console.log("minted:", result);

    await this.ShardsMarket.setDeadlineForRedeem(10, { from: accountAdmin });
    console.log("setDeadlineForRedeem:", result);
    result = await this.ShardsMarket.createShard(NFTTokenAddress, tokenId, name + "3", name + "3", minPrice, wantTokenAddress, { from: account1 });
    console.log("createShard:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, stakeAmount5, { from: account2 });
    console.log("approved:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, stakeAmount1, { from: account3 });
    console.log("approved", result);
    result = await this.ShardsMarket.stake(poolId, stakeAmount5, { from: account2 });
    console.log("stake:", result);
    result = await this.ShardsMarket.stake(poolId, stakeAmount1, { from: account3 });
    console.log("stake:", result);
    sleep(10000);
    result = await this.ShardsMarket.settle(poolId, { from: account1, gas: 6000000 });
    console.log("settle:", result);
    result = await this.ShardsMarket.creatorWithdrawWantToken(poolId, { from: account1 });
    console.log("creatorWithdrawWantToken:", result);
    result = await this.ShardsMarket.usersWithdrawShardToken(poolId, { from: account2 });
    console.log("usersWithdrawShardToken:", result);


    shardInfo = await this.ShardsMarket.shardInfo.call(poolId);
    console.log("ShardToken:", shardInfo[2]);
    this.ShardToken = await ShardToken.at(shardInfo[2]);
    shardBalance = await this.ShardToken.balanceOf.call(account2);
    console.log("shardBalance:", shardBalance);
    result = await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: account2 });
    console.log("shardBalance:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, applyForBuyoutAmount, { from: account2 });
    console.log("approved", result);
    result = await this.ShardsMarket.applyForBuyout(poolId, applyForBuyoutAmount, { from: account2 });
    console.log("applyForBuyout", result);
    result = await this.ShardsMarket.setDeadlineForRedeem(604800, { from: accountAdmin });
    console.log("setDeadlineForRedeem:", result);
    // //买断申请(买断失败)
    console.log("买断申请(买断失败):");
    tokenId++;
    console.log("tokenId:", tokenId);
    poolId++;
    console.log("poolId:", poolId);
    proposalId++;
    result = await this.NFTToken.mint(tokenId, { from: account1 });
    console.log("minted:", result);
    result = await this.NFTToken.approve(ShardsMarketAddress, tokenId, { from: account1 });
    console.log("minted:", result);

    await this.ShardsMarket.setDeadlineForRedeem(10, { from: accountAdmin });
    console.log("setDeadlineForRedeem:", result);
    result = await this.ShardsMarket.createShard(NFTTokenAddress, tokenId, name + "4", name + "4", minPrice, wantTokenAddress, { from: account1 });
    console.log("createShard:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, stakeAmount5, { from: account2 });
    console.log("approved:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, stakeAmount1, { from: account3 });
    console.log("approved", result);
    result = await this.ShardsMarket.stake(poolId, stakeAmount5, { from: account2 });
    console.log("stake:", result);
    result = await this.ShardsMarket.stake(poolId, stakeAmount1, { from: account3 });
    console.log("stake:", result);
    sleep(10000);
    result = await this.ShardsMarket.settle(poolId, { from: account1, gas: 6000000 });
    console.log("settle:", result);
    result = await this.ShardsMarket.creatorWithdrawWantToken(poolId, { from: account1 });
    console.log("creatorWithdrawWantToken:", result);
    result = await this.ShardsMarket.usersWithdrawShardToken(poolId, { from: account2 });
    console.log("usersWithdrawShardToken:", result);
    result = await this.ShardsMarket.usersWithdrawShardToken(poolId, { from: account3 });
    console.log("usersWithdrawShardToken:", result);

    shardInfo = await this.ShardsMarket.shardInfo.call(poolId);
    console.log("ShardToken:", shardInfo[2]);
    this.ShardToken = await ShardToken.at(shardInfo[2]);
    shardBalance = await this.ShardToken.balanceOf.call(account2);
    console.log("shardBalance:", shardBalance);
    result = await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: account2 });
    console.log("shardBalance:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, applyForBuyoutAmount, { from: account2 });
    console.log("approved", result);

    result = await this.ShardsMarket.setVoteLenth(15, { from: accountAdmin });
    console.log("setVoteLenth:", result);
    result = await this.ShardsMarket.applyForBuyout(poolId, applyForBuyoutAmount, { from: account2 });
    console.log("applyForBuyout:", result);
    result = await this.ShardsMarket.vote(poolId, false, { from: account3 });
    console.log("vote:", result);
    sleep(11000);
    result = await this.ShardsMarket.voteResultConfirm(poolId);
    console.log("voteResultConfirm:", result);

    //买断申请(成功)
    console.log("买断申请(成功):");
    tokenId++;
    console.log("tokenId:", tokenId);
    poolId++;
    console.log("poolId:", poolId);
    proposalId++;
    result = await this.NFTToken.mint(tokenId, { from: account1 });
    console.log("minted:", result);
    result = await this.NFTToken.approve(ShardsMarketAddress, tokenId, { from: account1 });
    console.log("minted:", result);

    await this.ShardsMarket.setDeadlineForRedeem(10, { from: accountAdmin });
    console.log("setDeadlineForRedeem:", result);
    result = await this.ShardsMarket.createShard(NFTTokenAddress, tokenId, name + "5", name + "5", minPrice, wantTokenAddress, { from: account1 });
    console.log("createShard:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, stakeAmount5, { from: account2 });
    console.log("approved:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, stakeAmount1, { from: account3 });
    console.log("approved", result);
    result = await this.ShardsMarket.stake(poolId, stakeAmount5, { from: account2 });
    console.log("stake:", result);
    result = await this.ShardsMarket.stake(poolId, stakeAmount1, { from: account3 });
    console.log("stake:", result);
    sleep(10000);
    result = await this.ShardsMarket.settle(poolId, { from: account1, gas: 6000000 });
    console.log("settle:", result);
    result = await this.ShardsMarket.creatorWithdrawWantToken(poolId, { from: account1 });
    console.log("creatorWithdrawWantToken:", result);
    result = await this.ShardsMarket.usersWithdrawShardToken(poolId, { from: account2 });
    console.log("usersWithdrawShardToken:", result);
    result = await this.ShardsMarket.usersWithdrawShardToken(poolId, { from: account3 });
    console.log("usersWithdrawShardToken:", result);

    shardInfo = await this.ShardsMarket.shardInfo.call(poolId);
    console.log("ShardToken:", shardInfo[2]);
    this.ShardToken = await ShardToken.at(shardInfo[2]);
    shardBalance = await this.ShardToken.balanceOf.call(account2);
    console.log("shardBalance:", shardBalance);
    result = await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: account2 });
    console.log("shardBalance:", result);
    result = await this.MockERC20Token.approve(ShardsMarketAddress, applyForBuyoutAmount, { from: account2 });
    console.log("approved", result);

    result = await this.ShardsMarket.setVoteLenth(15, { from: accountAdmin });
    console.log("setVoteLenth:", result);
    result = await this.ShardsMarket.applyForBuyout(poolId, applyForBuyoutAmount, { from: account2 });
    console.log("applyForBuyout:", result);
    result = await this.ShardsMarket.vote(poolId, true, { from: account3 });
    console.log("vote:", result);
    sleep(11000);
    result = await this.ShardsMarket.voteResultConfirm(poolId);
    console.log("voteResultConfirm:", result);


    console.log("状态创建完成！");
}