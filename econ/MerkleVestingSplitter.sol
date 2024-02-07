// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./Vesting.sol";

contract MerkleVestingSplitter {
    using SafeERC20 for ERC20;

    TokenVesting public immutable vesting;
    bytes32 public immutable root;
    uint256 public immutable totalTokensToRelease;

    bytes32 public vestingId;
    bool public isVestingIdSet;

    uint256 public tokensReleased;

    mapping(address => uint256) public claimed;
    mapping(address => uint256) public maxLimit;
    mapping(address => bool) public limitSet;

    event Claim(address indexed user, uint256 amount);

    constructor(TokenVesting _vesting, bytes32 _root, uint256 _toRelease) {
        vesting = _vesting;
        root = _root;
        totalTokensToRelease = _toRelease;
    }

    function setVestingId(bytes32 _vestingId) public {
        require(!isVestingIdSet, "Already set");
        vestingId = _vestingId;
        isVestingIdSet = true;
    }

    function claim(uint256 limit, bytes32[] calldata proofs) public {
        require(MerkleProof.verify(proofs, root, keccak256(abi.encodePacked(msg.sender, limit))), "Invalid proof");

        if (!limitSet[msg.sender]) {
            limitSet[msg.sender] = true;
            maxLimit[msg.sender] = limit;
        }

        uint256 toRelease = vesting.computeReleasableAmount(vestingId);
        if (toRelease > 0) {
            vesting.release(vestingId, toRelease);
            tokensReleased += toRelease;
        }

        TokenVesting.VestingSchedule memory _vesting = vesting.getVestingSchedule(vestingId);
        uint256 tokensToSend = (maxLimit[msg.sender] * tokensReleased / _vesting.amountTotal) - claimed[msg.sender];
        claimed[msg.sender] += tokensToSend;

        ERC20(vesting.getToken()).safeTransfer(msg.sender, tokensToSend);
        emit Claim(msg.sender, tokensToSend);
    }
}
