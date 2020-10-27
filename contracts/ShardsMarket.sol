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
    //token定价
    uint256 price;
    //抵押倒计时
    uint256 deadlineForStaking;
    //赎回倒计时
    uint256 deadlineForRedeem;
    //碎片创建者的碎片比例
    uint256 shardsCreatorProportion;
    //平台的碎片比例
    uint256 platformProportion;

    //买断比例
    uint256 buyOutProportion = 15;
    //max
    uint256 public constant max = 100;
    //买断倍数
    uint256 public buyOutTimes = 2;
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
    }

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    struct UserInfo {
        uint256 amount;
    }

    mapping(address => address) public LPToken;
    //id
    uint256 public proposolIdCount = 0;
    //投票时间跨度
    uint256 public voteLenth;
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

    constructor(address _WETH, address _factory) public {
        WETH = _WETH;
        factory = _factory;
    }

    function CreateShareds(
        address nft,
        uint256 _tokenId,
        string memory shardName,
        string memory shardSymbol,
        uint256 minPrice
    ) external {
        require(ERC721(nft).ownerOf(_tokenId) == msg.sender, "UNAUTHORIZED");
        ERC721(nft).safeTransferFrom(msg.sender, address(this), _tokenId);
        poolInfo[_tokenId] = shardPool({
            creator: msg.sender,
            state: ShardsState.Live,
            createTime: block.timestamp,
            shardToken: address(0),
            balanceOfETH: 0,
            shardName: shardName,
            shardSymbol: shardSymbol,
            minPrice: minPrice,
            nft: nft
        });
    }

    function Stake(uint256 _tokenId, uint256 amount) external payable {
        require(
            block.timestamp <=
                poolInfo[_tokenId].createTime.add(deadlineForStaking),
            "NFT:EXPIRED"
        );
        require(
            poolInfo[_tokenId].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
        );
        IWETH(WETH).deposit{value: amount}();
        assert(IWETH(WETH).transfer(address(this), amount));
        userInfo[_tokenId][msg.sender].amount.add(amount);
        poolInfo[_tokenId].balanceOfETH.add(amount);
    }

    function Redeem(uint256 _tokenId, uint256 amount) external payable {
        require(
            block.timestamp <=
                poolInfo[_tokenId].createTime.add(deadlineForRedeem),
            "NFT:EXPIRED"
        );
        require(
            poolInfo[_tokenId].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
        );
        IWETH(WETH).withdraw(amount);
        TransferHelper.safeTransferETH(msg.sender, amount);
        userInfo[_tokenId][msg.sender].amount.sub(amount);
        poolInfo[_tokenId].balanceOfETH.sub(amount);
    }

    function SetPrice(uint256 _tokenId) external {
        require(
            block.timestamp >=
                poolInfo[_tokenId].createTime.add(deadlineForRedeem),
            "NFT:NOT READY"
        );
        require(
            poolInfo[_tokenId].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
        );
        if (poolInfo[_tokenId].balanceOfETH < poolInfo[_tokenId].minPrice) {
            _failToSetPrice(_tokenId);
        } else {
            poolInfo[_tokenId].shardToken = _deployShardsToken(_tokenId);
            poolInfo[_tokenId].state == ShardsState.Listed;
        }
    }

    function _failToSetPrice(uint256 _tokenId) private {
        poolInfo[_tokenId].state == ShardsState.SubscriptionFailed;
    }

    function _deployShardsToken(uint256 _tokenId)
        private
        returns (address token)
    {
        bytes memory bytecode = type(ShardToken).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_tokenId));
        assembly {
            token := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ISharedToken(token).initialize(_tokenId);
    }

    function BuyOut(uint256 _tokenId, uint256 ETHAmount)
        external
        returns (uint256 proposalId)
    {
        uint256 shardBalance = ISharedToken(poolInfo[_tokenId].shardToken)
            .balanceOf(msg.sender);
        require(
            shardBalance >= totalSupply.mul(buyOutProportion).div(max),
            "Insuffient shardToken"
        );
        require(
            poolInfo[_tokenId].state == ShardsState.Live,
            "State should be Live"
        );
        uint256 currentPrice = getPrice(_tokenId);
        require(
            ETHAmount >=
                max.sub(buyOutProportion).mul(totalSupply).mul(currentPrice),
            "INSUFFICIENT_ETHAMOUNT"
        );

        TransferHelper.safeTransferFrom(
            WETH,
            msg.sender,
            address(this),
            ETHAmount
        );
        TransferHelper.safeTransferFrom(
            poolInfo[_tokenId].shardToken,
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

        blocked[poolInfo[_tokenId].shardToken][msg.sender] = proposalId;
        voted[proposalId][msg.sender] = true;
        proposolIdCount = proposolIdCount.add(1);
        poolInfo[_tokenId].state == ShardsState.ApplyforBuyout;
    }

    function Vote(uint256 _tokenId, bool isAgree) external {
        uint256 balance = ISharedToken(poolInfo[_tokenId].shardToken).balanceOf(
            msg.sender
        );
        require(balance >= 0, "INSUFFICIENT_VOTERIGHT");
        require(
            poolInfo[_tokenId].state == ShardsState.ApplyforBuyout,
            "WRONG_STATE"
        );
        uint256 id = proposalID[_tokenId];
        Proposal memory p = proposals[id];
        require(block.timestamp <= p.voteDeadline, "EXPIRED");
        require(voted[id][msg.sender] == false);
        blocked[poolInfo[_tokenId].shardToken][msg.sender] = id;
        voted[id][msg.sender] == true;
        if (isAgree) {
            p.votesReceived = p.votesReceived.add(balance);
            p.voteTotal = p.voteTotal.add(balance);
        } else {
            p.voteTotal = p.voteTotal.add(balance);
        }
    }

    function VoteResultComfirm(uint256 _tokenId) external {
        uint256 id = proposalID[_tokenId];
        Proposal memory p = proposals[id];
        require(msg.sender == p.submitter, "UNAUTHORIZED");
        require(block.timestamp >= p.voteDeadline, "NOT READY");
        require(
            poolInfo[_tokenId].state == ShardsState.ApplyforBuyout,
            "WRONG_STATE"
        );
        if (p.votesReceived >= p.voteTotal.mul(passNeeded).div(max)) {
            p.passed = true;
            poolInfo[_tokenId].state == ShardsState.Buyout;
            ShardToken(poolInfo[_tokenId].shardToken).burn(
                msg.sender,
                p.shardAmount
            );
            ERC721(poolInfo[_tokenId].nft).safeTransferFrom(
                address(this),
                msg.sender,
                _tokenId
            );
        } else {
            p.passed = false;
            poolInfo[_tokenId].state == ShardsState.BuyoutFailed;
        }
    }

    function ExchangeForETH(uint256 _tokenId, uint256 shardAmount)
        external
        returns (uint256 ETHAmount)
    {
        uint256 id = proposalID[_tokenId];
        Proposal memory p = proposals[id];
        require(poolInfo[_tokenId].state == ShardsState.Buyout, "WRONG_STATE");

        ShardToken(poolInfo[_tokenId].shardToken).burn(msg.sender, shardAmount);

        uint256 amount = shardAmount.mul(p.ETHAmount).div(
            totalSupply.sub(p.shardAmount)
        );
        TransferHelper.safeTransferETH(msg.sender, amount);
    }

    function RedeemForBuyoutFailed(uint256 _tokenId)
        external
        returns (uint256 shardTokenAmount, uint256 ETHAmount)
    {
        uint256 id = proposalID[_tokenId];
        Proposal memory p = proposals[id];
        require(msg.sender == p.submitter, "UNAUTHORIZED");
        require(
            poolInfo[_tokenId].state == ShardsState.BuyoutFailed &&
                p.passed == false,
            "WRONG_STATE"
        );
        TransferHelper.safeTransfer(
            poolInfo[_tokenId].shardToken,
            msg.sender,
            p.shardAmount
        );
        TransferHelper.safeTransferETH(msg.sender, p.ETHAmount);

        poolInfo[_tokenId].state == ShardsState.Live;
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

    function getPrice(uint256 _tokenId)
        internal
        returns (uint256 currentPrice)
    {
        address lPTokenAddress = IUniswapV2Factory(factory).getPair(
            poolInfo[_tokenId].shardToken,
            WETH
        );
        (uint112 _reserve0, uint112 _reserve1, ) = IUniswapV2Pair(
            lPTokenAddress
        )
            .getReserves();
        currentPrice = quote(1, _reserve1, _reserve0);
    }
}
