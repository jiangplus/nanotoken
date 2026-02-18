// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract NanoToken is ERC20, Ownable {
    constructor(uint256 initialSupply) ERC20("Nano Token", "NANO") Ownable(msg.sender) {
        _mint(msg.sender, initialSupply);
    }
}
