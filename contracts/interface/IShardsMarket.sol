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
    function totalSupply() external returns (uint256);

    //抵押倒计时
    function deadlineForStaking() external returns (uint256);

    //赎回倒计时
    function deadlineForRedeem() external returns (uint256);

    //碎片创建者的碎片比例
    function shardsCreatorProportion() external returns (uint256);

    //平台的碎片比例
    function platformProportion() external returns (uint256);

    //买断比例
    function buyOutProportion() external returns (uint256);

    //买断倍数
    function buyOutTimes() external returns (uint256);

    //创建碎片
    function CreateShareds(
        address nft,
        uint256 _tokenId,
        string memory shardName,
        string memory shardSymbol,
        uint256 minPrice
    ) external returns (uint256 shardPoolId);

    //认购
    function Stake(uint256 _shardPoolId, uint256 amount) external payable;

    //赎回
    function Redeem(uint256 _shardPoolId, uint256 amount) external payable;

    //认购结算时进行定价
    function SetPrice(uint256 _shardPoolId) external;

    //碎片化失败后用户赎回抵押的ETH
    function RedeemInSubscriptionFailed(uint256 _shardPoolId) external;

    //成功定价后用户提取shardToken
    function WithdrawShardToken(uint256 _shardPoolId) external;

    //成功定价后创建者提取ETH
    function CreatorWithdrawETH(uint256 _shardPoolId) external;

    //申请买断
    function BuyOut(uint256 _shardPoolId, uint256 ETHAmount)
        external
        returns (uint256 proposalId);

    //申请买断后进行投票
    function Vote(uint256 _shardPoolId, bool isAgree) external;

    //投票结果确认
    function VoteResultComfirm(uint256 _shardPoolId)
        external
        returns (bool result);

    //散户进行兑换ETH
    function ExchangeForETH(uint256 _shardPoolId, uint256 shardAmount)
        external
        returns (uint256 ETHAmount);

    //买断投票失败后取回质押的shard和eth
    function RedeemForBuyoutFailed(uint256 _shardPoolId)
        external
        returns (uint256 shardTokenAmount, uint256 ETHAmount);

    //设置碎片创建者占比
    function SetShardsCreatorProportion(uint256 _shardsCreatorProportion)
        external;

    function SetPlatformProportion(uint256 _platformProportion) external;

    function SetBuyOutProportion(uint256 _buyOutProportion) external;

    function SetBuyOutTimes(uint256 _buyOutTimes) external;

    function SetVoteLenth(uint256 _voteLenth) external;

    function SetPassNeeded(uint256 _passNeeded) external;

    function SetTotalSupply(uint256 _totalSupply) external;

    //view
    function GetShardPool(string memory url)
        external
        view
        returns (
            address creator, //shard创建者
            ShardsState state, //shared状态
            uint256 createTime, //创建时间
            address shardToken, //token地址
            uint256 balanceOfETH
        ); //)
}
