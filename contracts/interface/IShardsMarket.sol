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
    function CreateShareds(string memory url) external;

    //认购
    function Stake(string memory url, uint256 amount) external payable;

    //赎回
    function Redeem(string memory url, uint256 amount) external;

    //认购结算时进行定价
    function SetPrice(string memory url) external;

    //申请买断
    function BuyOut(string memory url, uint256 ETHAmount) external;

    /// 未开发

    //申请买断后进行投票
    function Vote(
        string memory url,
        uint256 voteCount,
        bool isAgree
    ) external;

    //用户定价之后领取shard代币
    function Withdraw(string memory url, uint256 amount) external;

    function WithdrawAll(string memory url) external;

    //散户进行兑换ETH
    function ExchangeForETH() external;

    //设置碎片创建者占比
    function SetShardsCreatorProportion(uint256 _shardsCreatorProportion)
        external;

    function SetTotalSupply(uint256 _totalSupply) external;

    function SetDeadlineForStaking(uint256 _deadlineForStaking) external;

    function SetDeadlineForRedeem(uint256 _deadlineForRedeem) external;

    function SetPlatformProportion(uint256 _platformProportion) external;

    function SetBuyOutProportion(uint256 _buyOutProportion) external;

    function SetBuyOutTimes(uint256 _buyOutTimes) external;

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
