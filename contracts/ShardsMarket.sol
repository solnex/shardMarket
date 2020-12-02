pragma solidity 0.6.12;

import "./interface/IShardsMarket.sol";
import "./interface/IWETH.sol";
import "./interface/IShardToken.sol";
import "./SharedToken.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/NFTLibrary.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721Receiver.sol";
import "./interface/IUniswapV2Router02.sol";

contract ShardsMarket is IShardsMarket, IERC721Receiver {
    using SafeMath for uint256;

    address private router;
    address private governance;

    address private factory;

    address private dev;

    address private tokenBar;

    //市场的碎片总供应量
    uint256 public override totalSupply = 10000000000000000000000;

    address public immutable WETH;

    //抵押倒计时 60*60*24*5
    uint256 public override deadlineForStake = 432000;
    //赎回倒计时 60*60*24*7
    uint256 public override deadlineForRedeem = 604800;
    //碎片创建者的碎片比例
    uint256 public override shardsCreatorProportion = 5;
    //平台的碎片比例
    uint256 public override platformProportion = 5;

    //买断比例
    uint256 public override buyoutProportion = 15;
    //max
    uint256 private constant max = 100;
    //买断倍数
    uint256 public override buyoutTimes = 1;
    //shardPoolId
    uint256 public shardPoolIdCount;
    //所有的shardpool的Id
    uint256[] private allPools;
    // Info of each pool.
    mapping(uint256 => shardPool) public poolInfo;
    //碎片池
    struct shardPool {
        address creator; //shard创建者
        uint256 tokenId; //nft的tokenID
        ShardsState state; //shared状态
        uint256 createTime; //创建时间
        uint256 deadlineForStake; //抵押deadline
        uint256 deadlineForRedeem; //赎回deadline
        uint256 balanceOfWantToken; //pool抵押总量
        uint256 minWantTokenAmount; //创建者要求的认购最低价格
        address nft; //nft合约地址
        bool isCreatorWithDraw; //创建者是否提取wantToken
        address wantToken; //创建者要求认购的token地址
        uint256 openingPrice;
    }

    mapping(uint256 => shard) public shardInfo;
    struct shard {
        string shardName;
        string shardSymbol;
        address shardToken;
        uint256 totalShardSupply;
        uint256 shardForCreator;
        uint256 shardForPlatform;
        uint256 shardForStakers;
        uint256 burnAmount;
    }

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    struct UserInfo {
        uint256 amount;
        bool isWithdrawShard;
    }

    uint256 public proposolIdCount;

    uint256 public override voteLenth = 259200;

    mapping(uint256 => uint256) public proposalIds;

    mapping(uint256 => uint256[]) private proposalsHistory;

    mapping(uint256 => Proposal) public proposals;

    mapping(uint256 => mapping(address => bool)) public voted;

    mapping(address => mapping(address => uint256)) private blocked;

    uint256 public override passNeeded = 75;

    struct Proposal {
        uint256 votesReceived;
        uint256 voteTotal;
        bool passed;
        address submitter;
        uint256 voteDeadline;
        uint256 shardAmount;
        uint256 wantTokenAmount;
        uint256 buyoutTimes;
        uint256 price;
        bool isSubmitterWithDraw;
        uint256 shardPoolId;
        bool isFailedConfirmed;
        uint256 blockHeight;
        uint256 createTime;
    }

    uint256 private timeSpan = 60;

    bool private buyoutSenderLimit;

    constructor(
        address _WETH,
        address _factory,
        address _governance,
        address _router,
        address _dev,
        address _tokenBar
    ) public {
        WETH = _WETH;
        factory = _factory;
        governance = _governance;
        router = _router;
        dev = _dev;
        tokenBar = _tokenBar;
    }

    function createShard(
        address nft,
        uint256 _tokenId,
        string memory shardName,
        string memory shardSymbol,
        uint256 minWantTokenAmount,
        address wantToken
    ) external override returns (uint256 shardPoolId) {
        require(IERC721(nft).ownerOf(_tokenId) == msg.sender, "UNAUTHORIZED");
        shardPoolId = shardPoolIdCount.add(1);
        poolInfo[shardPoolId] = shardPool({
            creator: msg.sender,
            tokenId: _tokenId,
            state: ShardsState.Live,
            createTime: block.timestamp,
            deadlineForStake: block.timestamp.add(deadlineForStake),
            deadlineForRedeem: block.timestamp.add(deadlineForRedeem),
            balanceOfWantToken: 0,
            minWantTokenAmount: minWantTokenAmount,
            nft: nft,
            isCreatorWithDraw: false,
            wantToken: wantToken,
            openingPrice: 0
        });
        IERC721(nft).safeTransferFrom(msg.sender, address(this), _tokenId);
        uint256 creatorAmount = totalSupply.mul(shardsCreatorProportion).div(
            max
        );
        uint256 platformAmount = totalSupply.mul(platformProportion).div(max);
        uint256 stakersAmount = totalSupply.sub(creatorAmount).sub(
            platformAmount
        );
        shardInfo[shardPoolId] = shard({
            shardName: shardName,
            shardSymbol: shardSymbol,
            shardToken: address(0),
            totalShardSupply: totalSupply,
            shardForCreator: creatorAmount,
            shardForPlatform: platformAmount,
            shardForStakers: stakersAmount,
            burnAmount: 0
        });
        allPools.push(shardPoolId);
        shardPoolIdCount = shardPoolId;
        emit ShardCreated(
            shardPoolId,
            msg.sender,
            nft,
            _tokenId,
            shardName,
            shardSymbol,
            minWantTokenAmount,
            block.timestamp,
            totalSupply,
            wantToken
        );
    }

    function stake(uint256 _shardPoolId, uint256 amount) external override {
        require(
            block.timestamp <= poolInfo[_shardPoolId].deadlineForStake,
            "EXPIRED"
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
        require(
            block.timestamp <= poolInfo[_shardPoolId].deadlineForStake,
            "EXPIRED"
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
            block.timestamp <= poolInfo[_shardPoolId].deadlineForRedeem,
            "EXPIRED"
        );
        // require(
        //     userInfo[_shardPoolId][msg.sender].amount >= amount,
        //     "INSUFFICIENT BALANCE"
        // );
        userInfo[_shardPoolId][msg.sender].amount = userInfo[_shardPoolId][msg
            .sender]
            .amount
            .sub(amount);
        poolInfo[_shardPoolId].balanceOfWantToken = poolInfo[_shardPoolId]
            .balanceOfWantToken
            .sub(amount);
        TransferHelper.safeTransfer(
            poolInfo[_shardPoolId].wantToken,
            msg.sender,
            amount
        );
        emit Redeem(msg.sender, _shardPoolId, amount);
    }

    function settle(uint256 _shardPoolId) external override {
        require(
            block.timestamp > poolInfo[_shardPoolId].deadlineForRedeem,
            "NOT READY"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.Live,
            "LIVE STATE IS REQUIRED"
        );
        if (
            poolInfo[_shardPoolId].balanceOfWantToken <
            poolInfo[_shardPoolId].minWantTokenAmount
        ) {
            poolInfo[_shardPoolId].state = ShardsState.SubscriptionFailed;
            IERC721(poolInfo[_shardPoolId].nft).safeTransferFrom(
                address(this),
                poolInfo[_shardPoolId].creator,
                poolInfo[_shardPoolId].tokenId
            );
            emit SettleFail(_shardPoolId);
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
            "WRONG STATE"
        );
        uint256 balance = userInfo[_shardPoolId][msg.sender].amount;
        require(balance > 0, "INSUFFIENT BALANCE");
        userInfo[_shardPoolId][msg.sender].amount = 0;
        poolInfo[_shardPoolId].balanceOfWantToken = poolInfo[_shardPoolId]
            .balanceOfWantToken
            .sub(balance);
        TransferHelper.safeTransfer(
            poolInfo[_shardPoolId].wantToken,
            msg.sender,
            balance
        );

        emit Redeem(msg.sender, _shardPoolId, balance);
    }

    function usersWithdrawShardToken(uint256 _shardPoolId) external override {
        require(
            poolInfo[_shardPoolId].state == ShardsState.Listed ||
                poolInfo[_shardPoolId].state == ShardsState.Buyout ||
                poolInfo[_shardPoolId].state == ShardsState.ApplyForBuyout,
            "WRONG_STATE"
        );
        uint256 userBanlance = userInfo[_shardPoolId][msg.sender].amount;
        bool isWithdrawShard = userInfo[_shardPoolId][msg.sender]
            .isWithdrawShard;
        require(userBanlance > 0 && !isWithdrawShard, "INSUFFIENT BALANCE");
        uint256 shardsForUsers = shardInfo[_shardPoolId].shardForStakers;
        uint256 totalBalance = poolInfo[_shardPoolId].balanceOfWantToken;
        // formula:
        // shardAmount/shardsForUsers= userBanlance/totalBalance
        //
        uint256 shardAmount = userBanlance.mul(shardsForUsers).div(
            totalBalance
        );
        userInfo[_shardPoolId][msg.sender].isWithdrawShard = true;
        IShardToken(shardInfo[_shardPoolId].shardToken).mint(
            msg.sender,
            shardAmount
        );
    }

    function creatorWithdrawWantToken(uint256 _shardPoolId) external override {
        require(msg.sender == poolInfo[_shardPoolId].creator, "UNAUTHORIZED");
        require(
            poolInfo[_shardPoolId].state == ShardsState.Listed,
            "WRONG STATE"
        );

        require(!poolInfo[_shardPoolId].isCreatorWithDraw, "ALREADY WITHDRAW");
        uint256 totalBalance = poolInfo[_shardPoolId].balanceOfWantToken;
        uint256 platformAmount = shardInfo[_shardPoolId].shardForPlatform;
        uint256 fee = poolInfo[_shardPoolId]
            .balanceOfWantToken
            .mul(platformAmount)
            .div(shardInfo[_shardPoolId].shardForStakers);
        uint256 amount = totalBalance.sub(fee);
        poolInfo[_shardPoolId].isCreatorWithDraw = true;
        TransferHelper.safeTransfer(
            poolInfo[_shardPoolId].wantToken,
            msg.sender,
            amount
        );
        uint256 creatorAmount = shardInfo[_shardPoolId].shardForCreator;
        address shardToken = shardInfo[_shardPoolId].shardToken;
        IShardToken(shardToken).mint(
            poolInfo[_shardPoolId].creator,
            creatorAmount
        );
    }

    function applyForBuyout(uint256 _shardPoolId, uint256 wantTokenAmount)
        external
        override
        returns (uint256 proposalId)
    {
        if (buyoutSenderLimit) {
            require(msg.sender == tx.origin, "INVALID SENDER");
        }
        uint256 shardBalance = IShardToken(shardInfo[_shardPoolId].shardToken)
            .balanceOf(msg.sender);
        uint256 supply = shardInfo[_shardPoolId].totalShardSupply;
        require(
            shardBalance >= supply.mul(buyoutProportion).div(max),
            "INSUFFIENT BALANCE"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.Listed,
            "LISTED STATE IS REQUIRED"
        );
        uint256 currentPrice = getPrice(_shardPoolId);
        uint256 needAmount = supply
            .sub(shardBalance)
            .mul(currentPrice)
            .mul(buyoutTimes)
            .div(1e18);
        require(wantTokenAmount >= needAmount, "INSUFFICIENT WANTTOKENAMOUNT");

        TransferHelper.safeTransferFrom(
            poolInfo[_shardPoolId].wantToken,
            msg.sender,
            address(this),
            wantTokenAmount
        );
        TransferHelper.safeTransferFrom(
            shardInfo[_shardPoolId].shardToken,
            msg.sender,
            address(this),
            shardBalance
        );
        proposalId = proposolIdCount.add(1);
        proposalIds[_shardPoolId] = proposalId;
        uint256 timestamp = block.timestamp.add(voteLenth);
        proposals[proposalId] = Proposal({
            votesReceived: 0,
            voteTotal: 0,
            passed: false,
            submitter: msg.sender,
            voteDeadline: timestamp,
            shardAmount: shardBalance,
            wantTokenAmount: wantTokenAmount,
            buyoutTimes: buyoutTimes,
            price: currentPrice,
            isSubmitterWithDraw: false,
            shardPoolId: _shardPoolId,
            isFailedConfirmed: false,
            blockHeight: block.number,
            createTime: block.timestamp
        });
        proposalsHistory[_shardPoolId].push(proposalId);
        blocked[shardInfo[_shardPoolId].shardToken][msg.sender] = proposalId;
        voted[proposalId][msg.sender] = true;
        proposolIdCount = proposalId;
        poolInfo[_shardPoolId].state = ShardsState.ApplyForBuyout;
        emit ApplyForBuyout(
            msg.sender,
            proposalId,
            _shardPoolId,
            shardBalance,
            wantTokenAmount,
            timestamp,
            buyoutTimes,
            currentPrice,
            block.number
        );
    }

    function vote(uint256 _shardPoolId, bool isAgree) external override {
        uint256 proposalId = proposalIds[_shardPoolId];
        uint256 blockHeight = proposals[proposalId].blockHeight;
        uint256 balance = IShardToken(shardInfo[_shardPoolId].shardToken)
            .getPriorVotes(msg.sender, blockHeight);
        require(balance > 0, "INSUFFICIENT VOTERIGHT");
        require(
            poolInfo[_shardPoolId].state == ShardsState.ApplyForBuyout,
            "WRONG STATE"
        );
        require(
            block.timestamp <= proposals[proposalId].voteDeadline,
            "EXPIRED"
        );
        require(!voted[proposalId][msg.sender], "AlREADY VOTED");
        blocked[shardInfo[_shardPoolId].shardToken][msg.sender] = proposalId;
        voted[proposalId][msg.sender] = true;
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

    function voteResultConfirm(uint256 _shardPoolId)
        external
        override
        returns (bool result)
    {
        uint256 proposalId = proposalIds[_shardPoolId];
        // require(msg.sender == proposals[proposalId].submitter, "UNAUTHORIZED");
        require(
            block.timestamp > proposals[proposalId].voteDeadline,
            "NOT READY"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.ApplyForBuyout,
            "WRONG STATE"
        );
        if (
            proposals[proposalId].votesReceived >=
            proposals[proposalId].voteTotal.mul(passNeeded).div(max) &&
            proposals[proposalId].voteTotal != 0
        ) {
            proposals[proposalId].passed = true;
            result = true;
            poolInfo[_shardPoolId].state = ShardsState.Buyout;
            IShardToken(shardInfo[_shardPoolId].shardToken).burn(
                address(this),
                proposals[proposalId].shardAmount
            );
            shardInfo[_shardPoolId].burnAmount = shardInfo[_shardPoolId]
                .burnAmount
                .add(proposals[proposalId].shardAmount);
            IERC721(poolInfo[_shardPoolId].nft).safeTransferFrom(
                address(this),
                proposals[proposalId].submitter,
                poolInfo[_shardPoolId].tokenId
            );
            _getProfit(_shardPoolId, proposalId);
        } else {
            proposals[proposalId].passed = false;
            proposals[proposalId].isFailedConfirmed = true;
            result = false;
            poolInfo[_shardPoolId].state = ShardsState.Listed;
        }
        emit VoteResultConfirm(proposalId, _shardPoolId, result);
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
            shardInfo[_shardPoolId].shardToken,
            msg.sender,
            address(this),
            shardAmount
        );
        IShardToken(shardInfo[_shardPoolId].shardToken).burn(
            address(this),
            shardAmount
        );
        shardInfo[_shardPoolId].burnAmount = shardInfo[_shardPoolId]
            .burnAmount
            .add(shardAmount);
        uint256 supply = shardInfo[_shardPoolId].totalShardSupply;
        wantTokenAmount = shardAmount.mul(p.wantTokenAmount).div(
            supply.sub(p.shardAmount)
        );
        TransferHelper.safeTransfer(
            poolInfo[_shardPoolId].wantToken,
            msg.sender,
            wantTokenAmount
        );
    }

    function redeemForBuyoutFailed(uint256 _proposalId)
        external
        override
        returns (uint256 shardTokenAmount, uint256 wantTokenAmount)
    {
        Proposal memory p = proposals[_proposalId];
        require(msg.sender == p.submitter, "UNAUTHORIZED");
        require(
            p.isFailedConfirmed && !p.isSubmitterWithDraw && !p.passed,
            "WRONG STATE"
        );
        shardTokenAmount = p.shardAmount;
        wantTokenAmount = p.wantTokenAmount;
        proposals[_proposalId].isSubmitterWithDraw = true;
        TransferHelper.safeTransfer(
            shardInfo[p.shardPoolId].shardToken,
            msg.sender,
            p.shardAmount
        );
        TransferHelper.safeTransfer(
            poolInfo[p.shardPoolId].wantToken,
            msg.sender,
            p.wantTokenAmount
        );
    }

    function getPrice(uint256 _shardPoolId)
        public
        view
        returns (uint256 currentPrice)
    {
        address tokenA = shardInfo[_shardPoolId].shardToken;
        address tokenB = poolInfo[_shardPoolId].wantToken;
        currentPrice = NFTLibrary.getPrice(tokenA, tokenB, factory);
    }

    //  function _failToSetPrice(uint256 _shardPoolId) private {}

    function _successToSetPrice(uint256 _shardPoolId) private {
        address shardToken = _deployShardsToken(_shardPoolId);
        poolInfo[_shardPoolId].state = ShardsState.Listed;
        shardInfo[_shardPoolId].shardToken = shardToken;
        address wantToken = poolInfo[_shardPoolId].wantToken;
        // uint256 creatorAmount = shardInfo[_shardPoolId].shardForCreator;
        uint256 platformAmount = shardInfo[_shardPoolId].shardForPlatform;
        // IShardToken(shardToken).mint(
        //     poolInfo[_shardPoolId].creator,
        //     creatorAmount
        // );
        IShardToken(shardToken).mint(address(this), platformAmount);
        uint256 shardPrice = poolInfo[_shardPoolId]
            .balanceOfWantToken
            .mul(1e18)
            .div(shardInfo[_shardPoolId].shardForStakers);
        //fee= shardPrice * platformAmount =balanceOfWantToken * platformAmount / shardForStakers
        uint256 fee = poolInfo[_shardPoolId]
            .balanceOfWantToken
            .mul(platformAmount)
            .div(shardInfo[_shardPoolId].shardForStakers);
        poolInfo[_shardPoolId].openingPrice = shardPrice;
        //addLiquidity
        TransferHelper.safeApprove(shardToken, router, platformAmount);
        TransferHelper.safeApprove(wantToken, router, fee);
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

        emit SettleSuccess(
            _shardPoolId,
            //creatorAmount,
            platformAmount,
            shardInfo[_shardPoolId].shardForStakers,
            poolInfo[_shardPoolId].balanceOfWantToken,
            fee,
            shardToken
        );
    }

    function _getProfit(uint256 _shardPoolId, uint256 _proposalId) private {
        address shardToken = shardInfo[_shardPoolId].shardToken;
        address wantToken = poolInfo[_shardPoolId].wantToken;

        address lPTokenAddress = NFTLibrary.getPair(
            shardToken,
            wantToken,
            factory
        );
        uint256 LPTokenBalance = NFTLibrary.balanceOf(
            address(this),
            lPTokenAddress
        );
        TransferHelper.safeApprove(lPTokenAddress, router, LPTokenBalance);
        (
            uint256 amountShardToken,
            uint256 amountWantToken
        ) = IUniswapV2Router02(router).removeLiquidity(
            shardToken,
            wantToken,
            LPTokenBalance,
            0,
            0,
            address(this),
            now.add(timeSpan)
        );
        IShardToken(shardInfo[_shardPoolId].shardToken).burn(
            address(this),
            amountShardToken
        );
        shardInfo[_shardPoolId].burnAmount = shardInfo[_shardPoolId]
            .burnAmount
            .add(amountShardToken);
        uint256 supply = shardInfo[_shardPoolId].totalShardSupply;
        uint256 wantTokenAmountForExchange = amountShardToken
            .mul(proposals[_proposalId].wantTokenAmount)
            .div(supply.sub(proposals[_proposalId].shardAmount));
        uint256 totalProfit = amountWantToken.add(wantTokenAmountForExchange);
        uint256 profitForDev = totalProfit.mul(20).div(max);
        uint256 profitForTokenBar = totalProfit.sub(profitForDev);
        TransferHelper.safeTransfer(wantToken, dev, profitForDev);
        TransferHelper.safeTransfer(wantToken, tokenBar, profitForTokenBar);
    }

    function setDeadlineForStake(uint256 _deadlineForStake) external override {
        require(msg.sender == governance, "UNAUTHORIZED");
        deadlineForStake = _deadlineForStake;
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

    function setBuyoutProportion(uint256 _buyoutProportion) external override {
        require(msg.sender == governance, "UNAUTHORIZED");
        buyoutProportion = _buyoutProportion;
    }

    function setBuyoutTimes(uint256 _buyoutTimes) external override {
        require(msg.sender == governance, "UNAUTHORIZED");
        buyoutTimes = _buyoutTimes;
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

    function setBuyoutSenderLimit(bool _buyoutSenderLimit) external {
        require(msg.sender == governance, "UNAUTHORIZED");
        buyoutSenderLimit = _buyoutSenderLimit;
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

    function getProposalsForExactPool(uint256 _shardPoolId)
        external
        view
        returns (uint256[] memory _proposalsHistory)
    {
        _proposalsHistory = proposalsHistory[_shardPoolId];
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
