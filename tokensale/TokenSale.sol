// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenSale is Ownable {
    using SafeERC20 for IERC20;

    enum SaleState {
        Pending,
        Started,
        Finished,
        Refund,
        UnfulfilledClaim
    }

    IERC20[] public raiseTokens;
    uint256 public immutable rate;
    bytes32 public immutable whitelistMerkleRoot;

    uint256 public immutable hardCap;
    uint256 public immutable softCap;

    uint256 public currentCap;
    SaleState public state;

    mapping(address => uint256) public committedValue;

    uint256 public saleDeadline;

    event Purchase(
        address indexed purchaser,
        address indexed purchasedTo,
        address indexed purchasedWith,
        uint256 ixPurchased,
        uint256 tokensCommitted
    );

    event SaleStarted();
    event SaleFinished();
    event SaleUnfulfilled();
    event SaleRefund();

    event Refunded(address indexed to, uint256 amount);

    constructor(IERC20[] memory _raiseTokens, uint256 _rate, bytes32 _root, uint256 _hardCap, uint256 _softCap) {
        raiseTokens = _raiseTokens;
        rate = _rate;
        whitelistMerkleRoot = _root;
        hardCap = _hardCap;
        softCap = _softCap;
    }

    function startSale(uint256 deadline) public onlyOwner {
        require(state == SaleState.Pending, "Invalid sale state");

        emit SaleStarted();
        state = SaleState.Started;
        saleDeadline = deadline;
    }

    // UnfulfilledClaim states indicates that there are unclaimed reserved tokens, so anyone who is whitelisted can purchase them
    function setSaleUnfulfilled() public onlyOwner {
        require(state == SaleState.Started, "Invalid sale state");

        emit SaleUnfulfilled();
        state = SaleState.UnfulfilledClaim;
    }

    function triggerDeadlineFinalisation() public onlyOwner {
        require(state == SaleState.Started || state == SaleState.UnfulfilledClaim, "Invalid sale state");
        require(saleDeadline > 0 && saleDeadline < block.timestamp, "Deadline has not passed yet");

        if (currentCap >= softCap) {
            state = SaleState.Finished;
            emit SaleFinished();
        } else {
            emit SaleRefund();
            state = SaleState.Refund;
        }
    }

    function setRefund() public onlyOwner {
        require(state == SaleState.Started || state == SaleState.UnfulfilledClaim, "Invalid sale state");

        emit SaleRefund();
        state = SaleState.Refund;
    }

    function withdraw(address to, uint256 amount, IERC20 commitmentToken) public onlyOwner {
        require(state == SaleState.Finished, "Invalid sale state");
        commitmentToken.safeTransfer(to, amount);
    }

    function claimRefund(IERC20 commitmentToken) public {
        require(state == SaleState.Refund, "Invalid sale state");
        require(committedValue[msg.sender] > 0, "Insufficient funds committed");

        uint256 refundAmount = committedValue[msg.sender];

        _validateCommitmentToken(commitmentToken);
        committedValue[msg.sender] = 0;

        commitmentToken.safeTransfer(msg.sender, refundAmount);
        emit Refunded(msg.sender, refundAmount);
    }

    function _validateSaleFinished() private {
        if (currentCap < hardCap) {
            return;
        }

        state = SaleState.Finished;
        emit SaleFinished();
    }

    function _purchase(address to, IERC20 commitmentToken, uint256 amount, uint256 limit) private {
        if (state == SaleState.Started) {
            require(committedValue[msg.sender] + amount <= limit, "Insufficient limit");
        }

        require(currentCap + amount <= hardCap, "Hard cap has been exceeded");

        currentCap += amount;
        committedValue[msg.sender] += amount;

        emit Purchase(msg.sender, to, address(commitmentToken), amount * rate, amount);
        _validateSaleFinished();
    }

    function _validateCommitmentToken(IERC20 commitmentToken) private view {
        bool isValidRaiseToken = false;
        for (uint i = 0; i < raiseTokens.length; i++) {
            if (raiseTokens[i] == commitmentToken) {
                isValidRaiseToken = true;
                break;
            }
        }

        require(isValidRaiseToken, "Raise token is not valid");
    }

    function purchase(address to, IERC20 commitmentToken, uint256 amount, uint256 limit, bytes32[] memory proof) public {
        require(state == SaleState.Started || state == SaleState.UnfulfilledClaim, "Invalid state");

        if (saleDeadline > 0) {
            require(saleDeadline > block.timestamp, "Deadline has passed");
        }

        if (whitelistMerkleRoot != bytes32(0)) {
            require(MerkleProof.verify(proof, whitelistMerkleRoot, keccak256(abi.encodePacked(msg.sender, limit))), "Invalid merkle proof");
        }

        _validateCommitmentToken(commitmentToken);
        commitmentToken.safeTransferFrom(msg.sender, address(this), amount);

        _purchase(to, commitmentToken, amount, limit);
    }
}