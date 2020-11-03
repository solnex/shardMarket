
const NFTToken = artifacts.require('NFTToken');
const MockWETH = artifacts.require('MockWETH');
const ShardsMarket = artifacts.require('ShardsMarket');


contract('NFTToken', (accounts) => {
    let bob = accounts[0];
    beforeEach(async () => {
        this.NFTToken = await NFTToken.new("NFT", "NFT", { from: bob });
        this.MockWETH = await MockWETH.new({ from: bob });
        this.ShardsMarket = await ShardsMarket.new(this.MockWETH.address, bob, bob, bob, { from: bob, gas: 6000000 });
        //  this.ShardsMarket = await ShardsMarket.new(accounts[0], accounts[0], accounts[0], accounts[0], { from: accounts[0] });
    });
    // it('approve with safeErc20', async () => {
    //     await this.NFTToken.mint(100);
    //     let owner = await this.NFTToken.ownerOf(100);
    //     assert.equal(owner, bob);
    // });
    // it('createShared works', async () => {
    //     await this.NFTToken.mint(100);
    //     await this.NFTToken.approve(this.ShardsMarket.address, 100);
    //     await this.ShardsMarket.createShared(this.NFTToken.address,
    //         100,
    //         "myshard",
    //         "myshard",
    //         12);
    //     let owner = await this.NFTToken.ownerOf(100);
    //     assert.equal(owner, this.ShardsMarket.address);
    //     var shardPoolInfo = await this.ShardsMarket.getShardPool.call(1);
    //     assert.equal(shardPoolInfo[0], bob);
    // });
    // it('stake works', async () => {
    //     await this.NFTToken.mint(100);
    //     await this.NFTToken.approve(this.ShardsMarket.address, 100);
    //     await this.ShardsMarket.createShared(this.NFTToken.address,
    //         100,
    //         "myshard",
    //         "myshard",
    //         12);
    //     // await this.MockWETH.approve(this.ShardsMarket.address, 10);
    //     await this.ShardsMarket.stake(1, 10, { value: 10, from: bob });
    //     var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
    //     let balance = await web3.eth.getBalance(this.ShardsMarket.address);
    //     // await this.MockWETH.balanceOf(this.ShardsMarket.address);
    //     assert.equal(balance, 10);

    //     assert.equal(shardPoolInfo[5], 10);
    //     var userInfo = await this.ShardsMarket.userInfo.call(1, bob);
    //     assert.equal(userInfo[0], 10);
    // });
    // it('redeem works', async () => {
    //     await this.NFTToken.mint(100);
    //     await this.NFTToken.approve(this.ShardsMarket.address, 100);
    //     await this.ShardsMarket.createShared(this.NFTToken.address,
    //         100,
    //         "myshard",
    //         "myshard",
    //         12);
    //     await this.ShardsMarket.stake(1, 10, { value: 10, from: bob });
    //     let balanceBefore = await web3.eth.getBalance(this.ShardsMarket.address);
    //     assert.equal(balanceBefore, 10);
    //     var shardPoolInfoBefore = await this.ShardsMarket.poolInfo.call(1);
    //     assert.equal(shardPoolInfoBefore[5], 10);
    //     var userInfoBefore = await this.ShardsMarket.userInfo.call(1, bob);
    //     assert.equal(userInfoBefore[0], 10);
    //     await this.ShardsMarket.redeem(1, 5);
    //     let balanceAfter = await web3.eth.getBalance(this.ShardsMarket.address);
    //     assert.equal(balanceAfter, 5);
    //     var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
    //     assert.equal(shardPoolInfoAfter[5], 5);
    //     var userInfoAfter = await this.ShardsMarket.userInfo.call(1, bob);
    //     assert.equal(userInfoAfter[0], 5);
    // });
    // it('settle fail works', async () => {
    //     await this.NFTToken.mint(100);
    //     await this.NFTToken.approve(this.ShardsMarket.address, 100);
    //     await this.ShardsMarket.createShared(this.NFTToken.address,
    //         100,
    //         "myshard",
    //         "myshard",
    //         12);
    //     await this.ShardsMarket.stake(1, 10, { value: 10, from: bob });
    //     await this.ShardsMarket.setDeadlineForRedeem(0);
    //     await this.ShardsMarket.settle(1);
    //     var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
    //     //  assert.equal(shardPoolInfoAfter[4], 0);//tokenaddress
    //     assert.equal(shardPoolInfoAfter[2], 5);//state
    // });
    it('settle success works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            10000);
        await this.ShardsMarket.stake(1, 100000, { value: 10000, from: bob });
        await this.ShardsMarket.setDeadlineForRedeem(0);
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoAfter[4], 0);//tokenaddress
        assert.equal(shardPoolInfoAfter[2], 5);//state
    });
})