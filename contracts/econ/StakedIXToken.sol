// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./LuminexFarming.sol";

contract StakedIXToken is ERC20 {
    using SafeERC20 for ERC20;

    uint256 public constant IX_POOL_ID = 0;

    LuminexFarming public immutable farm;
    ERC20 public immutable ixToken;

    uint256 public rewards;
    uint256 public claimedRewards;

    bytes32 public depositId;

    bool public depositedTriggered;
    uint256 public depositedIX;

    event Claim(address indexed user, uint256 amount);

    constructor(address _farm, address _ixToken) ERC20("Staked IX", "sIX") {
        farm = LuminexFarming(_farm);
        ixToken = ERC20(_ixToken);
    }

    function mint(uint256 amount, address to) public {
        require(!depositedTriggered, "Deposit already triggered");

        depositedIX = amount;
        depositedTriggered = true;

        ixToken.safeIncreaseAllowance(address(farm), amount);

        depositId = farm.computeNextDepositIdFor(address(this));
        farm.deposit(IX_POOL_ID, amount);

        _mint(to, amount);
    }

    function pendingTokens(uint256 sIXAmount) public view returns (uint256) {
        uint256 _reward = farm.pendingIX(IX_POOL_ID, address(this));

        uint256 rewardsToClaim = sIXAmount * ((rewards + _reward) - claimedRewards) / totalSupply();
        return rewardsToClaim + sIXAmount;
    }

    function withdraw(uint256 amount) public {
        uint256 _reward = farm.pendingIX(IX_POOL_ID, address(this));
        if (_reward > 0) {
            rewards += _reward;
        }

        farm.withdraw(depositId, amount);

        uint256 rewardsToClaim = amount * (rewards - claimedRewards) / totalSupply();
        uint256 tokensToSend = rewardsToClaim + amount;
        claimedRewards += rewardsToClaim;

        _burn(msg.sender, amount);

        ixToken.safeTransfer(msg.sender, tokensToSend);
        emit Claim(msg.sender, tokensToSend);
    }
}
