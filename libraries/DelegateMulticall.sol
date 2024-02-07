// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";

contract DelegateMulticall {
    struct Call {
        address target;
        bytes data;
    }

    function multicall(Call[] calldata calls) external virtual returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory returnData) = calls[i].target.call(abi.encodePacked(calls[i].data, msg.sender));
            results[i] = Address.verifyCallResult(success, returnData, "Multicall: sub-call failed");
        }

        return results;
    }
}