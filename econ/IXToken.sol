// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./IMintableERC20.sol";
import "./Vesting.sol";
import "./MerkleVestingSplitter.sol";
import "./MerkleSplitter.sol";
import "./StakedIXToken.sol";

contract IXToken is ERC20, IMintableERC20, Ownable {
    address public minter;
    uint256 public constant MAX_SUPPLY = 100_000_000 ether;
    uint256 public immutable vestingStartTime;

    uint256 public constant MONTH = 30 days;
    uint256 public constant YEAR = 365 days;

    bool public initFinished;

    TokenVesting public immutable vesting;

    mapping(bytes32 => MerkleVestingSplitter) public vestingSplitters;
    mapping(bytes32 => MerkleSplitter) public splitters;

    constructor(uint256 _vestingStartTime) ERC20("illumineX Token", "IX") {
        vesting = new TokenVesting(address(this));
        vestingStartTime = _vestingStartTime;
    }

    function init(
        address _coreContributorsMultisig,
        address _ixFundMultisig,
        bytes32 _advisorsRoot,
        address _communityGrowthMultisig,
        address _airdropMultisig,
        bytes32 _privateSaleTGERoot,
        bytes32 _privateSaleVestingRoot,
        bytes32 _publicSaleTGERoot,
        bytes32 _publicSaleVestingRoot,
        address _stakedIX
    ) public onlyOwner {
        require(!initFinished, "Init already finished");
        initFinished = true;

        _mintVestedTokens(_coreContributorsMultisig, 15_000_000 ether, MONTH, YEAR * 2);
        _mint(_ixFundMultisig, 13_000_000 ether);
        _mintSplitVestedTokens(keccak256("ADVISORS"), _advisorsRoot, 5_000_000 ether, MONTH, YEAR * 2);
        _mintVestedTokens(_communityGrowthMultisig, 6_000_000 ether, MONTH, YEAR);
        _mint(_airdropMultisig, 2_750_000 ether);

        _mintSplit(keccak256("PRIVATE_SALE_TGE"), _privateSaleTGERoot, 3_600_000 ether);
        _mintPrivateSaleVestedTokens(_privateSaleVestingRoot, StakedIXToken(_stakedIX), 5_400_000 ether, 0, MONTH * 4);

        _mintSplit(keccak256("PUBLIC_SALE_TGE"), _publicSaleTGERoot, 4_200_000 ether);
        _mintSplitVestedTokens(keccak256("PUBLIC_SALE_VESTED"), _publicSaleVestingRoot, 2_800_000 ether, 0, MONTH * 6);

        // Protocol Owned Liquidity
        _mint(msg.sender, 2_250_000 ether);

        require(totalSupply() == 60_000_000 ether, "Pre-minted supply imbalanced");

        vesting.transferOwnership(msg.sender);
    }

    function _mintSplit(bytes32 walletId, bytes32 _root, uint256 amount) private {
        splitters[walletId] = new MerkleSplitter(_root, address(this));
        _mint(address(splitters[walletId]), amount);
    }

    function _mintVestedTokens(address to, uint256 amount, uint256 cliff, uint256 duration) private returns (bytes32 _vestingId) {
        _mint(address(vesting), amount);
        _vestingId = vesting.computeNextVestingScheduleIdForHolder(to);
        vesting.createVestingSchedule(to, vestingStartTime, cliff, duration, 1, false, amount);
    }

    function _mintSplitVestedTokens(bytes32 walletId, bytes32 _root, uint256 toVest, uint256 cliff, uint256 duration) private {
        vestingSplitters[walletId] = new MerkleVestingSplitter(vesting, _root, toVest);

        bytes32 _vestingId = _mintVestedTokens(address(vestingSplitters[walletId]), toVest, cliff, duration);
        vestingSplitters[walletId].setVestingId(_vestingId);
    }

    function _mintPrivateSaleVestedTokens(bytes32 _root, StakedIXToken _stakedIX, uint256 toVest, uint256 cliff, uint256 duration) private {
        bytes32 walletId = keccak256("PRIVATE_SALE_VESTED");

        TokenVesting _vesting = new TokenVesting(address(_stakedIX));
        vestingSplitters[walletId] = new MerkleVestingSplitter(_vesting, _root, toVest);

        _mint(address(_stakedIX), toVest);
        _stakedIX.mint(toVest, address(_vesting));

        bytes32 _vestingId = _vesting.computeNextVestingScheduleIdForHolder(address(vestingSplitters[walletId]));
        _vesting.createVestingSchedule(address(vestingSplitters[walletId]), vestingStartTime, cliff, duration, 1, false, toVest);

        vestingSplitters[walletId].setVestingId(_vestingId);
    }

    function mint(address _to, uint256 _amount) public {
        require(msg.sender == minter, "Not a minter");
        if (totalSupply() == MAX_SUPPLY) {
            return;
        }

        uint256 amount = (totalSupply() + _amount <= MAX_SUPPLY) ? _amount : (MAX_SUPPLY - totalSupply());
        _mint(_to, amount);
    }

    function setMinter(address _minter) public onlyOwner {
        require(minter == address(0), "Not allowed");
        minter = _minter;
    }
}
