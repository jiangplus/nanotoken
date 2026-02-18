// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NanoToken} from "src/NanoToken.sol";

contract NanoTokenFactory {
    mapping(address => bool) public isNanoTokenFromFactory;

    event NanoTokenCreated(
        address indexed token,
        address indexed admin,
        string name,
        string symbol,
        uint8 decimals,
        uint256 initialSupply
    );

    function createNanoToken(
        address admin,
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 initialSupply
    ) external returns (address token) {
        NanoToken deployed = new NanoToken(admin, name, symbol, decimals, initialSupply);
        token = address(deployed);
        isNanoTokenFromFactory[token] = true;
        emit NanoTokenCreated(token, admin, name, symbol, decimals, initialSupply);
    }
}
