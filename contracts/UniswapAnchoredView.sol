pragma solidity 0.6.12;
struct Observation {
    uint256 timestamp;
    uint256 acc;
}

contract UniswapAnchoredView {
    /// @notice The old observation for each symbolHash
    mapping(address => Observation) public oldObservations;

    /// @notice The new observation for each symbolHash
    mapping(address => Observation) public newObservations;
}
