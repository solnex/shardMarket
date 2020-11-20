pragma solidity 0.6.12;
import "../interface/IUniswapV2Pair.sol";
import "../interface/IUniswapV2Factory.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

library NFTLibrary {
    using SafeMath for uint256;

    function getPrice(
        address tokenA,
        address tokenB,
        address factory
    ) internal view returns (uint256 currentPrice) {
        address lPTokenAddress = IUniswapV2Factory(factory).getPair(
            tokenA,
            tokenB
        );
        (uint112 _reserve0, uint112 _reserve1, ) = IUniswapV2Pair(
            lPTokenAddress
        )
            .getReserves();
        (uint112 reserve0, uint112 reserve1) = tokenA < tokenB
            ? (_reserve0, _reserve1)
            : (_reserve1, _reserve0);
        currentPrice = quote(1e18, reserve0, reserve1);
    }

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, "INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "INSUFFICIENT_LIQUIDITY");
        amountB = amountA.mul(reserveB) / reserveA;
    }

    function balanceOf(address user, address lPTokenAddress)
        internal
        view
        returns (uint256 balance)
    {
        balance = IUniswapV2Pair(lPTokenAddress).balanceOf(user);
    }

    function getPair(
        address tokenA,
        address tokenB,
        address factory
    ) internal view returns (address pair) {
        pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
    }
}
