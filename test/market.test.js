
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
    it('approve with safeErc20', async () => {
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
            12);
        let owner = await this.NFTToken.ownerOf(100);
        assert.equal(owner, this.ShardsMarket.address);
        var shardPoolInfo = await this.ShardsMarket.getShardPool.call(1);
        assert.equal(shardPoolInfo[0], bob);
    });
    it('stake works', async () => {
        await this.NFTToken.mint(100);
        await this.NFTToken.approve(this.ShardsMarket.address, 100);
        await this.ShardsMarket.createShared(this.NFTToken.address,
            100,
            "myshard",
            "myshard",
            12);
        await this.MockWETH.approve(this.ShardsMarket.address, 10);
        await this.ShardsMarket.stake(1, 10);
        var shardPoolInfo = await this.ShardsMarket.getShardPool.call(1);
        assert.equal(shardPoolInfo[4], 10);
    });
})