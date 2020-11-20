
const NFTToken = artifacts.require('NFTToken');
const MockWETH = artifacts.require('MockWETH');
const ShardsMarket = artifacts.require('ShardsMarket');
const MockFactory = artifacts.require('UniswapV2Factory');
const Router = artifacts.require('UniswapV2Router02');
const ShardToken = artifacts.require('ShardToken');
const Pair = artifacts.require('UniswapV2Pair');
const MockERC20Token = artifacts.require('mockERCToken');
const utils = require("./utils");
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
    let dev = accounts[2];
    let tokenBar = accounts[3];
    beforeEach(async () => {
        this.NFTToken = await NFTToken.new("NFT", "NFT", { from: bob });
        this.MockERC20Token = await MockERC20Token.new("ELF", "ELF", { from: bob });
        this.MockWETH = await MockWETH.new({ from: bob });
        this.MockFactory = await MockFactory.new(bob, { from: bob, gas: 6000000 });
        this.Router = await Router.new(this.MockFactory.address, this.MockWETH.address, { from: bob, gas: 6000000 });
        this.ShardsMarket = await ShardsMarket.new(this.MockWETH.address, this.MockFactory.address, bob, this.Router.address, dev, tokenBar, { from: bob, gas: 6500000 });

    });
    it('NFTToken mint works', async () => {
        await this.NFTToken.mint(100);
        let owner = await this.NFTToken.ownerOf(100);
        assert.equal(owner, bob);
    });
    it('createShard works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);

        //UNAUTHORIZED
        utils.assertThrowsAsynchronously(
            () => this.ShardsMarket.createShard(this.NFTToken.address,
                100,
                "myshard",
                "myshard",
                12,
                this.MockWETH.address, { from: alex })
        );

        //success
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            12,
            this.MockWETH.address);
        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[0], bob);

        let owner = await this.NFTToken.ownerOf(100);
        assert.equal(owner, this.ShardsMarket.address);
    });
    it('stake works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);

        await this.NFTToken.mint(101);
        await this.NFTToken.approve(this.ShardsMarket.address, 101);

        await this.ShardsMarket.createShard(this.NFTToken.address,
            101,
            "myshard",
            "myshard",
            12,
            this.MockWETH.address);
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            12,
            this.MockERC20Token.address);
        //stakeETH test

        //UNWANTED
        utils.assertThrowsAsynchronously(
            () => this.ShardsMarket.stakeETH(2, { value: 10, from: bob })
        );
        //success
        await this.ShardsMarket.stakeETH(1, { value: 10, from: bob });

        let balance = await this.MockWETH.balanceOf(this.ShardsMarket.address);
        assert.equal(balance, 10);

        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[6], 10);

        var userInfo = await this.ShardsMarket.userInfo.call(1, bob);
        assert.equal(userInfo[0], 10);


        await this.MockWETH.deposit({ value: 10 });
        await this.MockWETH.approve(this.ShardsMarket.address, 10);
        await this.ShardsMarket.stake(1, 10, { from: bob });

        balance = await this.MockWETH.balanceOf(this.ShardsMarket.address);
        assert.equal(balance, 20);

        shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[6], 20);

        userInfo = await this.ShardsMarket.userInfo.call(1, bob);
        assert.equal(userInfo[0], 20);

        //EXPIRED
        deadlineForStake = 432000 + 20;
        await mine(deadlineForStake); //skip to  deadlineForRedeem
        utils.assertThrowsAsynchronously(
            () => this.ShardsMarket.stakeETH(1, { value: 10, from: bob })
        );
    });
    it('redeem works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            12,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: 10, from: bob });

        var balanceBefore = await this.MockWETH.balanceOf(this.ShardsMarket.address);
        assert.equal(balanceBefore, 10);
        var shardPoolInfoBefore = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoBefore[6], 10);//balanceOfWantToken
        var userInfoBefore = await this.ShardsMarket.userInfo.call(1, bob);
        assert.equal(userInfoBefore[0], 10);

        await this.ShardsMarket.redeem(1, 5);

        var balanceAfter = await this.MockWETH.balanceOf(this.ShardsMarket.address);
        assert.equal(balanceAfter, 5);
        var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoAfter[6], 5);
        var userInfoAfter = await this.ShardsMarket.userInfo.call(1, bob);
        assert.equal(userInfoAfter[0], 5);

        var userBalanceAfter = await this.MockWETH.balanceOf(bob);
        assert.equal(userBalanceAfter, 5);
        //INSUFFICIENT BALANCE
        utils.assertThrowsAsynchronously(
            () => this.ShardsMarket.redeem(1, 10)
        );
        //EXPIRED
        deadlineForRedeem = 604800 + 20;
        await mine(deadlineForRedeem); //skip to  deadlineForRedeem
        utils.assertThrowsAsynchronously(
            () => this.ShardsMarket.redeem(1, 5)
        );
    });
    it('settle fail works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            12,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: 10, from: bob });


        // //NFT:NOT READY
        // utils.assertThrowsAsynchronously(
        //     () => this.ShardsMarket.settle(1)
        // );

        deadlineForRedeem = 604800 + 20;
        await mine(deadlineForRedeem); //skip to  deadlineForRedeem
        await this.ShardsMarket.settle(1);

        var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoAfter[2], 4);//state

        //NFT:LIVE STATE IS REQUIRED
        utils.assertThrowsAsynchronously(
            () => this.ShardsMarket.settle(1)
        );
    });
    it('redeemInSubscriptionFailed works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            12,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: 10, from: bob });
        deadlineForRedeem = 604800 + 20;
        await mine(deadlineForRedeem); //skip to  deadlineForRedeem
        await this.ShardsMarket.settle(1);
        var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoAfter[2], 4);//state

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
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: bob });
        deadlineForRedeem = 604800 + 20;
        await mine(deadlineForRedeem); //skip to  deadlineForRedeem
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoAfter[2], 1);//state

        shardInfo = await this.ShardsMarket.shardInfo.call(1);
        this.ShardToken = await ShardToken.at(shardInfo[2]);

        let owner = await this.NFTToken.ownerOf(100);
        assert.equal(owner, this.ShardsMarket.address);
    });

    it('creatorWithdrawWantToken  works', async () => {
        var code = await this.MockFactory.pairCodeHash.call();
        assert.equal(code, "0x38c4ef24d8dd555cb3831e1dab71bcbe555fc7ffe5d4fd6ba360b0f3700af27b");
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: bob });
        deadlineForRedeem = 604800 + 20;
        await mine(deadlineForRedeem); //skip to  deadlineForRedeem

        //WRONG_STATE
        utils.assertThrowsAsynchronously(
            () => this.ShardsMarket.creatorWithdrawWantToken(1)
        );

        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        var shardPoolInfoAfter = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfoAfter[2], 1);//state


        shardInfo = await this.ShardsMarket.shardInfo.call(1);
        this.ShardToken = await ShardToken.at(shardInfo[2]);
        shardBalance = await this.ShardToken.balanceOf(this.ShardsMarket.address);
        assert.equal(shardBalance, 0);

        //UNAUTHORIZED
        utils.assertThrowsAsynchronously(
            () => this.ShardsMarket.creatorWithdrawWantToken(1, { from: alex })
        );

        await this.ShardsMarket.creatorWithdrawWantToken(1, { gas: 6000000 });

        //ALREADY WITHDRAW"
        utils.assertThrowsAsynchronously(
            () => this.ShardsMarket.creatorWithdrawWantToken(1)
        );

        var userBalanceAfter = await this.MockWETH.balanceOf(bob);

        let shardBalanceForPlatform = 10000 * 0.05;
        var fee = shardBalanceForPlatform * amount / (10000 * 0.9);

        amountExpect = amount - parseInt(fee);

        balance = "944444444444444445";
        assert.equal(userBalanceAfter, amountExpect);
    });
    it('applyForBuyout  works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: alex });
        deadlineForRedeem = 604800 + 20;
        await mine(deadlineForRedeem); //skip to  deadlineForRedeem
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        await this.ShardsMarket.usersWithdrawShardToken(1, { from: alex });

        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        shardInfo = await this.ShardsMarket.shardInfo.call(1);
        var pairAddress = await this.MockFactory.getPair.call(shardInfo[2], shardPoolInfo[10]);
        this.Pair = await Pair.at(pairAddress);
        var reverse = await this.Pair.getReserves.call();
        var reverse0 = reverse[0] / reverse[1] > 1 ? reverse[0] : reverse[1];
        var reverse1 = reverse[0] / reverse[1] > 1 ? reverse[1] : reverse[0];

        assert.equal(reverse0, 500000000000000000000n);
        assert.equal(reverse1, 55555555555555555n);
        this.ShardToken = await ShardToken.at(shardInfo[2]);
        shardBalance = await this.ShardToken.balanceOf(alex);
        // // let amountNeed = parseInt(price) * (10000 * decimals - shardBalance) / decimals;
        let openPrice = parseInt(reverse1 * 1e18 / reverse0);

        amountLimit = "3111111111111110000";
        amountNeed = "222222222222222000";
        assert.equal(shardBalance, 9000000000000000000000n);
        //approve
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: alex });
        await this.MockWETH.deposit({ value: amountLimit, from: alex });
        await this.MockWETH.approve(this.ShardsMarket.address, amountLimit, { from: alex });

        //INSUFFIENT BALANCE
        utils.assertThrowsAsynchronously(
            () => this.ShardsMarket.applyForBuyout(1, amountLimit, { from: bob })
        );

        price = await this.ShardsMarket.getPrice.call(1);
        assert.equal(price, openPrice);
        await this.ShardsMarket.applyForBuyout(1, amountLimit, { from: alex });

        shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[2], 2);//state : applyForBuyout
        assert.equal(shardPoolInfo[11], openPrice);//state : applyForBuyout
        shardBalance = "9000000000000000000000";
        var voteInfo = await this.ShardsMarket.proposals.call(1);
        assert.equal(voteInfo[3], alex); //submmiter:alex
        assert.equal(voteInfo[5], shardBalance); //shardAmount:9000000000000000000000
        assert.equal(voteInfo[6], amountNeed); //wantTokenAmount:3111111111111110000

    });
    it('vote  works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: alex });
        deadlineForRedeem = 604800 + 20;
        await mine(deadlineForRedeem); //skip to  deadlineForRedeem
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        await this.ShardsMarket.usersWithdrawShardToken(1, { from: alex });
        //approve
        shardInfo = await this.ShardsMarket.shardInfo.call(1);
        this.ShardToken = await ShardToken.at(shardInfo[2]);
        shardBalance = await this.ShardToken.balanceOf(alex);

        amountNeed = "3111111111111110000";
        await this.MockWETH.deposit({ value: amountNeed, from: alex });
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: alex });
        await this.MockWETH.approve(this.ShardsMarket.address, amountNeed, { from: alex });


        await this.ShardsMarket.applyForBuyout(1, amountNeed, { from: alex });

        var voteInfo = await this.ShardsMarket.proposals.call(1);
        assert.equal(voteInfo[0], 0); //votesReceived:0
        assert.equal(voteInfo[1], 0); //voteTotal:0

        //vote follow the block height 
        amoutTransfer = "100000000000000000000";
        await this.ShardToken.transfer(accounts[3], amoutTransfer, { from: bob });
        //INSUFFICIENT VOTERIGHT
        utils.assertThrowsAsynchronously(
            () => this.ShardsMarket.vote(1, true, { from: accounts[3] })
        );

        await this.ShardsMarket.vote(1, true, { from: bob });

        shardBalance = await this.ShardToken.balanceOf(bob);
        shardBalanceExpect = "400000000000000000000";
        assert.equal(shardBalance, shardBalanceExpect);

        voteBalanace = await this.ShardToken.getPriorVotes(bob, voteInfo[12]);//blockHeight
        voteBalanaceExpect = "500000000000000000000";
        assert.equal(voteBalanace, voteBalanaceExpect);

        voteInfo = await this.ShardsMarket.proposals.call(1);
        assert.equal(voteInfo[0], voteBalanaceExpect); //votesReceived:0
        assert.equal(voteInfo[1], voteBalanaceExpect); //voteTotal:0
    });

    it('voteResultConfirm success works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: alex });
        deadlineForRedeem = 604800 + 20;
        await mine(deadlineForRedeem); //skip to  deadlineForRedeem
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        await this.ShardsMarket.usersWithdrawShardToken(1, { from: alex });
        //approve
        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        shardInfo = await this.ShardsMarket.shardInfo.call(1);
        this.ShardToken = await ShardToken.at(shardInfo[2]);
        shardBalance = await this.ShardToken.balanceOf(alex);
        amountNeed = "1111111111111110000";
        await this.MockWETH.deposit({ value: amountNeed, from: alex });
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: alex });
        await this.MockWETH.approve(this.ShardsMarket.address, amountNeed, { from: alex });

        await this.ShardsMarket.applyForBuyout(1, amountNeed, { from: alex });
        await this.ShardsMarket.vote(1, true, { from: bob });

        voteInfo = await this.ShardsMarket.proposals.call(1);

        voteLenth = 259200 + 20;
        await mine(voteLenth); //skip to  voteDeadline

        await this.ShardsMarket.voteResultConfirm(1, { from: alex });

        voteInfo = await this.ShardsMarket.proposals.call(1);
        assert.equal(voteInfo[2], true); //passed:true

        shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[2], 3); //state:buyout

        owner = await this.NFTToken.ownerOf(100);
        assert.equal(owner, alex);

        //profit test 
        devProfit = await this.MockWETH.balanceOf(dev, { from: dev });
        tokenBarProfit = await this.MockWETH.balanceOf(tokenBar, { from: tokenBar });
        assert.equal(devProfit, 33333333333333304n);
        assert.equal(tokenBarProfit, 133333333333333218n);
    });
    it('voteResultConfirm fail works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: alex });
        deadlineForRedeem = 604800 + 20;
        await mine(deadlineForRedeem); //skip to  deadlineForRedeem
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        await this.ShardsMarket.usersWithdrawShardToken(1, { from: alex });
        //approve
        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        shardInfo = await this.ShardsMarket.shardInfo.call(1);
        this.ShardToken = await ShardToken.at(shardInfo[2]);
        shardBalance = await this.ShardToken.balanceOf(alex);
        amountNeed = "1111111111111110000";
        await this.MockWETH.deposit({ value: amountNeed, from: alex });
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: alex });
        await this.MockWETH.approve(this.ShardsMarket.address, amountNeed, { from: alex });

        await this.ShardsMarket.applyForBuyout(1, amountNeed, { from: alex });
        await this.ShardsMarket.vote(1, false, { from: bob });

        voteInfo = await this.ShardsMarket.proposals.call(1);

        voteLenth = 259200 + 20
        await mine(voteLenth); //skip to  voteDeadline

        await this.ShardsMarket.voteResultConfirm(1, { from: alex });

        voteInfo = await this.ShardsMarket.proposals.call(1);
        assert.equal(voteInfo[2], false); //passed:true

        shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        assert.equal(shardPoolInfo[2], 1); //state:BuyoutFailed

        owner = await this.NFTToken.ownerOf(100);
        assert.equal(owner, this.ShardsMarket.address);
    });
    it('redeemForBuyoutFailed  works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        let amount = "1000000000000000000";
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: alex });
        deadlineForRedeem = 604800 + 20;
        await mine(deadlineForRedeem); //skip to  deadlineForRedeem
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        await this.ShardsMarket.usersWithdrawShardToken(1, { from: alex });
        //approve
        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        shardInfo = await this.ShardsMarket.shardInfo.call(1);
        this.ShardToken = await ShardToken.at(shardInfo[2]);
        shardBalance = await this.ShardToken.balanceOf(alex);
        amountNeed = "1111111111111110000";
        await this.MockWETH.deposit({ value: amountNeed, from: alex });
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: alex });
        await this.MockWETH.approve(this.ShardsMarket.address, amountNeed, { from: alex });

        await this.ShardsMarket.applyForBuyout(1, amountNeed, { from: alex });
        await this.ShardsMarket.vote(1, false, { from: bob });

        voteInfo = await this.ShardsMarket.proposals.call(1);

        voteLenth = 259200 + 20
        await mine(voteLenth); //skip to  voteDeadline

        await this.ShardsMarket.voteResultConfirm(1, { from: alex });

        await this.ShardsMarket.redeemForBuyoutFailed(1, { from: alex });

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
        await this.ShardsMarket.createShard(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            amount,
            this.MockWETH.address);
        await this.ShardsMarket.stakeETH(1, { value: amount, from: alex });
        deadlineForRedeem = 604800 + 20;
        await mine(deadlineForRedeem); //skip to  deadlineForRedeem
        await this.ShardsMarket.settle(1, { from: bob, gas: 6000000 });
        await this.ShardsMarket.usersWithdrawShardToken(1, { from: alex });
        //approve
        var shardPoolInfo = await this.ShardsMarket.poolInfo.call(1);
        shardInfo = await this.ShardsMarket.shardInfo.call(1);
        this.ShardToken = await ShardToken.at(shardInfo[2]);
        shardBalance = await this.ShardToken.balanceOf(alex);
        amountNeed = "1111111111111110000";
        await this.MockWETH.deposit({ value: amountNeed, from: alex });
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalance, { from: alex });
        await this.MockWETH.approve(this.ShardsMarket.address, amountNeed, { from: alex });

        await this.ShardsMarket.applyForBuyout(1, amountNeed, { from: alex });
        await this.ShardsMarket.vote(1, true, { from: bob });

        voteInfo = await this.ShardsMarket.proposals.call(1);

        voteLenth = 259200 + 20
        await mine(voteLenth); //skip to  voteDeadline

        await this.ShardsMarket.voteResultConfirm(1, { from: alex });
        //approve
        shardBalanceBob = await this.ShardToken.balanceOf(bob);
        await this.ShardToken.approve(this.ShardsMarket.address, shardBalanceBob, { from: bob });
        await this.ShardsMarket.exchangeForWantToken(1, shardBalanceBob, { from: bob });
        shardBalanceBob = await this.ShardToken.balanceOf(bob);
        assert.equal(shardBalanceBob, 0);


    });
})