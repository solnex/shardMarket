pragma solidity 0.6.12;

import "./interface/IShardsMarket.sol";
import "./interface/IWETH.sol";
import "./interface/ISharedToken.sol";
import "./interface/IUniswapV2Pair.sol";
import "./interface/IUniswapV2Factory.sol";
import "./SharedToken.sol";
import "./libraries/TransferHelper.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract ShardsMarket {
    using SafeMath for uint256;
    //NFT url
    string[] urls;

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
    mapping(string => shardPool) public poolInfo;
    //碎片池
    struct shardPool {
        address creator; //shard创建者
        ShardsState state; //shared状态
        uint256 createTime; //创建时间
        address shardToken; //token地址
        uint256 balanceOfETH; //pool抵押总量
    }

    mapping(string => mapping(address => UserInfo)) public userInfo;
    struct UserInfo {
        uint256 amount;
    }

    mapping(address => address) public LPToken;
    //id
    uint256 public proposolIdCount = 0;
    //投票时间跨度
    uint256 public voteLenth;
    //每个NFT对应的投票id
    mapping(string => uint256) public proposalID;
    //投票
    mapping(uint256 => Proposal) public proposals;
    //用户是否已经投票
    mapping(uint256 => mapping(address => bool)) public voted;
    //代币用户是否被锁定
    mapping(address => mapping(address => uint256)) public blocked;

    struct Proposal {
        uint256 votesReceived;
        uint256 voteTotal;
        bool passed;
        address submitter;
        uint256 voteDeadline;
    }

    constructor(address _WETH, address _factory) public {
        WETH = _WETH;
        factory = _factory;
    }

    function CreateShareds(string memory url) external {
        poolInfo[url] = shardPool({
            creator: msg.sender,
            state: ShardsState.Live,
            createTime: block.timestamp,
            shardToken: address(0),
            balanceOfETH: 0
        });
    }

    function Stake(string memory url, uint256 amount) external payable {
        require(
            block.timestamp <= poolInfo[url].createTime.add(deadlineForStaking),
            "NFT:EXPIRED"
        );
        require(
            poolInfo[url].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
        );
        IWETH(WETH).deposit{value: amount}();
        assert(IWETH(WETH).transfer(address(this), amount));
        userInfo[url][msg.sender].amount.add(amount);
        poolInfo[url].balanceOfETH.add(amount);
    }

    function Redeem(string memory url, uint256 amount) external payable {
        require(
            block.timestamp <= poolInfo[url].createTime.add(deadlineForRedeem),
            "NFT:EXPIRED"
        );
        require(
            poolInfo[url].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
        );
        IWETH(WETH).withdraw(amount);
        TransferHelper.safeTransferETH(msg.sender, amount);
        userInfo[url][msg.sender].amount.sub(amount);
        poolInfo[url].balanceOfETH.sub(amount);
    }

    function SetPrice(string memory url) external {
        require(
            block.timestamp >= poolInfo[url].createTime.add(deadlineForRedeem),
            "NFT:NOT READY"
        );
        require(
            poolInfo[url].state == ShardsState.Live,
            "NFT:LIVE STATE IS REQUIRED"
        );
        if (poolInfo[url].balanceOfETH == 0) {
            _failToSetPrice(url);
        } else {
            poolInfo[url].shardToken = _deployShardsToken(url);
            poolInfo[url].state == ShardsState.Listed;
        }
    }

    function _failToSetPrice(string memory url) private {
        poolInfo[url].state == ShardsState.SubscriptionFailed;
    }

    function _deployShardsToken(string memory url)
        private
        returns (address token)
    {
        bytes memory bytecode = type(ShardToken).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(url));
        assembly {
            token := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ISharedToken(token).initialize(url);
    }

    function BuyOut(string memory url, uint256 ETHAmount) external {
        require(
            ISharedToken(poolInfo[url].shardToken).balanceOf(msg.sender) >=
                totalSupply.mul(buyOutProportion).div(max),
            "Insuffient shardToken"
        );
        require(
            poolInfo[url].state == ShardsState.Live ||
                poolInfo[url].state == ShardsState.BuyoutFailed,
            "State should be Live"
        );
        uint256 currentPrice = getPrice(url);
        require(
            ETHAmount >=
                max.sub(buyOutProportion).mul(totalSupply).mul(currentPrice),
            "INSUFFICIENT_ETHAMOUNT"
        );
        if (proposolIdCount == 0) {
            proposolIdCount = 1;
        }
        proposals[proposolIdCount] = Proposal({
            votesReceived: 0,
            voteTotal: 0,
            passed: false,
            submitter: msg.sender,
            voteDeadline: block.timestamp.add(voteLenth)
        });

        poolInfo[url].state == ShardsState.ApplyforBuyout;
    }

    function Vote(
        string memory url,
        uint256 voteCount,
        bool isAgree
    ) external {
        uint256 balance = ISharedToken(poolInfo[url].shardToken).balanceOf(
            _voter
        );
        require(balance > 0, "INSUFFICIENT_VOTERIGHT");
        Proposal memory p = proposals[proposalID[url]];
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

    function getPrice(string memory url)
        internal
        returns (uint256 currentPrice)
    {
        address lPTokenAddress = IUniswapV2Factory(factory).getPair(
            poolInfo[url].shardToken,
            WETH
        );
        (uint112 _reserve0, uint112 _reserve1, ) = IUniswapV2Pair(
            lPTokenAddress
        )
            .getReserves();
        currentPrice = quote(1, _reserve1, _reserve0);
    }
}
