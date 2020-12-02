pragma solidity 0.6.12;

interface IShardsMarket {
    enum ShardsState {Live, Listed, ApplyForBuyout, Buyout, SubscriptionFailed}

    /// 已开发
    //市场的碎片总供应量
    function totalSupply() external view returns (uint256);

    //抵押倒计时
    function deadlineForStake() external view returns (uint256);

    //赎回倒计时
    function deadlineForRedeem() external view returns (uint256);

    //碎片创建者的碎片比例
    function shardsCreatorProportion() external view returns (uint256);

    //平台的碎片比例
    function platformProportion() external view returns (uint256);

    //买断比例
    function buyoutProportion() external view returns (uint256);

    //买断倍数
    function buyoutTimes() external view returns (uint256);

    function voteLenth() external view returns (uint256);

    function passNeeded() external view returns (uint256);

    event ShardCreated(
        uint256 shardPoolId,
        address indexed creator,
        address nft,
        uint256 _tokenId,
        string shardName,
        string shardSymbol,
        uint256 minWantTokenAmount,
        uint256 createTime,
        uint256 totalSupply,
        address wantToken
    );
    event Stake(address indexed sender, uint256 shardPoolId, uint256 amount);
    event Redeem(address indexed sender, uint256 shardPoolId, uint256 amount);
    event SettleSuccess(
        uint256 indexed shardPoolId,
        // uint256 creatorAmount,
        uint256 platformAmount,
        uint256 shardForStakers,
        uint256 balanceOfWantToken,
        uint256 fee,
        address shardToken
    );
    event SettleFail(uint256 indexed shardPoolId);
    event ApplyForBuyout(
        address indexed sender,
        uint256 indexed proposalId,
        uint256 indexed _shardPoolId,
        uint256 shardAmount,
        uint256 wantTokenAmount,
        uint256 voteDeadline,
        uint256 buyoutTimes,
        uint256 price,
        uint256 blockHeight
    );
    event Vote(
        address indexed sender,
        uint256 indexed proposalId,
        uint256 indexed _shardPoolId,
        bool isAgree,
        uint256 voteAmount
    );
    event VoteResultConfirm(
        uint256 indexed proposalId,
        uint256 indexed _shardPoolId,
        bool isPassed
    );

    //创建碎片
    function createShard(
        address nft,
        uint256 _tokenId,
        string memory shardName,
        string memory shardSymbol,
        uint256 minWantTokenAmount,
        address wantToken
    ) external returns (uint256 shardPoolId);

    //认购
    function stakeETH(uint256 _shardPoolId) external payable;

    function stake(uint256 _shardPoolId, uint256 amount) external;

    //赎回
    function redeem(uint256 _shardPoolId, uint256 amount) external;

    //认购结算时进行定价
    function settle(uint256 _shardPoolId) external;

    //碎片化失败后用户赎回抵押的wantToken
    function redeemInSubscriptionFailed(uint256 _shardPoolId) external;

    //成功定价后用户提取shardToken
    function usersWithdrawShardToken(uint256 _shardPoolId) external;

    //成功定价后创建者提取wantToken
    function creatorWithdrawWantToken(uint256 _shardPoolId) external;

    //申请买断
    function applyForBuyout(uint256 _shardPoolId, uint256 wantTokenAmount)
        external
        returns (uint256 proposalId);

    //申请买断后进行投票
    function vote(uint256 _shardPoolId, bool isAgree) external;

    //投票结果确认
    function voteResultConfirm(uint256 _shardPoolId)
        external
        returns (bool result);

    //散户进行兑换wantToken
    function exchangeForWantToken(uint256 _shardPoolId, uint256 shardAmount)
        external
        returns (uint256 wantTokenAmount);

    //买断投票失败后取回质押的shard和wantToken
    function redeemForBuyoutFailed(uint256 _proposalId)
        external
        returns (uint256 shardTokenAmount, uint256 wantTokenAmount);

    //设置碎片创建者占比
    function setShardsCreatorProportion(uint256 _shardsCreatorProportion)
        external;

    function setPlatformProportion(uint256 _platformProportion) external;

    function setBuyoutProportion(uint256 _buyoutProportion) external;

    function setBuyoutTimes(uint256 _buyoutTimes) external;

    function setVoteLenth(uint256 _voteLenth) external;

    function setPassNeeded(uint256 _passNeeded) external;

    function setTotalSupply(uint256 _totalSupply) external;

    function setDeadlineForRedeem(uint256 _deadlineForRedeem) external;

    function setDeadlineForStake(uint256 _deadlineForStake) external;

    // function getAllPools() external view returns (uint256[] memory _pools);
}
