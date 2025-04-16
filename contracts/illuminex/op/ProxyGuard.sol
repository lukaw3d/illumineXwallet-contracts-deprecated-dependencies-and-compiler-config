// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./MultichainEndpoint.sol";

contract ProxyGuard {
    using SafeERC20 for IERC20;

    MultichainEndpoint public immutable dst;

    mapping(bytes32 => bool) public hashRecords;

    constructor(address payable _dst) {
        dst = MultichainEndpoint(_dst);
    }

    function proxyPass(address token, uint256 amount, bytes memory encodedParams) public payable {
        bytes32 _hash = keccak256(encodedParams);

        require(!hashRecords[_hash], "Hash already used");
        require(!dst.ofacBlocklist(msg.sender), "OFAC blocked");

        if (token != dst.nativeWrapper()) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(token).safeIncreaseAllowance(address(dst), amount);
        }

        hashRecords[_hash] = true;
        dst.proxyPass{value: msg.value}(token, amount, encodedParams);
    }
}
