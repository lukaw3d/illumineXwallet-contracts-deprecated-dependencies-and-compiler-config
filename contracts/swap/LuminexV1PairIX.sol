// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./LuminexV1Pair.sol";

contract LuminexV1PairIX is LuminexV1Pair, Ownable {
    uint256 public constant KICKSTART_PHASE_DURATION = 7 minutes;
    uint256 public constant INITIAL_PROTECTION_PHASE_DURATION = 1 hours;
    uint256 public constant CIRC_SUPPLY_INITIAL = 10_900_000 ether;

    uint256 public constant MAX_BUY = CIRC_SUPPLY_INITIAL * 50 / 10000;

    bool private tradingEnabled;

    uint256 private kickStartExpiration;
    uint256 private initialProtectionExpiration;

    address public immutable ixToken;

    constructor(address _ixToken) {
        ixToken = _ixToken;
    }

    function enableTrading() public onlyOwner {
        require(!tradingEnabled, "Trading is disabled");
        tradingEnabled = true;

        kickStartExpiration = block.timestamp + KICKSTART_PHASE_DURATION;
        initialProtectionExpiration = block.timestamp + INITIAL_PROTECTION_PHASE_DURATION;
    }

    function _isKickStartPhase() private view returns (bool) {
        return block.timestamp <= kickStartExpiration;
    }

    function _isInitialProtectionPhase() private view returns (bool) {
        return block.timestamp > kickStartExpiration && block.timestamp <= initialProtectionExpiration;
    }

    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external override lock {
        require(tradingEnabled, "Trading is not yet enabled");

        uint256 ixAmount = token0 == ixToken ? amount0Out : amount1Out;
        if (_isKickStartPhase() || _isInitialProtectionPhase()) {
            require(ixAmount <= MAX_BUY, "Whale protection");
        }

        uint256 tax0 = 0;
        uint256 tax1 = 0;
        if (_isKickStartPhase()) {
            tax0 = amount0Out * 35 / 100;
            tax1 = amount1Out * 35 / 100;
        } else if (_isInitialProtectionPhase()) {
            tax0 = amount0Out / 10;
            tax1 = amount1Out / 10;
        }

        if (tax0 > 0) _safeTransfer(token0, owner(), tax0);
        if (tax1 > 0) _safeTransfer(token1, owner(), tax1);

        _swap(amount0Out - tax0, amount1Out - tax1, to, data);
    }
}