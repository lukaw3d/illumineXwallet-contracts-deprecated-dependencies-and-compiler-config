// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockWETH is ERC20 {
    constructor() ERC20('WROSE', 'WROSE') {}

    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint amount) public payable {
        _burn(msg.sender, amount);
        payable(address(msg.sender)).transfer(amount);
    }
}