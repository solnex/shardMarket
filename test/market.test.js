
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
    it('NFTToken mint works', async () => {
        await this.NFTToken.mint(100);
        let owner = await this.NFTToken.ownerOf(100);
        assert.equal(owner, bob);
    });
    it('createShared works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            12,
            this.MockWETH.address);
        let owner = await this.NFTToken.ownerOf(100);
        assert.equal(owner, this.ShardsMarket.address);
        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[0], bob);
    });
    it('stake works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            12,
            this.MockWETH.address);
        //stakeETH test
        await this.ShardsMarket.stakeETH(1, { value: 10, from: bob });

        let balance = await this.MockWETH.balanceOf(this.ShardsMarket.address);
        assert.equal(balance, 10);

        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[5], 10);

        var userInfo = await this.ShardsMarket.userInfo.call(1, bob);
        assert.equal(userInfo[0], 10);
        //stake test
        await this.MockWETH.deposit({ value: 10 });
        await this.MockWETH.approve(this.ShardsMarket.address, 10);
        await this.ShardsMarket.stake(1, 10, { from: bob });

        balance = await this.MockWETH.balanceOf(this.ShardsMarket.address);
        assert.equal(balance, 20);

        shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[5], 20);

        userInfo = await this.ShardsMarket.userInfo.call(1, bob);
        assert.equal(userInfo[0], 20);
    });
    it('redeem works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            12,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: 10, from: bob });

        var balanceBefore = await this.MockWETH.balanceOf(this.ShardsMarket.address);
        assert.equal(balanceBefore, 10);
        var shardPoolInfoBefore = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoBefore[5], 10);//balanceOfWantToken
        var userInfoBefore = await this.ShardsMarket.userInfo.call(1, bob);
        assert.equal(userInfoBefore[0], 10);

        await this.ShardsMarket.redeem(1, 5);

        var balanceAfter = await this.MockWETH.balanceOf(this.ShardsMarket.address);
        assert.equal(balanceAfter, 5);
        var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoAfter[5], 5);
        var userInfoAfter = await this.ShardsMarket.userInfo.call(1, bob);
        assert.equal(userInfoAfter[0], 5);

        var userBalanceAfter = await this.MockWETH.balanceOf(bob);
        assert.equal(userBalanceAfter, 5);
    });
    it('settle fail works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            12,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: 10, from: bob });
        await this.ShardsMarket.setDeadlineForRedeem(0);

        let ownerBefore = await this.NFTToken.ownerOf(100);
        assert.equal(ownerBefore, this.ShardsMarket.address);

        await this.ShardsMarket.settle(1);

        var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoAfter[2], 5);//state

        let ownerAfter = await this.NFTToken.ownerOf(100);
        assert.equal(ownerAfter, bob);
    });
    it('redeemInSubscriptionFailed works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            12,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: 10, from: bob });
        await this.ShardsMarket.setDeadlineForRedeem(0);
        await this.ShardsMarket.settle(1);
        var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoAfter[2], 5);//state

        await this.ShardsMarket.redeemInSubscriptionFailed(1, { from: bob });

        var userInfoAfter = await this.ShardsMarket.userInfo.call(1, bob);
        assert.equal(userInfoAfter[0], 0);

        var userBalanceAfter = await this.MockWETH.balanceOf(bob);
        assert.equal(userBalanceAfter, 10);
    });


    it('settle success works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "10000000000000000000";
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: bob });
        await this.ShardsMarket.setDeadlineForRedeem(0);
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoAfter[2], 1);//state
    });

    it('settle success works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "10000000000000000000";
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: bob });
        await this.ShardsMarket.setDeadlineForRedeem(0);
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoAfter[2], 1);//state
    });



})