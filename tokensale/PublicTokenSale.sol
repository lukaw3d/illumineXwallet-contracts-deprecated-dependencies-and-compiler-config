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
        Guaranteed,
        Fcfs,
        Finished,
        Refund,
        UnfulfilledRaffle,
        UnfulfilledOpen
    }

    IERC20[] public raiseTokens;
    uint256 public immutable rate;

    bytes32 public guaranteedMerkleRoot;
    bytes32 public fcfsMerkleRoot;
    bytes32 public raffleMerkleRoot;

    uint256 public immutable hardCap;
    uint256 public immutable softCap;

    uint256 public currentCap;
    SaleState public state;

    mapping(address => uint256) public committedValue;

    uint256 public stateDeadline;

    event Purchase(
        address indexed purchaser,
        address indexed purchasedTo,
        address indexed purchasedWith,
        uint256 ixPurchased,
        uint256 tokensCommitted
    );

    event SaleStarted();
    event SaleFinished();
    event SaleStateSwitch(SaleState oldState, SaleState newState);
    event SaleRefund();

    event UpdateGuaranteedRoot(bytes32 newRoot);
    event UpdateFcfsRoot(bytes32 newRoot);
    event UpdateRafflesRoot(bytes32 newRoot);

    event Refunded(address indexed to, uint256 amount);

    constructor(
        IERC20[] memory _raiseTokens,
        uint256 _rate,
        bytes32 _rootGuaranteed,
        bytes32 _rootFcfs,
        bytes32 _rootRaffle,
        uint256 _hardCap,
        uint256 _softCap
    ) {
        raiseTokens = _raiseTokens;
        rate = _rate;
        guaranteedMerkleRoot = _rootGuaranteed;
        fcfsMerkleRoot = _rootFcfs;
        raffleMerkleRoot = _rootRaffle;
        hardCap = _hardCap;
        softCap = _softCap;
    }

    function _switchState(SaleState _state, uint256 deadline) private {
        emit SaleStateSwitch(state, _state);
        state = _state;
        stateDeadline = deadline;
    }

    function switchSaleState(uint256 deadline) public onlyOwner {
        if (state == SaleState.Pending) {
            _switchState(SaleState.Guaranteed, deadline);
        } else if (state == SaleState.Guaranteed) {
            _switchState(SaleState.Fcfs, deadline);
        } else if (state == SaleState.Fcfs) {
            _switchState(SaleState.UnfulfilledRaffle, deadline);
        } else if (state == SaleState.UnfulfilledRaffle) {
            _switchState(SaleState.UnfulfilledOpen, deadline);
        }
    }

    function setRefund() public onlyOwner {
        require(state == SaleState.Guaranteed || state == SaleState.UnfulfilledRaffle || state == SaleState.Fcfs || state == SaleState.UnfulfilledOpen, "Invalid sale state");

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

    function updateGuaranteedRoot(bytes32 newRoot) public onlyOwner {
        emit UpdateGuaranteedRoot(newRoot);
        guaranteedMerkleRoot = newRoot;
    }

    function updateFcfsRoot(bytes32 newRoot) public onlyOwner {
        emit UpdateFcfsRoot(newRoot);
        fcfsMerkleRoot = newRoot;
    }

    function updateRafflesRoot(bytes32 newRoot) public onlyOwner {
        emit UpdateRafflesRoot(newRoot);
        raffleMerkleRoot = newRoot;
    }

    function triggerDeadlineFinalisation() public onlyOwner {
        require(state == SaleState.UnfulfilledOpen, "Invalid sale state");
        require(stateDeadline > 0 && stateDeadline < block.timestamp, "Deadline has not passed yet");

        if (currentCap >= softCap) {
            state = SaleState.Finished;
            emit SaleFinished();
        } else {
            emit SaleRefund();
            state = SaleState.Refund;
        }
    }

    function _validateSaleFinished() private {
        if (currentCap < hardCap) {
            return;
        }

        state = SaleState.Finished;
        emit SaleFinished();
    }

    function _purchase(address to, IERC20 commitmentToken, uint256 amount, uint256 limit) private {
        if (state != SaleState.UnfulfilledOpen) {
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
        require(state == SaleState.Guaranteed || state == SaleState.UnfulfilledRaffle || state == SaleState.Fcfs || state == SaleState.UnfulfilledOpen, "Invalid state");

        if (stateDeadline > 0) {
            require(stateDeadline > block.timestamp, "Deadline has passed");
        }

        bytes32 _root = bytes32(0);
        if (state == SaleState.Guaranteed) {
            _root = guaranteedMerkleRoot;
        } else if (state == SaleState.Fcfs) {
            _root = fcfsMerkleRoot;
        } else if (state == SaleState.UnfulfilledRaffle) {
            _root = raffleMerkleRoot;
        }

        if (_root != bytes32(0)) {
            require(MerkleProof.verify(proof, _root, keccak256(abi.encodePacked(msg.sender, limit))), "Invalid merkle proof");
        }

        _validateCommitmentToken(commitmentToken);
        commitmentToken.safeTransferFrom(msg.sender, address(this), amount);

        _purchase(to, commitmentToken, amount, limit);
    }
}