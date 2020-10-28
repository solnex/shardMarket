pragma solidity 0.6.12;

import "./interface/IShardsMarket.sol";
import "./interface/IWETH.sol";
import "./interface/ISharedToken.sol";
import "./interface/IUniswapV2Pair.sol";
import "./interface/ERC721.sol";
import "./interface/IUniswapV2Factory.sol";
import "./SharedToken.sol";
import "./libraries/TransferHelper.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract ShardsMarket {
    using SafeMath for uint256;
    //NFT _tokenId
    uint256[] tokenIds;

    address governance;
    enum ShardsState {
        Live,
        Listed,
        ApplyforBuyout,
        Buyout,
        BuyoutFailed,
        SubscriptionFailed
    }
    address factory;
    //市场的碎片总供应量
    uint256 totalSupply = 10000;

    address public immutable WETH;

    //抵押倒计时 60*60*24*5
    uint256 deadlineForStaking = 432000;
    //赎回倒计时 60*60*24*7
    uint256 deadlineForRedeem = 604800;
    //碎片创建者的碎片比例
    uint256 shardsCreatorProportion = 5;
    //平台的碎片比例
    uint256 platformProportion = 5;

    //买断比例
    uint256 buyOutProportion = 15;
    //max
    uint256 public constant max = 100;
    //买断倍数
    uint256 public buyOutTimes = 2;
    //shardPoolId
    uint256 public shardPoolIdCount = 0;
    //所有的shardpool的Id
    uint256[] public allPools;
    // Info of each pool.
    mapping(uint256 => shardPool) public poolInfo;
    //碎片池
    struct shardPool {
        address creator; //shard创建者
        ShardsState state; //shared状态
        uint256 createTime; //创建时间
        address shardToken; //token地址
        uint256 balanceOfETH; //pool抵押总量
        string shardName;
        string shardSymbol;
        uint256 minPrice;
        address nft;
        uint256 totalSupply;
        uint256 shardPrice;
        bool isCreateWithDraw;
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
    uint256 public voteLenth = 259200;
    //每个NFT对应的投票id
    mapping(uint256 => uint256) public proposalID;
    //投票
    mapping(uint256 => Proposal) public proposals;
    //用户是否已经投票
    mapping(uint256 => mapping(address => bool)) public voted;
    //代币用户是否被锁定
    mapping(address => mapping(address => uint256)) public blocked;
    //投票通过比例
    uint256 public passNeeded = 75;

    struct Proposal {
        uint256 votesReceived;
        uint256 voteTotal;
        bool passed;
        address submitter;
        uint256 voteDeadline;
        uint256 shardAmount;
        uint256 ETHAmount;
    }

    constructor(
        address _WETH,
        address _factory,
        address _governance
    ) public {
        WETH = _WETH;
        factory = _factory;
        governance = _governance;
    }

    function CreateShareds(
        address nft,
        uint256 _tokenId,
        string memory shardName,
        string memory shardSymbol,
        uint256 minPrice
    ) external returns (uint256 shardPoolId) {
        require(ERC721(nft).ownerOf(_tokenId) == msg.sender, "UNAUTHORIZED");
        ERC721(nft).safeTransferFrom(msg.sender, address(this), _tokenId);
        if (shardPoolIdCount == 0) {
            shardPoolIdCount = 1;
        }
        shardPoolId = shardPoolIdCount;
        poolInfo[_tokenId] = shardPool({
            creator: msg.sender,
            state: ShardsState.Live,
            createTime: block.timestamp,
            shardToken: address(0),
            balanceOfETH: 0,
            shardName: shardName,
            shardSymbol: shardSymbol,
            minPrice: minPrice,
            nft: nft,
            totalSupply: totalSupply,
            shardPrice: 0,
            isCreateWithDraw: false
        });
        allPools.push(shardPoolIdCount);
        shardPoolIdCount = shardPoolIdCount.add(1);
    }

    function Stake(uint256 _shardPoolId, uint256 amount) external payable {
        require(
            block.timestamp <=
                poolInfo[_shardPoolId].createTime.add(deadlineForStaking),
            "NFT:EXPIRED"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
        );
        IWETH(WETH).deposit{value: amount}();
        assert(IWETH(WETH).transfer(address(this), amount));
        userInfo[_shardPoolId][msg.sender].amount = userInfo[_shardPoolId][msg
            .sender]
            .amount
            .add(amount);
        poolInfo[_shardPoolId].balanceOfETH = poolInfo[_shardPoolId]
            .balanceOfETH
            .add(amount);
    }

    function Redeem(uint256 _shardPoolId, uint256 amount) external payable {
        require(
            block.timestamp <=
                poolInfo[_shardPoolId].createTime.add(deadlineForRedeem),
            "NFT:EXPIRED"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
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
    }

    function SetPrice(uint256 _shardPoolId) external {
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

    function RedeemInSubscriptionFailed(uint256 _shardPoolId) external {
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

    function WithdrawShardToken(uint256 _shardPoolId) external {
        require(
            poolInfo[_shardPoolId].state == ShardsState.Listed,
            "WRONG_STATE"
        );
        uint256 userETH = userInfo[_shardPoolId][msg.sender].amount;
        bool isWithdrawShard = userInfo[_shardPoolId][msg.sender]
            .isWithdrawShard;
        require(userETH > 0 && !isWithdrawShard, "INSUFFIENT BALANCE");
        uint256 shardsForUsers = poolInfo[_shardPoolId]
            .totalSupply
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

    function CreatorWithdrawETH(uint256 _shardPoolId) external {
        require(msg.sender == poolInfo[_shardPoolId].creator, "UNAUTHORIZED");
        require(
            poolInfo[_shardPoolId].state == ShardsState.Listed,
            "WRONG_STATE"
        );
        require(!poolInfo[_shardPoolId].isCreateWithDraw, "ALREADY WITHDRAW");
        uint256 totalETH = poolInfo[_shardPoolId].balanceOfETH;
        // uint256 platformAmount = poolInfo[_shardPoolId]
        //     .totalSupply
        //     .mul(platformProportion)
        //     .div(max);
        uint256 platformAmount = ISharedToken(poolInfo[_shardPoolId].shardToken)
            .balanceOf(address(this));
        uint256 fee = poolInfo[_shardPoolId].shardPrice.mul(platformAmount);
        uint256 amount = totalETH.sub(fee);
        poolInfo[_shardPoolId].isCreateWithDraw = true;
        IWETH(WETH).withdraw(amount);
        TransferHelper.safeTransferETH(msg.sender, amount);
    }

    function BuyOut(uint256 _shardPoolId, uint256 ETHAmount)
        external
        returns (uint256 proposalId)
    {
        uint256 shardBalance = ISharedToken(poolInfo[_shardPoolId].shardToken)
            .balanceOf(msg.sender);
        require(
            shardBalance >= totalSupply.mul(buyOutProportion).div(max),
            "INSUFFIENT BALANCE"
        );
        require(
            poolInfo[_shardPoolId].state == ShardsState.Live,
            "LIVE STATE IS REQUIRED"
        );
        uint256 currentPrice = getPrice(_shardPoolId);
        require(
            ETHAmount >=
                max.sub(buyOutProportion).mul(totalSupply).mul(currentPrice),
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
        proposals[proposolIdCount] = Proposal({
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
    }

    function Vote(uint256 _shardPoolId, bool isAgree) external {
        uint256 balance = ISharedToken(poolInfo[_shardPoolId].shardToken)
            .balanceOf(msg.sender);
        require(balance >= 0, "INSUFFICIENT VOTERIGHT");
        require(
            poolInfo[_shardPoolId].state == ShardsState.ApplyforBuyout,
            "WRONG STATE"
        );
        uint256 id = proposalID[_shardPoolId];
        Proposal memory p = proposals[id];
        require(block.timestamp <= p.voteDeadline, "EXPIRED");
        require(voted[id][msg.sender] == false);
        blocked[poolInfo[_shardPoolId].shardToken][msg.sender] = id;
        voted[id][msg.sender] == true;
        if (isAgree) {
            p.votesReceived = p.votesReceived.add(balance);
            p.voteTotal = p.voteTotal.add(balance);
        } else {
            p.voteTotal = p.voteTotal.add(balance);
        }
    }

    function VoteResultComfirm(uint256 _shardPoolId)
        external
        returns (bool result)
    {
        uint256 id = proposalID[_shardPoolId];
        Proposal memory p = proposals[id];
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
            ERC721(poolInfo[_shardPoolId].nft).safeTransferFrom(
                address(this),
                msg.sender,
                _shardPoolId
            );
        } else {
            p.passed = false;
            result = false;
            poolInfo[_shardPoolId].state == ShardsState.BuyoutFailed;
        }
    }

    function ExchangeForETH(uint256 _shardPoolId, uint256 shardAmount)
        external
        returns (uint256 ETHAmount)
    {
        uint256 id = proposalID[_shardPoolId];
        Proposal memory p = proposals[id];
        require(
            poolInfo[_shardPoolId].state == ShardsState.Buyout,
            "WRONG STATE"
        );

        ShardToken(poolInfo[_shardPoolId].shardToken).burn(
            msg.sender,
            shardAmount
        );

        uint256 amount = shardAmount.mul(p.ETHAmount).div(
            totalSupply.sub(p.shardAmount)
        );
        TransferHelper.safeTransferETH(msg.sender, amount);
    }

    function RedeemForBuyoutFailed(uint256 _shardPoolId)
        external
        returns (uint256 shardTokenAmount, uint256 ETHAmount)
    {
        uint256 id = proposalID[_shardPoolId];
        Proposal memory p = proposals[id];
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

    //view

    function _failToSetPrice(uint256 _shardPoolId) private {
        poolInfo[_shardPoolId].state = ShardsState.SubscriptionFailed;
        ERC721(poolInfo[_shardPoolId].nft).safeTransferFrom(
            address(this),
            poolInfo[_shardPoolId].creator,
            _shardPoolId
        );
    }

    function _successToSetPrice(uint256 _shardPoolId) private {
        poolInfo[_shardPoolId].shardToken = _deployShardsToken(_shardPoolId);
        poolInfo[_shardPoolId].state == ShardsState.Listed;
        uint256 creatorAmount = poolInfo[_shardPoolId]
            .totalSupply
            .mul(shardsCreatorProportion)
            .div(max);
        uint256 platformAmount = poolInfo[_shardPoolId]
            .totalSupply
            .mul(platformProportion)
            .div(max);
        ISharedToken(poolInfo[_shardPoolId].shardToken).mint(
            poolInfo[_shardPoolId].creator,
            creatorAmount
        );
        ISharedToken(poolInfo[_shardPoolId].shardToken).mint(
            poolInfo[_shardPoolId].creator,
            platformAmount
        );
        uint256 shardPrice = poolInfo[_shardPoolId].balanceOfETH.div(
            poolInfo[_shardPoolId]
                .totalSupply
                .mul(max.sub(shardsCreatorProportion).sub(platformProportion))
                .div(max)
        );
        poolInfo[_shardPoolId].shardPrice = shardPrice;
    }

    function SetDeadlineForStaking(uint256 _deadlineForStaking) external {
        require(msg.sender == governance, "UNAUTHORIZED");
        deadlineForStaking = _deadlineForStaking;
    }

    function SetDeadlineForRedeem(uint256 _deadlineForRedeem) external {
        require(msg.sender == governance, "UNAUTHORIZED");
        deadlineForRedeem = _deadlineForRedeem;
    }

    function SetShardsCreatorProportion(uint256 _shardsCreatorProportion)
        external
    {
        require(msg.sender == governance, "UNAUTHORIZED");
        shardsCreatorProportion = _shardsCreatorProportion;
    }

    function SetPlatformProportion(uint256 _platformProportion) external {
        require(msg.sender == governance, "UNAUTHORIZED");
        platformProportion = _platformProportion;
    }

    function SetBuyOutProportion(uint256 _buyOutProportion) external {
        require(msg.sender == governance, "UNAUTHORIZED");
        buyOutProportion = _buyOutProportion;
    }

    function SetBuyOutTimes(uint256 _buyOutTimes) external {
        require(msg.sender == governance, "UNAUTHORIZED");
        buyOutTimes = _buyOutTimes;
    }

    function SetVoteLenth(uint256 _voteLenth) external {
        require(msg.sender == governance, "UNAUTHORIZED");
        voteLenth = _voteLenth;
    }

    function SetPassNeeded(uint256 _passNeeded) external {
        require(msg.sender == governance, "UNAUTHORIZED");
        passNeeded = _passNeeded;
    }

    function SetTotalSupply(uint256 _totalSupply) external {
        require(msg.sender == governance, "UNAUTHORIZED");
        totalSupply = _totalSupply;
    }

    function _deployShardsToken(uint256 _shardPoolId)
        private
        returns (address token)
    {
        bytes memory bytecode = type(ShardToken).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_shardPoolId));
        assembly {
            token := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ISharedToken(token).initialize(_shardPoolId);
    }
}
