// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MerkleSplitter {
    using SafeERC20 for ERC20;

    bytes32 public immutable root;
    address public immutable token;

    mapping(address => uint256) public claimed;
    mapping(address => uint256) public maxLimit;
    mapping(address => bool) public limitSet;

    event Claim(address indexed user, uint256 amount);

    constructor(bytes32 _root, address _token) {
        root = _root;
        token = _token;
    }

    function claim(uint256 amount, uint256 limit, bytes32[] calldata proofs) public {
        require(MerkleProof.verify(proofs, root, keccak256(abi.encodePacked(msg.sender, limit))), "Invalid proof");

        if (!limitSet[msg.sender]) {
            limitSet[msg.sender] = true;
            maxLimit[msg.sender] = limit;
        }

        require(claimed[msg.sender] + amount <= maxLimit[msg.sender], "Insufficient funds");
        claimed[msg.sender] += amount;

        ERC20(token).safeTransfer(msg.sender, amount);
        emit Claim(msg.sender, amount);
    }
}
