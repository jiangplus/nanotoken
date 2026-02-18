// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NanoToken} from "src/NanoToken.sol";

contract NanoTokenTest is Test {
    NanoToken internal token;
    address internal user = address(0xBEEF);
    address internal recipient = address(0xCAFE);
    address internal allowedRecipient = address(0xABCD);

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
        token.transfer(recipient, 100 ether);

        assertEq(token.balanceOf(recipient), 100 ether);
        assertEq(token.balanceOf(address(this)), 999_900 ether);
    }

    function testOwnerCanSetAndUnsetBlacklist() public {
        token.setBlacklist(user, true);
        assertTrue(token.blacklisted(user));

        token.setBlacklist(user, false);
        assertFalse(token.blacklisted(user));
    }

    function testNonOwnerCannotManageBlacklist() public {
        vm.prank(user);
        vm.expectRevert();
        token.setBlacklist(user, true);

        vm.prank(user);
        vm.expectRevert();
        token.setBlacklist(user, false);
    }

    function testBlacklistedSenderCannotTransfer() public {
        token.transfer(user, 100 ether);
        token.setBlacklist(user, true);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NanoToken.BlacklistedAddress.selector, user));
        token.transfer(recipient, 1 ether);
    }

    function testBlacklistedRecipientCannotReceive() public {
        token.setBlacklist(recipient, true);

        vm.expectRevert(abi.encodeWithSelector(NanoToken.BlacklistedAddress.selector, recipient));
        token.transfer(recipient, 1 ether);
    }

    function testOwnerCanSetAndUnsetWhitelist() public {
        token.setWhitelist(user, true);
        assertTrue(token.whitelisted(user));
        assertEq(token.whitelistCount(), 1);

        token.setWhitelist(user, false);
        assertFalse(token.whitelisted(user));
        assertEq(token.whitelistCount(), 0);
    }

    function testNonOwnerCannotManageWhitelist() public {
        vm.prank(user);
        vm.expectRevert();
        token.setWhitelist(user, true);
    }

    function testWhitelistEmptyDoesNotRestrictTransfers() public {
        token.transfer(user, 10 ether);

        vm.prank(user);
        token.transfer(recipient, 1 ether);
        assertEq(token.balanceOf(recipient), 1 ether);
    }

    function testNonWhitelistedSenderCannotTransferToNonWhitelistedRecipient() public {
        token.transfer(user, 10 ether);
        token.setWhitelist(allowedRecipient, true);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(NanoToken.WhitelistRestrictedTransfer.selector, user, recipient)
        );
        token.transfer(recipient, 1 ether);
    }

    function testNonWhitelistedSenderCanTransferToWhitelistedRecipient() public {
        token.transfer(user, 10 ether);
        token.setWhitelist(allowedRecipient, true);

        vm.prank(user);
        token.transfer(allowedRecipient, 1 ether);
        assertEq(token.balanceOf(allowedRecipient), 1 ether);
    }

    function testNonWhitelistedSenderCanBurnWhenWhitelistIsNotEmpty() public {
        token.transfer(user, 10 ether);
        token.setWhitelist(allowedRecipient, true);

        vm.prank(user);
        token.burn(1 ether);
        assertEq(token.balanceOf(user), 9 ether);
    }

    function testOwnerCanAlwaysTransferWhenWhitelistIsNotEmpty() public {
        token.setWhitelist(allowedRecipient, true);

        token.transfer(recipient, 1 ether);
        assertEq(token.balanceOf(recipient), 1 ether);
    }

    function testWhitelistedSenderCanAlwaysTransferWhenWhitelistIsNotEmpty() public {
        token.transfer(user, 10 ether);
        token.setWhitelist(user, true);
        token.setWhitelist(allowedRecipient, true);

        vm.prank(user);
        token.transfer(recipient, 1 ether);
        assertEq(token.balanceOf(recipient), 1 ether);
    }
}
