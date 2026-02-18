// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NanoToken} from "src/NanoToken.sol";

contract NanoTokenTest is Test {
    NanoToken internal token;

    function setUp() public {
        token = new NanoToken(1_000_000 ether);
    }

    function testInitialSupplyMintedToDeployer() public view {
        assertEq(token.totalSupply(), 1_000_000 ether);
        assertEq(token.balanceOf(address(this)), 1_000_000 ether);
    }

    function testOwnerIsCreator() public view {
        assertEq(token.owner(), address(this));
    }

    function testTransfer() public {
        address recipient = address(0xBEEF);

        token.transfer(recipient, 100 ether);

        assertEq(token.balanceOf(recipient), 100 ether);
        assertEq(token.balanceOf(address(this)), 999_900 ether);
    }
}
