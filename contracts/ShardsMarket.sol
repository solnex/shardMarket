pragma solidity 0.6.12;

import "./interface/IShardsMarket.sol";
import "./interface/IWETH.sol";
import "./interface/IShardToken.sol";
import "./interface/IUniswapV2Pair.sol";
import "./interface/IUniswapV2Factory.sol";
import "./SharedToken.sol";
import "./libraries/TransferHelper.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721Receiver.sol";
import "./interface/IUniswapV2Router02.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract ShardsMarket is IShardsMarket, IERC721Receiver {
    using SafeMath for uint256;

    address public immutable router;
    address governance;

    address factory;

    uint256 public constant decimals = 1e18;
    //市场的碎片总供应量
    uint256 public override totalSupply = 10000;

    address public immutable WETH;

    //抵押倒计时 60*60*24*5
    uint256 public override deadlineForStaking = 432000;
    //赎回倒计时 60*60*24*7
    uint256 public override deadlineForRedeem = 604800;
    //碎片创建者的碎片比例
    uint256 public override shardsCreatorProportion = 5;
    //平台的碎片比例
    uint256 public override platformProportion = 5;

    //买断比例
    uint256 public override buyOutProportion = 15;
    //max
    uint256 public constant max = 100;
    //买断倍数
    uint256 public override buyOutTimes = 2;
    //shardPoolId
    uint256 public shardPoolIdCount = 0;
    //所有的shardpool的Id
    uint256[] public allPools;
    // Info of each pool.
    mapping(uint256 => shardPool) public poolInfo;
    //碎片池
    struct shardPool {
        address creator; //shard创建者
        uint256 tokenId;
        ShardsState state; //shared状态
        uint256 createTime; //创建时间
        address shardToken; //token地址
        uint256 balanceOfWantToken; //pool抵押总量
        uint256 minPrice;
        address nft;
        uint256 totalShardSupply;
        uint256 shardPrice;
        bool isCreatorWithDraw;
        address wantToken;
    }
    mapping(uint256 => shard) public shardInfo;
    struct shard {
        string shardName;
        string shardSymbol;
    }
    //每个shardpool对应的user信息
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    struct UserInfo {
        uint256 amount;
        bool isWithdrawShard;
    }

    mapping(address => address) public LPToken;
    //id
    uint256 public proposolIdCount = 0;
    //投票时间跨度 60*60*24*3
    uint256 public override voteLenth = 259200;
    //每个NFT对应的投票id
    mapping(uint256 => uint256) public proposalIds;
    //投票
    mapping(uint256 => Proposal) public proposals;
    //用户是否已经投票
    mapping(uint256 => mapping(address => bool)) public voted;
    //代币用户是否被锁定
    mapping(address => mapping(address => uint256)) public blocked;
    //投票通过比例
    uint256 public override passNeeded = 75;

    struct Proposal {
        uint256 votesReceived;
        uint256 voteTotal;
        bool passed;
        address submitter;
        uint256 voteDeadline;
        uint256 shardAmount;
        uint256 wantTokenAmount;
    }

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    uint256 private timeSpan = 60;

    constructor(
        address _WETH,
        address _factory,
        address _governance,
        address _router
    ) public {
        WETH = _WETH;
        factory = _factory;
        governance = _governance;
        router = _router;
    }

    function createShared(
        address nft,
        uint256 _tokenId,
        string memory shardName,
        string memory shardSymbol,
        uint256 minPrice,
        address wantToken
    ) external override returns (uint256 shardPoolId) {
        require(IERC721(nft).ownerOf(_tokenId) == msg.sender, "UNAUTHORIZED");
        IERC721(nft).safeTransferFrom(msg.sender, address(this), _tokenId);
        shardPoolId = shardPoolIdCount.add(1);
        poolInfo[shardPoolId] = shardPool({
            creator: msg.sender,
            tokenId: _tokenId,
            state: ShardsState.Live,
            createTime: block.timestamp,
            shardToken: address(0),
            balanceOfWantToken: 0,
            minPrice: minPrice,
            nft: nft,
            totalShardSupply: totalSupply,
            shardPrice: 0,
            isCreatorWithDraw: false,
            wantToken: wantToken
        });
        shardInfo[shardPoolId] = shard({
            shardName: shardName,
            shardSymbol: shardSymbol
        });
        allPools.push(shardPoolId);
        shardPoolIdCount = shardPoolId;
        emit SharedCreated(
            msg.sender,
            nft,
            _tokenId,
            shardName,
            shardSymbol,
            minPrice,
            poolInfo[_tokenId].createTime,
            totalSupply,
            wantToken
        );
    }

    function stake(uint256 _shardPoolId, uint256 amount) external override {
        uint256 createTime = poolInfo[_shardPoolId].createTime;
        require(
            block.timestamp <= createTime.add(deadlineForStaking),
            "NFT:EXPIRED"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
        );
        address wantToken = poolInfo[_shardPoolId].wantToken;
        TransferHelper.safeTransferFrom(
            wantToken,
            msg.sender,
            address(this),
            amount
        );
        _stake(_shardPoolId, amount);
    }

    function stakeETH(uint256 _shardPoolId) external override payable {
        uint256 createTime = poolInfo[_shardPoolId].createTime;
        require(
            block.timestamp <= createTime.add(deadlineForStaking),
            "NFT:EXPIRED"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
        );
        require(poolInfo[_shardPoolId].wantToken == WETH, "UNWANTED");
        IWETH(WETH).deposit{value: msg.value}();
        _stake(_shardPoolId, msg.value);
    }

    function _stake(uint256 _shardPoolId, uint256 amount) private {
        userInfo[_shardPoolId][msg.sender].amount = userInfo[_shardPoolId][msg
            .sender]
            .amount
            .add(amount);
        poolInfo[_shardPoolId].balanceOfWantToken = poolInfo[_shardPoolId]
            .balanceOfWantToken
            .add(amount);
        emit Stake(msg.sender, _shardPoolId, amount);
    }

    function redeem(uint256 _shardPoolId, uint256 amount) external override {
        require(
            block.timestamp <=
                poolInfo[_shardPoolId].createTime.add(deadlineForRedeem),
            "NFT:EXPIRED"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
        );
        require(
            userInfo[_shardPoolId][msg.sender].amount >= amount,
            "INSUFFICIENT BALANCE"
        );
        IERC20(poolInfo[_shardPoolId].wantToken).transfer(msg.sender, amount);

        userInfo[_shardPoolId][msg.sender].amount = userInfo[_shardPoolId][msg
            .sender]
            .amount
            .sub(amount);
        poolInfo[_shardPoolId].balanceOfWantToken = poolInfo[_shardPoolId]
            .balanceOfWantToken
            .sub(amount);
        emit Redeem(msg.sender, _shardPoolId, amount);
    }

    function settle(uint256 _shardPoolId) external override {
        require(
            block.timestamp >=
                poolInfo[_shardPoolId].createTime.add(deadlineForRedeem),
            "NFT:NOT READY"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
        );
        if (
            poolInfo[_shardPoolId].balanceOfWantToken <
            poolInfo[_shardPoolId].minPrice
        ) {
            _failToSetPrice(_shardPoolId);
        } else {
            _successToSetPrice(_shardPoolId);
        }
    }

    function redeemInSubscriptionFailed(uint256 _shardPoolId)
        external
        override
    {
        require(
            poolInfo[_shardPoolId].state == ShardsState.SubscriptionFailed,
            "WRONG_STATE"
        );
        uint256 balance = userInfo[_shardPoolId][msg.sender].amount;
        require(balance > 0, "INSUFFIENT BALANCE");
        userInfo[_shardPoolId][msg.sender].amount = 0;
        poolInfo[_shardPoolId].balanceOfWantToken = poolInfo[_shardPoolId]
            .balanceOfWantToken
            .sub(balance);
        IERC20(poolInfo[_shardPoolId].wantToken).transfer(msg.sender, balance);
        emit Redeem(msg.sender, _shardPoolId, balance);
    }

    function usersWithdrawShardToken(uint256 _shardPoolId) external override {
        require(
            poolInfo[_shardPoolId].state == ShardsState.Listed,
            "WRONG_STATE"
        );
        uint256 userBanlance = userInfo[_shardPoolId][msg.sender].amount;
        bool isWithdrawShard = userInfo[_shardPoolId][msg.sender]
            .isWithdrawShard;
        require(userBanlance > 0 && !isWithdrawShard, "INSUFFIENT BALANCE");
        uint256 shardsForUsers = poolInfo[_shardPoolId]
            .totalShardSupply
            .mul(decimals)
            .mul(max.sub(shardsCreatorProportion).sub(platformProportion))
            .div(max);
        uint256 totalBalance = poolInfo[_shardPoolId].balanceOfWantToken;

        uint256 shardAmount = userBanlance.mul(shardsForUsers).div(
            totalBalance
        );
        userInfo[_shardPoolId][msg.sender].isWithdrawShard = true;
        IShardToken(poolInfo[_shardPoolId].shardToken).mint(
            msg.sender,
            shardAmount
        );
    }

    function creatorWithdrawWantToken(uint256 _shardPoolId) external override {
        require(msg.sender == poolInfo[_shardPoolId].creator, "UNAUTHORIZED");
        require(
            poolInfo[_shardPoolId].state == ShardsState.Listed,
            "WRONG_STATE"
        );
        address shardToken = poolInfo[_shardPoolId].shardToken;
        address wantToken = poolInfo[_shardPoolId].wantToken;

        require(!poolInfo[_shardPoolId].isCreatorWithDraw, "ALREADY WITHDRAW");
        uint256 totalBalance = poolInfo[_shardPoolId].balanceOfWantToken;
        uint256 platformAmount = poolInfo[_shardPoolId]
            .totalShardSupply
            .mul(decimals)
            .mul(platformProportion)
            .div(max);
        uint256 fee = poolInfo[_shardPoolId].shardPrice.mul(platformAmount).div(
            decimals
        );
        uint256 amount = totalBalance.sub(fee);
        poolInfo[_shardPoolId].isCreatorWithDraw = true;
        IERC20(wantToken).transfer(msg.sender, amount);
    }

    function applyforBuyout(uint256 _shardPoolId, uint256 wantTokenAmount)
        external
        override
        lock
        returns (uint256 proposalId)
    {
        uint256 shardBalance = IShardToken(poolInfo[_shardPoolId].shardToken)
            .balanceOf(msg.sender);
        uint256 supply = poolInfo[_shardPoolId].totalShardSupply;
        require(
            shardBalance >= supply.mul(decimals).mul(buyOutProportion).div(max),
            "INSUFFIENT BALANCE"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.Listed,
            "LISTED STATE IS REQUIRED"
        );
        uint256 currentPrice = getPrice(_shardPoolId);
        require(
            wantTokenAmount >=
                supply.mul(decimals).sub(shardBalance).mul(currentPrice).div(
                    decimals
                ),
            "INSUFFICIENT wantTokenAmount"
        );

        TransferHelper.safeTransferFrom(
            poolInfo[_shardPoolId].wantToken,
            msg.sender,
            address(this),
            wantTokenAmount
        );
        TransferHelper.safeTransferFrom(
            poolInfo[_shardPoolId].shardToken,
            msg.sender,
            address(this),
            shardBalance
        );
        proposalId = proposolIdCount.add(1);
        proposalIds[_shardPoolId] = proposalId;
        proposals[proposalId] = Proposal({
            votesReceived: 0,
            voteTotal: 0,
            passed: false,
            submitter: msg.sender,
            voteDeadline: block.timestamp.add(voteLenth),
            shardAmount: shardBalance,
            wantTokenAmount: wantTokenAmount
        });

        blocked[poolInfo[_shardPoolId].shardToken][msg.sender] = proposalId;
        voted[proposalId][msg.sender] = true;
        proposolIdCount = proposalId;
        poolInfo[_shardPoolId].state = ShardsState.ApplyforBuyout;
        emit ApplyforBuyout(
            msg.sender,
            proposalId,
            _shardPoolId,
            shardBalance,
            wantTokenAmount,
            proposals[proposalId].voteDeadline
        );
    }

    function vote(uint256 _shardPoolId, bool isAgree) external override {
        uint256 balance = IShardToken(poolInfo[_shardPoolId].shardToken)
            .balanceOf(msg.sender);
        require(balance >= 0, "INSUFFICIENT VOTERIGHT");
        require(
            poolInfo[_shardPoolId].state == ShardsState.ApplyforBuyout,
            "WRONG STATE"
        );
        uint256 proposalId = proposalIds[_shardPoolId];
        require(
            block.timestamp <= proposals[proposalId].voteDeadline,
            "EXPIRED"
        );
        require(voted[proposalId][msg.sender] == false);
        blocked[poolInfo[_shardPoolId].shardToken][msg.sender] = proposalId;
        voted[proposalId][msg.sender] == true;
        if (isAgree) {
            proposals[proposalId].votesReceived = proposals[proposalId]
                .votesReceived
                .add(balance);
            proposals[proposalId].voteTotal = proposals[proposalId]
                .voteTotal
                .add(balance);
        } else {
            proposals[proposalId].voteTotal = proposals[proposalId]
                .voteTotal
                .add(balance);
        }
        emit Vote(msg.sender, proposalId, _shardPoolId, isAgree, balance);
    }

    function voteResultComfirm(uint256 _shardPoolId)
        external
        override
        returns (bool result)
    {
        uint256 proposalId = proposalIds[_shardPoolId];
        require(msg.sender == proposals[proposalId].submitter, "UNAUTHORIZED");
        require(
            block.timestamp >= proposals[proposalId].voteDeadline,
            "NOT READY"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.ApplyforBuyout,
            "WRONG STATE"
        );
        if (
            proposals[proposalId].votesReceived >=
            proposals[proposalId].voteTotal.mul(passNeeded).div(max)
        ) {
            proposals[proposalId].passed = true;
            result = true;
            poolInfo[_shardPoolId].state = ShardsState.Buyout;
            IShardToken(poolInfo[_shardPoolId].shardToken).burn(
                address(this),
                proposals[proposalId].shardAmount
            );
            IERC721(poolInfo[_shardPoolId].nft).safeTransferFrom(
                address(this),
                msg.sender,
                poolInfo[_shardPoolId].tokenId
            );
        } else {
            proposals[proposalId].passed = false;
            result = false;
            poolInfo[_shardPoolId].state = ShardsState.BuyoutFailed;
        }
        emit VoteResultComfirm(
            proposalId,
            _shardPoolId,
            proposals[proposalId].passed
        );
    }

    function exchangeForWantToken(uint256 _shardPoolId, uint256 shardAmount)
        external
        override
        returns (uint256 wantTokenAmount)
    {
        uint256 proposalId = proposalIds[_shardPoolId];
        Proposal memory p = proposals[proposalId];
        require(
            poolInfo[_shardPoolId].state == ShardsState.Buyout,
            "WRONG STATE"
        );
        TransferHelper.safeTransferFrom(
            poolInfo[_shardPoolId].shardToken,
            msg.sender,
            address(this),
            shardAmount
        );
        ShardToken(poolInfo[_shardPoolId].shardToken).burn(
            address(this),
            shardAmount
        );
        uint256 supply = poolInfo[_shardPoolId].totalShardSupply.mul(decimals);
        wantTokenAmount = shardAmount.mul(p.wantTokenAmount).div(
            supply.sub(p.shardAmount)
        );
        TransferHelper.safeTransfer(
            poolInfo[_shardPoolId].wantToken,
            msg.sender,
            wantTokenAmount
        );
    }

    function redeemForBuyOutFailed(uint256 _shardPoolId)
        external
        override
        returns (uint256 shardTokenAmount, uint256 wantTokenAmount)
    {
        uint256 proposalId = proposalIds[_shardPoolId];
        Proposal memory p = proposals[proposalId];
        require(msg.sender == p.submitter, "UNAUTHORIZED");
        require(
            poolInfo[_shardPoolId].state == ShardsState.BuyoutFailed &&
                p.passed == false,
            "WRONG_STATE"
        );
        TransferHelper.safeTransfer(
            poolInfo[_shardPoolId].shardToken,
            msg.sender,
            p.shardAmount
        );
        TransferHelper.safeTransfer(
            poolInfo[_shardPoolId].wantToken,
            msg.sender,
            p.wantTokenAmount
        );

        poolInfo[_shardPoolId].state = ShardsState.Listed;
    }

    function addLiquidity(
        address shardToken,
        uint256 shardTokenAmount,
        address wantToken,
        uint256 wantTokenAmount
    ) public {
        uint256 amountAMin;
        uint256 amountBMin;
        uint256 deadline = block.timestamp.add(timeSpan);
        IUniswapV2Router02(router).addLiquidity(
            shardToken,
            wantToken,
            shardTokenAmount,
            wantTokenAmount,
            amountAMin,
            amountBMin,
            address(this),
            deadline
        );
    }

    //for test
    function getShardBalance(address shardToken, address user)
        public
        view
        returns (uint256 balance)
    {
        balance = ShardToken(shardToken).balanceOf(user);
    }

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, "UniswapV2Library: INSUFFICIENT_AMOUNT");
        require(
            reserveA > 0 && reserveB > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        amountB = amountA.mul(reserveB) / reserveA;
    }

    function getPrice(uint256 _shardPoolId)
        public
        view
        returns (uint256 currentPrice)
    {
        address lPTokenAddress = IUniswapV2Factory(factory).getPair(
            poolInfo[_shardPoolId].shardToken,
            poolInfo[_shardPoolId].wantToken
        );
        (uint112 _reserve0, uint112 _reserve1, ) = IUniswapV2Pair(
            lPTokenAddress
        )
            .getReserves();
        currentPrice = quote(1, _reserve1, _reserve0);
    }

    function _failToSetPrice(uint256 _shardPoolId) private {
        poolInfo[_shardPoolId].state = ShardsState.SubscriptionFailed;
        IERC721(poolInfo[_shardPoolId].nft).safeTransferFrom(
            address(this),
            poolInfo[_shardPoolId].creator,
            poolInfo[_shardPoolId].tokenId
        );
        emit SettleFail(_shardPoolId);
    }

    function _successToSetPrice(uint256 _shardPoolId) private {
        address shardToken = _deployShardsToken(_shardPoolId);
        poolInfo[_shardPoolId].state = ShardsState.Listed;
        poolInfo[_shardPoolId].shardToken = shardToken;
        address wantToken = poolInfo[_shardPoolId].wantToken;
        uint256 creatorAmount = poolInfo[_shardPoolId]
            .totalShardSupply
            .mul(decimals)
            .mul(shardsCreatorProportion)
            .div(max);
        uint256 platformAmount = poolInfo[_shardPoolId]
            .totalShardSupply
            .mul(decimals)
            .mul(platformProportion)
            .div(max);
        IShardToken(shardToken).mint(
            poolInfo[_shardPoolId].creator,
            creatorAmount
        );
        IShardToken(shardToken).mint(address(this), platformAmount);
        uint256 shardPrice = poolInfo[_shardPoolId].balanceOfWantToken.div(
            poolInfo[_shardPoolId]
                .totalShardSupply
                .sub(creatorAmount.div(decimals))
                .sub(platformAmount.div(decimals))
        );
        poolInfo[_shardPoolId].shardPrice = shardPrice;
        uint256 fee = poolInfo[_shardPoolId].shardPrice.mul(platformAmount).div(
            decimals
        );
        //addLiquidity
        IERC20(shardToken).approve(router, platformAmount);
        IERC20(wantToken).approve(router, fee);
        IUniswapV2Router02(router).addLiquidity(
            shardToken,
            wantToken,
            platformAmount,
            fee,
            0,
            0,
            address(this),
            now.add(timeSpan)
        );

        emit SettleSuccess(_shardPoolId, shardPrice);
    }

    function setDeadlineForStaking(uint256 _deadlineForStaking)
        external
        override
    {
        require(msg.sender == governance, "UNAUTHORIZED");
        deadlineForStaking = _deadlineForStaking;
    }

    function setDeadlineForRedeem(uint256 _deadlineForRedeem)
        external
        override
    {
        require(msg.sender == governance, "UNAUTHORIZED");
        deadlineForRedeem = _deadlineForRedeem;
    }

    function setShardsCreatorProportion(uint256 _shardsCreatorProportion)
        external
        override
    {
        require(msg.sender == governance, "UNAUTHORIZED");
        shardsCreatorProportion = _shardsCreatorProportion;
    }

    function setPlatformProportion(uint256 _platformProportion)
        external
        override
    {
        require(msg.sender == governance, "UNAUTHORIZED");
        platformProportion = _platformProportion;
    }

    function setBuyOutProportion(uint256 _buyOutProportion) external override {
        require(msg.sender == governance, "UNAUTHORIZED");
        buyOutProportion = _buyOutProportion;
    }

    function setBuyOutTimes(uint256 _buyOutTimes) external override {
        require(msg.sender == governance, "UNAUTHORIZED");
        buyOutTimes = _buyOutTimes;
    }

    function setVoteLenth(uint256 _voteLenth) external override {
        require(msg.sender == governance, "UNAUTHORIZED");
        voteLenth = _voteLenth;
    }

    function setPassNeeded(uint256 _passNeeded) external override {
        require(msg.sender == governance, "UNAUTHORIZED");
        passNeeded = _passNeeded;
    }

    function setTotalSupply(uint256 _totalSupply) external override {
        require(msg.sender == governance, "UNAUTHORIZED");
        totalSupply = _totalSupply;
    }

    function _deployShardsToken(uint256 _shardPoolId)
        private
        returns (address token)
    {
        string memory name = shardInfo[_shardPoolId].shardName;
        string memory symbol = shardInfo[_shardPoolId].shardSymbol;
        bytes memory bytecode = type(ShardToken).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_shardPoolId, symbol, name));
        assembly {
            token := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IShardToken(token).initialize(
            poolInfo[_shardPoolId].tokenId,
            symbol,
            name
        );
    }

    function getAllPools() external view returns (uint256[] memory _pools) {
        _pools = allPools;
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external override returns (bytes4) {
        _operator;
        _from;
        _tokenId;
        _data;
        return 0x150b7a02;
    }
}
