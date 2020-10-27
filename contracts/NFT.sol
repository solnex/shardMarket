pragma solidity 0.6.12;
import "./interface/IUniswapV2Router02.sol";
import "./interface/IWETH.sol";
import "./interface/INFT.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract NFT is INFT {
    address public immutable router;
    address public immutable WETH;
    uint256 public constant min = 9500;
    uint256 public constant all = 10000;
    using SafeMath for uint256;

    constructor(address _router, address _WETH) public {
        router = _router;
        WETH = _WETH;
    }

    function addliquidity(
        address token,
        uint256 tokenAmount,
        uint256 ETHAmount
    ) public override payable {
        uint256 amountAMin = tokenAmount.mul(min).div(all);
        uint256 amountBMin = ETHAmount.mul(min).div(all);
        uint256 deadline = block.timestamp;
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
}
