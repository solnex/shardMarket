pragma solidity 0.6.12;

import "./interface/IShardToken.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract ShardToken is IShardToken {
    using SafeMath for uint256;

    string public override name = "NFT V1";
    string public override symbol = "NFT-V1";
    uint8 public constant override decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    uint256 public tokenId;
    address public market;

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor() public {
        market = msg.sender;
    }

    function _mint(address to, uint256 value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    function _approve(
        address owner,
        address spender,
        uint256 value
    ) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint256 value)
        external
        override
        returns (bool)
    {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value)
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool) {
        if (allowance[from][msg.sender] != uint256(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(
                value
            );
        }
        _transfer(from, to, value);
        return true;
    }

    function burn(address from, uint256 value) external override {
        require(msg.sender == market, "FORBIDDEN");
        _burn(from, value);
    }

    function mint(address to, uint256 value) external override {
        require(msg.sender == market, "FORBIDDEN");
        _mint(to, value);
    }

    function initialize(
        uint256 _tokenId,
        string memory _symbol,
        string memory _name
    ) external override {
        require(msg.sender == market, "FORBIDDEN"); // sufficient check
        tokenId = _tokenId;
        name = _name;
        symbol = _symbol;
    }
}
