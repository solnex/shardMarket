pragma solidity 0.6.12;

import "./interface/IShardsMarket.sol";
import "./interface/IWETH.sol";
import "./interface/ISharedToken.sol";
import "./interface/IUniswapV2Pair.sol";
import "./interface/IUniswapV2Factory.sol";
import "./SharedToken.sol";
import "./libraries/TransferHelper.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721Receiver.sol";
import "./interface/IUniswapV2Router02.sol";

contract ShardsMarket is IShardsMarket, IERC721Receiver {
    using SafeMath for uint256;

    address public immutable router;
    address governance;

    address factory;
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
        uint256 balanceOfETH; //pool抵押总量
        string shardName;
        string shardSymbol;
        uint256 minPrice;
        address nft;
        uint256 totalShardSupply;
        uint256 shardPrice;
        bool isCreatorWithDraw;
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
        uint256 ETHAmount;
    }

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    uint256 private timeSpan = 20;

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
        uint256 minPrice
    ) external override returns (uint256 shardPoolId) {
        require(IERC721(nft).ownerOf(_tokenId) == msg.sender, "UNAUTHORIZED");
        IERC721(nft).safeTransferFrom(msg.sender, address(this), _tokenId);
        if (shardPoolIdCount == 0) {
            shardPoolIdCount = 1;
        }
        shardPoolId = shardPoolIdCount;
        poolInfo[shardPoolId] = shardPool({
            creator: msg.sender,
            tokenId: _tokenId,
            state: ShardsState.Live,
            createTime: block.timestamp,
            shardToken: address(0),
            balanceOfETH: 0,
            shardName: shardName,
            shardSymbol: shardSymbol,
            minPrice: minPrice,
            nft: nft,
            totalShardSupply: totalSupply,
            shardPrice: 0,
            isCreatorWithDraw: false
        });
        allPools.push(shardPoolIdCount);
        shardPoolIdCount = shardPoolIdCount.add(1);
        emit SharedCreated(
            msg.sender,
            nft,
            _tokenId,
            shardName,
            shardSymbol,
            minPrice,
            poolInfo[_tokenId].createTime,
            totalSupply
        );
    }

    function stake(uint256 _shardPoolId, uint256 amount)
        external
        override
        payable
    {
        uint256 createTime = poolInfo[_shardPoolId].createTime;
        require(
            block.timestamp <= createTime.add(deadlineForStaking),
            "NFT:EXPIRED"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
        );
        IWETH(WETH).deposit{value: amount}();
        // assert(IWETH(WETH).transfer(address(this), amount));
        uint256 userBalance = userInfo[_shardPoolId][msg.sender].amount;
        uint256 poolBalance = poolInfo[_shardPoolId].balanceOfETH;
        userInfo[_shardPoolId][msg.sender].amount = userBalance.add(amount);
        poolInfo[_shardPoolId].balanceOfETH = poolBalance.add(amount);
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
        IWETH(WETH).withdraw(amount);
        TransferHelper.safeTransferETH(msg.sender, amount);
        userInfo[_shardPoolId][msg.sender].amount = userInfo[_shardPoolId][msg
            .sender]
            .amount
            .sub(amount);
        poolInfo[_shardPoolId].balanceOfETH = poolInfo[_shardPoolId]
            .balanceOfETH
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
            poolInfo[_shardPoolId].balanceOfETH <
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
        poolInfo[_shardPoolId].balanceOfETH = poolInfo[_shardPoolId]
            .balanceOfETH
            .sub(balance);
        IWETH(WETH).withdraw(balance);
        TransferHelper.safeTransferETH(msg.sender, balance);
    }

    function usersWithdrawShardToken(uint256 _shardPoolId) external override {
        require(
            poolInfo[_shardPoolId].state == ShardsState.Listed,
            "WRONG_STATE"
        );
        uint256 userETH = userInfo[_shardPoolId][msg.sender].amount;
        bool isWithdrawShard = userInfo[_shardPoolId][msg.sender]
            .isWithdrawShard;
        require(userETH > 0 && !isWithdrawShard, "INSUFFIENT BALANCE");
        uint256 shardsForUsers = poolInfo[_shardPoolId]
            .totalShardSupply
            .mul(max.sub(shardsCreatorProportion).sub(platformProportion))
            .div(max);
        uint256 totalETH = poolInfo[_shardPoolId].balanceOfETH;

        uint256 shardAmount = userETH.mul(shardsForUsers).div(totalETH);
        userInfo[_shardPoolId][msg.sender].isWithdrawShard = true;
        ISharedToken(poolInfo[_shardPoolId].shardToken).mint(
            msg.sender,
            shardAmount
        );
    }

    function creatorWithdrawETH(uint256 _shardPoolId) external override {
        require(msg.sender == poolInfo[_shardPoolId].creator, "UNAUTHORIZED");
        require(
            poolInfo[_shardPoolId].state == ShardsState.Listed,
            "WRONG_STATE"
        );
        require(!poolInfo[_shardPoolId].isCreatorWithDraw, "ALREADY WITHDRAW");
        uint256 totalETH = poolInfo[_shardPoolId].balanceOfETH;
        // uint256 platformAmount = poolInfo[_shardPoolId]
        //     .totalSupply
        //     .mul(platformProportion)
        //     .div(max);
        uint256 platformAmount = ISharedToken(poolInfo[_shardPoolId].shardToken)
            .balanceOf(address(this));
        uint256 fee = poolInfo[_shardPoolId].shardPrice.mul(platformAmount);
        uint256 amount = totalETH.sub(fee);
        poolInfo[_shardPoolId].isCreatorWithDraw = true;
        IWETH(WETH).withdraw(amount);
        TransferHelper.safeTransferETH(msg.sender, amount);
    }

    function buyOut(uint256 _shardPoolId, uint256 ETHAmount)
        external
        override
        lock
        returns (uint256 proposalId)
    {
        uint256 shardBalance = ISharedToken(poolInfo[_shardPoolId].shardToken)
            .balanceOf(msg.sender);
        uint256 supply = poolInfo[_shardPoolId].totalShardSupply;
        require(
            shardBalance >= supply.mul(buyOutProportion).div(max),
            "INSUFFIENT BALANCE"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.Live,
            "LIVE STATE IS REQUIRED"
        );
        uint256 currentPrice = getPrice(_shardPoolId);
        require(
            ETHAmount >=
                max.sub(buyOutProportion).mul(supply).mul(currentPrice),
            "INSUFFICIENT ETHAMOUNT"
        );

        TransferHelper.safeTransferFrom(
            WETH,
            msg.sender,
            address(this),
            ETHAmount
        );
        TransferHelper.safeTransferFrom(
            poolInfo[_shardPoolId].shardToken,
            msg.sender,
            address(this),
            shardBalance
        );
        if (proposolIdCount == 0) {
            proposolIdCount = 1;
        }
        proposalId = proposolIdCount;
        proposalIds[_shardPoolId] = proposalId;
        proposals[proposalId] = Proposal({
            votesReceived: 0,
            voteTotal: 0,
            passed: false,
            submitter: msg.sender,
            voteDeadline: block.timestamp.add(voteLenth),
            shardAmount: shardBalance,
            ETHAmount: ETHAmount
        });

        blocked[poolInfo[_shardPoolId].shardToken][msg.sender] = proposalId;
        voted[proposalId][msg.sender] = true;
        proposolIdCount = proposolIdCount.add(1);
        poolInfo[_shardPoolId].state == ShardsState.ApplyforBuyout;
        emit BuyOut(
            msg.sender,
            proposalId,
            _shardPoolId,
            shardBalance,
            ETHAmount,
            proposals[proposalId].voteDeadline
        );
    }

    function vote(uint256 _shardPoolId, bool isAgree) external override {
        uint256 balance = ISharedToken(poolInfo[_shardPoolId].shardToken)
            .balanceOf(msg.sender);
        require(balance >= 0, "INSUFFICIENT VOTERIGHT");
        require(
            poolInfo[_shardPoolId].state == ShardsState.ApplyforBuyout,
            "WRONG STATE"
        );
        uint256 proposalId = proposalIds[_shardPoolId];
        Proposal memory p = proposals[proposalId];
        require(block.timestamp <= p.voteDeadline, "EXPIRED");
        require(voted[proposalId][msg.sender] == false);
        blocked[poolInfo[_shardPoolId].shardToken][msg.sender] = proposalId;
        voted[proposalId][msg.sender] == true;
        if (isAgree) {
            p.votesReceived = p.votesReceived.add(balance);
            p.voteTotal = p.voteTotal.add(balance);
        } else {
            p.voteTotal = p.voteTotal.add(balance);
        }
        emit Vote(msg.sender, proposalId, _shardPoolId, isAgree, balance);
    }

    function voteResultComfirm(uint256 _shardPoolId)
        external
        override
        returns (bool result)
    {
        uint256 proposalId = proposalIds[_shardPoolId];
        Proposal memory p = proposals[proposalId];
        require(msg.sender == p.submitter, "UNAUTHORIZED");
        require(block.timestamp >= p.voteDeadline, "NOT READY");
        require(
            poolInfo[_shardPoolId].state == ShardsState.ApplyforBuyout,
            "WRONG STATE"
        );
        if (p.votesReceived >= p.voteTotal.mul(passNeeded).div(max)) {
            p.passed = true;
            result = true;
            poolInfo[_shardPoolId].state == ShardsState.Buyout;
            ShardToken(poolInfo[_shardPoolId].shardToken).burn(
                msg.sender,
                p.shardAmount
            );
            IERC721(poolInfo[_shardPoolId].nft).safeTransferFrom(
                address(this),
                msg.sender,
                _shardPoolId
            );
        } else {
            p.passed = false;
            result = false;
            poolInfo[_shardPoolId].state == ShardsState.BuyoutFailed;
        }
        emit VoteResultComfirm(proposalId, _shardPoolId, p.passed);
    }

    function exchangeForETH(uint256 _shardPoolId, uint256 shardAmount)
        external
        override
        payable
        returns (uint256 ETHAmount)
    {
        uint256 proposalId = proposalIds[_shardPoolId];
        Proposal memory p = proposals[proposalId];
        require(
            poolInfo[_shardPoolId].state == ShardsState.Buyout,
            "WRONG STATE"
        );

        ShardToken(poolInfo[_shardPoolId].shardToken).burn(
            msg.sender,
            shardAmount
        );
        uint256 supply = poolInfo[_shardPoolId].totalShardSupply;
        uint256 amount = shardAmount.mul(p.ETHAmount).div(
            supply.sub(p.shardAmount)
        );
        IWETH(WETH).withdraw(amount);
        TransferHelper.safeTransferETH(msg.sender, amount);
    }

    function redeemForBuyOutFailed(uint256 _shardPoolId)
        external
        override
        returns (uint256 shardTokenAmount, uint256 ETHAmount)
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
        TransferHelper.safeTransferETH(msg.sender, p.ETHAmount);

        poolInfo[_shardPoolId].state == ShardsState.Live;
    }

    function addLiquidity(
        address token,
        uint256 tokenAmount,
        uint256 ETHAmount
    ) public payable {
        uint256 amountAMin;
        uint256 amountBMin;
        uint256 deadline = block.timestamp.add(timeSpan);
        IWETH(WETH).withdraw(ETHAmount);
        IUniswapV2Router02(router).addLiquidity(
            token,
            WETH,
            tokenAmount,
            ETHAmount,
            amountAMin,
            amountBMin,
            address(this),
            deadline
        );
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
        internal
        returns (uint256 currentPrice)
    {
        address lPTokenAddress = IUniswapV2Factory(factory).getPair(
            poolInfo[_shardPoolId].shardToken,
            WETH
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
        poolInfo[_shardPoolId].shardToken = _deployShardsToken(_shardPoolId);
        poolInfo[_shardPoolId].state == ShardsState.Listed;

        uint256 creatorAmount = poolInfo[_shardPoolId]
            .totalShardSupply
            .mul(shardsCreatorProportion)
            .div(max);
        uint256 platformAmount = poolInfo[_shardPoolId]
            .totalShardSupply
            .mul(platformProportion)
            .div(max);
        ISharedToken(poolInfo[_shardPoolId].shardToken).mint(
            poolInfo[_shardPoolId].creator,
            creatorAmount
        );
        ISharedToken(poolInfo[_shardPoolId].shardToken).mint(
            address(this),
            platformAmount
        );
        uint256 shardPrice = poolInfo[_shardPoolId].balanceOfETH.div(
            poolInfo[_shardPoolId].totalShardSupply.sub(creatorAmount).sub(
                platformAmount
            )
        );
        uint256 ETHforAddLiquidity = shardPrice.mul(platformAmount);
        addLiquidity(
            poolInfo[_shardPoolId].shardToken,
            platformAmount,
            ETHforAddLiquidity
        );
        poolInfo[_shardPoolId].shardPrice = shardPrice;
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
        string memory name = poolInfo[_shardPoolId].shardName;
        string memory symbol = poolInfo[_shardPoolId].shardSymbol;
        bytes memory bytecode = type(ShardToken).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_shardPoolId, symbol, name));
        assembly {
            token := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ISharedToken(token).initialize(_shardPoolId, symbol, name);
    }

    //view
    function getShardPool(uint256 _shardPoolId)
        external
        override
        view
        returns (
            address _creator, //shard创建者
            ShardsState _state, //shared状态
            uint256 _createTime, //创建时间
            address _shardToken, //token地址
            uint256 _balanceOfETH, //pool抵押总量
            string memory _shardName,
            string memory _shardSymbol,
            uint256 _minPrice,
            uint256 _totalShardSupply,
            uint256 _shardPrice,
            bool _isCreatorWithDraw
        )
    {
        _creator = poolInfo[_shardPoolId].creator; //shard创建者
        _state = poolInfo[_shardPoolId].state; //shared状态
        _createTime = poolInfo[_shardPoolId].createTime; //创建时间
        _shardToken = poolInfo[_shardPoolId].shardToken; //token地址
        _balanceOfETH = poolInfo[_shardPoolId].balanceOfETH; //pool抵押总量
        _shardName = poolInfo[_shardPoolId].shardName;
        _shardSymbol = poolInfo[_shardPoolId].shardSymbol;
        _minPrice = poolInfo[_shardPoolId].minPrice;
        _totalShardSupply = poolInfo[_shardPoolId].totalShardSupply;
        _shardPrice = poolInfo[_shardPoolId].shardPrice;
        _isCreatorWithDraw = poolInfo[_shardPoolId].isCreatorWithDraw;
    }

    function getAllPools()
        external
        override
        view
        returns (uint256[] memory _pools)
    {
        _pools = allPools;
    }

    function getProposalState(uint256 _shardPoolId)
        external
        override
        view
        returns (
            uint256 _votesReceived,
            uint256 _voteTotal,
            bool _passed,
            address _submitter,
            uint256 _voteDeadline,
            uint256 _shardAmount,
            uint256 _ETHAmount
        )
    {
        uint256 proposalId = proposalIds[_shardPoolId];
        _votesReceived = proposals[proposalId].votesReceived;
        _voteTotal = proposals[proposalId].voteTotal;
        _passed = proposals[proposalId].passed;
        _submitter = proposals[proposalId].submitter;
        _voteDeadline = proposals[proposalId].voteDeadline;
        _shardAmount = proposals[proposalId].shardAmount;
        _ETHAmount = proposals[proposalId].ETHAmount;
    }

    function getUserInfo(uint256 _shardPoolId)
        external
        override
        view
        returns (uint256 _amount, bool _isWithdrawShard)
    {
        _amount = userInfo[_shardPoolId][msg.sender].amount;
        _isWithdrawShard = userInfo[_shardPoolId][msg.sender].isWithdrawShard;
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
