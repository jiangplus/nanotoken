// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FlowableNanoToken} from "src/FlowableNanoToken.sol";

contract FlowableNanoTokenFactory {
    mapping(address => bool) public isFlowableNanoTokenFromFactory;

    event FlowableNanoTokenCreated(
        address indexed token,
        address indexed admin,
        string name,
        string symbol,
        uint8 decimals,
        uint256 initialSupply
    );

    function createFlowableNanoToken(
        address admin,
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 initialSupply
    ) external returns (address token) {
        FlowableNanoToken deployed =
            new FlowableNanoToken(admin, name, symbol, decimals, initialSupply);
        token = address(deployed);
        isFlowableNanoTokenFromFactory[token] = true;
        emit FlowableNanoTokenCreated(token, admin, name, symbol, decimals, initialSupply);
    }
}
