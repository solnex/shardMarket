pragma solidity 0.6.12;

interface IShardsMarket {
    enum ShardsState {
        Live,
        Listed,
        ApplyforBuyout,
        Buyout,
        BuyoutFailed,
        SubscriptionFailed
    }

    /// 已开发
    //市场的碎片总供应量
    function totalSupply() external view returns (uint256);

    //抵押倒计时
    function deadlineForStaking() external view returns (uint256);

    //赎回倒计时
    function deadlineForRedeem() external view returns (uint256);

    //碎片创建者的碎片比例
    function shardsCreatorProportion() external view returns (uint256);

    //平台的碎片比例
    function platformProportion() external view returns (uint256);

    //买断比例
    function buyOutProportion() external view returns (uint256);

    //买断倍数
    function buyOutTimes() external view returns (uint256);

    function voteLenth() external view returns (uint256);

    function passNeeded() external view returns (uint256);

    event SharedCreated(
        address indexed creator,
        address nft,
        uint256 _tokenId,
        string shardName,
        string shardSymbol,
        uint256 minPrice,
        uint256 createTime,
        uint256 totalSupply,
        address wantToken
    );
    event Stake(address indexed sender, uint256 shardPoolId, uint256 amount);
    event Redeem(address indexed sender, uint256 shardPoolId, uint256 amount);
    event SettleSuccess(uint256 indexed shardPoolId, uint256 shardPrice);
    event SettleFail(uint256 indexed shardPoolId);
    event ApplyforBuyout(
        address indexed sender,
        uint256 indexed proposalId,
        uint256 indexed _shardPoolId,
        uint256 shardAmount,
        uint256 wantTokenAmount,
        uint256 voteDeadline
    );
    event Vote(
        address indexed sender,
        uint256 indexed proposalId,
        uint256 indexed _shardPoolId,
        bool isAgree,
        uint256 voteAmount
    );
    event VoteResultComfirm(
        uint256 indexed proposalId,
        uint256 indexed _shardPoolId,
        bool isPassed
    );

    //创建碎片
    function createShared(
        address nft,
        uint256 _tokenId,
        string memory shardName,
        string memory shardSymbol,
        uint256 minPrice,
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
    function applyforBuyout(uint256 _shardPoolId, uint256 wantTokenAmount)
        external
        returns (uint256 proposalId);

    //申请买断后进行投票
    function vote(uint256 _shardPoolId, bool isAgree) external;

    //投票结果确认
    function voteResultComfirm(uint256 _shardPoolId)
        external
        returns (bool result);

    //散户进行兑换wantToken
    function exchangeForWantToken(uint256 _shardPoolId, uint256 shardAmount)
        external
        returns (uint256 wantTokenAmount);

    //买断投票失败后取回质押的shard和wantToken
    function redeemForBuyOutFailed(uint256 _shardPoolId)
        external
        returns (uint256 shardTokenAmount, uint256 wantTokenAmount);

    //设置碎片创建者占比
    function setShardsCreatorProportion(uint256 _shardsCreatorProportion)
        external;

    function setPlatformProportion(uint256 _platformProportion) external;

    function setBuyOutProportion(uint256 _buyOutProportion) external;

    function setBuyOutTimes(uint256 _buyOutTimes) external;

    function setVoteLenth(uint256 _voteLenth) external;

    function setPassNeeded(uint256 _passNeeded) external;

    function setTotalSupply(uint256 _totalSupply) external;

    function setDeadlineForRedeem(uint256 _deadlineForRedeem) external;

    function setDeadlineForStaking(uint256 _deadlineForStaking) external;

    // function getAllPools() external view returns (uint256[] memory _pools);
}
