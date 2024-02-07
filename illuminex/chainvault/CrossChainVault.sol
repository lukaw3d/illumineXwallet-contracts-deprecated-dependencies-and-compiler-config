// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./ICrossChainVault.sol";

contract CrossChainVault is ICrossChainVault, Ownable {
    using SafeERC20 for IERC20;

    struct SetAllowedAssetParams {
        address asset;
        bool isAllowed;
    }

    mapping(address => mapping(address => uint256)) public lockedAssets;
    mapping(address => bool) public allowedAssets;

    event Lock(address indexed user, address indexed asset, uint256 amount);
    event Unlock(address indexed user, address indexed asset, uint256 amount);
    event SetAllowedAsset(address indexed asset, bool isAllowed);

    event FeesSet(address indexed asset, uint256 newFees);
    event FeesWithdrawn(address indexed to, address indexed asset, uint256 amount);

    mapping(address => uint256) public feesCollected;
    mapping(address => uint256) public fees;

    function setAllowedAssets(SetAllowedAssetParams[] calldata assets) public onlyOwner {
        for (uint i = 0; i < assets.length; i++) {
            emit SetAllowedAsset(assets[i].asset, assets[i].isAllowed);
            allowedAssets[assets[i].asset] = assets[i].isAllowed;
        }
    }

    function setFees(address asset, uint256 _fees) public onlyOwner {
        require(_fees <= 10, "Fees too big");
        emit FeesSet(asset, _fees);
        fees[asset] = _fees;
    }

    function withdrawFees(address asset, address to) public onlyOwner {
        require(feesCollected[asset] > 0, "Balance can't be zero");

        emit FeesWithdrawn(to, asset, feesCollected[asset]);
        IERC20(asset).safeTransfer(to, feesCollected[asset]);
        feesCollected[asset] = 0;
    }

    receive() external payable {}

    function lock(address asset, uint256 amount) public override returns (uint256) {
        require(allowedAssets[asset], "Asset is not allowed");

        uint256 fee = amount * fees[asset] / 1000;
        uint256 amountAfterFee = amount - fee;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        lockedAssets[msg.sender][asset] += amountAfterFee;
        feesCollected[asset] += fee;
        emit Lock(msg.sender, asset, amount);

        return amountAfterFee;
    }

    function unlock(address asset, uint256 amount) public override {
        require(lockedAssets[msg.sender][asset] >= amount, "Insufficient locked balance");

        lockedAssets[msg.sender][asset] -= amount;
        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Unlock(msg.sender, asset, amount);
    }
}
