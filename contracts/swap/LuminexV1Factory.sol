// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../interfaces/ILuminexV1Factory.sol';
import './LuminexV1Pair.sol';
import './LuminexV1PairIX.sol';

contract LuminexV1Factory is ILuminexV1Factory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => bool) public feeFreePairs;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    address public immutable ixToken;

    constructor(address _feeToSetter, address _ixToken) {
        feeToSetter = _feeToSetter;
        ixToken = _ixToken;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (ILuminexV1Pair pair) {
        require(tokenA != tokenB, 'LuminexV1: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'LuminexV1: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'LuminexV1: PAIR_EXISTS'); // single check is sufficient

        if (token0 == ixToken || token1 == ixToken) {
            LuminexV1PairIX ixPair = new LuminexV1PairIX(ixToken);
            ixPair.transferOwnership(feeToSetter);

            pair = ixPair;
        } else {
            pair = new LuminexV1Pair();
        }

        pair.initialize(token0, token1);
        getPair[token0][token1] = address(pair);
        getPair[token1][token0] = address(pair); // populate mapping in the reverse direction
        allPairs.push(address(pair));

        emit PairCreated(token0, token1, address(pair), allPairs.length);
    }

    function setPairFeeDisabled(address pair, bool disabled) public {
        require(msg.sender == feeToSetter, 'LuminexV1: FORBIDDEN');
        feeFreePairs[pair] = disabled;
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'LuminexV1: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'LuminexV1: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}