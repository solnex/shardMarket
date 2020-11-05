
const NFTToken = artifacts.require('NFTToken');
const MockWETH = artifacts.require('MockWETH');
const ShardsMarket = artifacts.require('ShardsMarket');
const MockFactory = artifacts.require('UniswapV2Factory');
const Router = artifacts.require('UniswapV2Router02');
const ShardToken = artifacts.require('ShardToken');
const Pair = artifacts.require('UniswapV2Pair');
const decimals = "1000000000000000000";
const mine = (timestamp) => {
    return new Promise((resolve, reject) => {
        web3.currentProvider.send({
            jsonrpc: '2.0',
            method: 'evm_increaseTime',
            id: Date.now(),
            params: [timestamp],
        }, (err, res) => {
            if (err) return reject(err)
            resolve(res)
        })
    })
}

contract('NFTToken', (accounts) => {
    let bob = accounts[0];
    let alex = accounts[1];
    beforeEach(async () => {
        this.NFTToken = await NFTToken.new("NFT", "NFT", { from: bob });
        this.MockWETH = await MockWETH.new({ from: bob });
        this.MockFactory = await MockFactory.new(bob, { from: bob, gas: 6000000 });
        this.Router = await Router.new(this.MockFactory.address, this.MockWETH.address, { from: bob, gas: 6000000 });
        this.ShardsMarket = await ShardsMarket.new(this.MockWETH.address, this.MockFactory.address, bob, this.Router.address, { from: bob, gas: 6000000 });

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
        let amount = "1000000000000000000";
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
        var shardBalance = await this.ShardsMarket.getShardBalance.call(shardPoolInfoAfter[4], bob);

        assert.equal(shardBalance, 500 * 1e18);
    });

    it('creatorWithdrawWantToken  works', async () => {
        var code = await this.MockFactory.pairCodeHash.call();
        assert.equal(code, "0x38c4ef24d8dd555cb3831e1dab71bcbe555fc7ffe5d4fd6ba360b0f3700af27b");
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
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

        this.ShardToken = await ShardToken.at(shardPoolInfoAfter[4]);
        shardBalance = await this.ShardToken.balanceOf(this.ShardsMarket.address);
        assert.equal(shardBalance, 0);

        var price = amount / (10000 * 0.9);
        assert.equal(shardPoolInfoAfter[9], parseInt(price));

        await this.ShardsMarket.creatorWithdrawWantToken(1, { gas: 6000000 });

        var userBalanceAfter = await this.MockWETH.balanceOf(bob);

        let shardBalanceForPlatform = 10000 * 0.05 * decimals;
        var fee = shardBalanceForPlatform * parseInt(price) / decimals;

        amountExpect = amount - parseInt(fee);
        assert.equal(userBalanceAfter, amountExpect);
    });
    it('applyforBuyout  works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: alex });
        await this.ShardsMarket.setDeadlineForRedeem(0);
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        await this.ShardsMarket.usersWithdrawShardToken(1, { from: alex });

        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);

        var pairAddress = await this.MockFactory.getPair.call(shardPoolInfo[4], shardPoolInfo[11]);
        this.Pair = await Pair.at(pairAddress);
        var reverse = await this.Pair.getReserves.call();
        var reverse0 = reverse[0] / reverse[1] > 1 ? reverse[0] : reverse[1];
        var reverse1 = reverse[0] / reverse[1] > 1 ? reverse[1] : reverse[0];
        assert.equal(reverse0, 500000000000000000000);
        assert.equal(reverse1, 55555555555555500);
        var price = amount * reverse1 / reverse0;
        assert.equal(shardPoolInfo[9], parseInt(price));

        this.ShardToken = await ShardToken.at(shardPoolInfo[4]);
        shardBalance = await this.ShardToken.balanceOf(alex);
        let amountNeed = parseInt(price) * (10000 * decimals - shardBalance) / decimals;
        amountNeed = "1111111111111110000";
        //approve
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: alex });
        await this.MockWETH.deposit({ value: amountNeed, from: alex });
        await this.MockWETH.approve(this.ShardsMarket.address, amountNeed, { from: alex });


        await this.ShardsMarket.applyforBuyout(1, amountNeed, { from: alex });

        shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[2], 2);//state : ApplyforBuyout
        shardBalance = "9000000000000000000000";
        var voteInfo = await this.ShardsMarket.proposals.call(1);
        assert.equal(voteInfo[3], alex); //submmiter:alex
        assert.equal(voteInfo[5], shardBalance); //shardAmount:alex
        assert.equal(voteInfo[6], amountNeed); //wantTokenAmount:alex

    });
    it('vote  works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: alex });
        await this.ShardsMarket.setDeadlineForRedeem(0);
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        await this.ShardsMarket.usersWithdrawShardToken(1, { from: alex });
        //approve
        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        this.ShardToken = await ShardToken.at(shardPoolInfo[4]);
        shardBalance = await this.ShardToken.balanceOf(alex);
        amountNeed = "1111111111111110000";
        await this.MockWETH.deposit({ value: amountNeed, from: alex });
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: alex });
        await this.MockWETH.approve(this.ShardsMarket.address, amountNeed, { from: alex });


        await this.ShardsMarket.applyforBuyout(1, amountNeed, { from: alex });

        var voteInfo = await this.ShardsMarket.proposals.call(1);
        assert.equal(voteInfo[0], 0); //votesReceived:0
        assert.equal(voteInfo[1], 0); //voteTotal:0
        await this.ShardsMarket.vote(1, true, { from: bob });

        this.ShardToken = await ShardToken.at(shardPoolInfo[4]);
        shardBalance = await this.ShardToken.balanceOf(bob);
        shardBalance = "500000000000000000000";
        voteInfo = await this.ShardsMarket.proposals.call(1);
        assert.equal(voteInfo[0], shardBalance); //votesReceived:0
        assert.equal(voteInfo[1], shardBalance); //voteTotal:0
    });

    it('voteResultComfirm success works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: alex });
        await this.ShardsMarket.setDeadlineForRedeem(0);
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        await this.ShardsMarket.usersWithdrawShardToken(1, { from: alex });
        //approve
        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        this.ShardToken = await ShardToken.at(shardPoolInfo[4]);
        shardBalance = await this.ShardToken.balanceOf(alex);
        amountNeed = "1111111111111110000";
        await this.MockWETH.deposit({ value: amountNeed, from: alex });
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: alex });
        await this.MockWETH.approve(this.ShardsMarket.address, amountNeed, { from: alex });

        await this.ShardsMarket.applyforBuyout(1, amountNeed, { from: alex });
        await this.ShardsMarket.vote(1, true, { from: bob });

        voteInfo = await this.ShardsMarket.proposals.call(1);

        voteLenth = 259200
        await mine(voteLenth); //skip to  voteDeadline

        await this.ShardsMarket.voteResultComfirm(1, { from: alex });

        voteInfo = await this.ShardsMarket.proposals.call(1);
        assert.equal(voteInfo[2], true); //passed:true

        shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[2], 3); //state:buyout

        owner = await this.NFTToken.ownerOf(100);
        assert.equal(owner, alex);
    });
    it('voteResultComfirm fail works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: alex });
        await this.ShardsMarket.setDeadlineForRedeem(0);
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        await this.ShardsMarket.usersWithdrawShardToken(1, { from: alex });
        //approve
        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        this.ShardToken = await ShardToken.at(shardPoolInfo[4]);
        shardBalance = await this.ShardToken.balanceOf(alex);
        amountNeed = "1111111111111110000";
        await this.MockWETH.deposit({ value: amountNeed, from: alex });
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: alex });
        await this.MockWETH.approve(this.ShardsMarket.address, amountNeed, { from: alex });

        await this.ShardsMarket.applyforBuyout(1, amountNeed, { from: alex });
        await this.ShardsMarket.vote(1, false, { from: bob });

        voteInfo = await this.ShardsMarket.proposals.call(1);

        voteLenth = 259200
        await mine(voteLenth); //skip to  voteDeadline

        await this.ShardsMarket.voteResultComfirm(1, { from: alex });

        voteInfo = await this.ShardsMarket.proposals.call(1);
        assert.equal(voteInfo[2], false); //passed:true

        shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[2], 4); //state:BuyoutFailed

        owner = await this.NFTToken.ownerOf(100);
        assert.equal(owner, this.ShardsMarket.address);
    });
    it('redeemForBuyOutFailed  works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: alex });
        await this.ShardsMarket.setDeadlineForRedeem(0);
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        await this.ShardsMarket.usersWithdrawShardToken(1, { from: alex });
        //approve
        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        this.ShardToken = await ShardToken.at(shardPoolInfo[4]);
        shardBalance = await this.ShardToken.balanceOf(alex);
        amountNeed = "1111111111111110000";
        await this.MockWETH.deposit({ value: amountNeed, from: alex });
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: alex });
        await this.MockWETH.approve(this.ShardsMarket.address, amountNeed, { from: alex });

        await this.ShardsMarket.applyforBuyout(1, amountNeed, { from: alex });
        await this.ShardsMarket.vote(1, false, { from: bob });

        voteInfo = await this.ShardsMarket.proposals.call(1);

        voteLenth = 259200
        await mine(voteLenth); //skip to  voteDeadline

        await this.ShardsMarket.voteResultComfirm(1, { from: alex });

        await this.ShardsMarket.redeemForBuyOutFailed(1, { from: alex });

        shardBalanceNew = await this.ShardToken.balanceOf(alex);
        assert.equal(shardBalanceNew, 9e+21);
        ETHBalance = await this.MockWETH.balanceOf(alex);
        assert.equal(ETHBalance, amountNeed);

        shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[2], 1); //state:listed

        owner = await this.NFTToken.ownerOf(100);
        assert.equal(owner, this.ShardsMarket.address);
    });

    it('exchangeForWantToken  works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: alex });
        await this.ShardsMarket.setDeadlineForRedeem(0);
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        await this.ShardsMarket.usersWithdrawShardToken(1, { from: alex });
        //approve
        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        this.ShardToken = await ShardToken.at(shardPoolInfo[4]);
        shardBalance = await this.ShardToken.balanceOf(alex);
        amountNeed = "1111111111111110000";
        await this.MockWETH.deposit({ value: amountNeed, from: alex });
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: alex });
        await this.MockWETH.approve(this.ShardsMarket.address, amountNeed, { from: alex });

        await this.ShardsMarket.applyforBuyout(1, amountNeed, { from: alex });
        await this.ShardsMarket.vote(1, true, { from: bob });

        voteInfo = await this.ShardsMarket.proposals.call(1);

        voteLenth = 259200
        await mine(voteLenth); //skip to  voteDeadline

        await this.ShardsMarket.voteResultComfirm(1, { from: alex });
        //approve
        shardBalanceBob = await this.ShardToken.balanceOf(bob);
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalanceBob, { from: bob });
        await this.ShardsMarket.exchangeForWantToken(1, shardBalanceBob, { from: bob });
        shardBalanceBob = await this.ShardToken.balanceOf(bob);
        assert.equal(shardBalanceBob, 0);


    });
})