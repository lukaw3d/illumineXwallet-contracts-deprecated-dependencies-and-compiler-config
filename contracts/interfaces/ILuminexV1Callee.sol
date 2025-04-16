// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface ILuminexV1Callee {
    function illuminexV1Call(address sender, uint amount0, uint amount1, bytes calldata data) external;
}