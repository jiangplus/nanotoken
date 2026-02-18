// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FlowableNanoToken} from "src/FlowableNanoToken.sol";

contract FlowableNanoTokenTest is Test {
    FlowableNanoToken internal token;

    address internal sender = address(0xA11CE);
    address internal recipient = address(0xB0B);
    address internal thirdParty = address(0xCAFE);

    function setUp() public {
        token = new FlowableNanoToken(1_000_000 ether);
        token.transfer(sender, 1_000 ether);
    }

    function testCreateAndWithdrawFlow() public {
        vm.prank(sender);
        uint256 flowId = token.createFlow(recipient, 1 ether, 0, 100 ether);

        vm.warp(block.timestamp + 10);

        vm.prank(recipient);
        uint256 withdrawn = token.withdrawMaxFlow(flowId, recipient);

        assertEq(withdrawn, 10 ether);
        assertEq(token.balanceOf(recipient), 10 ether);
        assertEq(token.flowWithdrawableAmount(flowId), 0);
    }

    function testPauseAndResumeFlow() public {
        vm.prank(sender);
        uint256 flowId = token.createFlow(recipient, 1 ether, 0, 100 ether);

        vm.warp(block.timestamp + 10);
        vm.prank(sender);
        token.pauseFlow(flowId);

        vm.warp(block.timestamp + 10);
        vm.prank(sender);
        token.resumeFlow(flowId);

        vm.warp(block.timestamp + 5);
        vm.prank(recipient);
        uint256 withdrawn = token.withdrawMaxFlow(flowId, recipient);

        assertEq(withdrawn, 15 ether);
        assertEq(token.balanceOf(recipient), 15 ether);
    }

    function testSenderCanRefundUnstreamedBalance() public {
        vm.prank(sender);
        uint256 flowId = token.createFlow(recipient, 1 ether, 0, 100 ether);

        vm.warp(block.timestamp + 10);

        vm.prank(sender);
        token.refundFlow(flowId, 80 ether);

        assertEq(token.balanceOf(sender), 980 ether);

        vm.prank(recipient);
        uint256 withdrawn = token.withdrawMaxFlow(flowId, recipient);
        assertEq(withdrawn, 10 ether);
        assertEq(token.balanceOf(recipient), 10 ether);
    }

    function testRecipientCanVoidAndWithdrawCoveredDebt() public {
        vm.prank(sender);
        uint256 flowId = token.createFlow(recipient, 1 ether, 0, 5 ether);

        vm.warp(block.timestamp + 10);

        vm.prank(recipient);
        token.voidFlow(flowId);

        vm.prank(recipient);
        uint256 withdrawn = token.withdrawMaxFlow(flowId, recipient);

        assertEq(withdrawn, 5 ether);
        assertEq(token.balanceOf(recipient), 5 ether);

        vm.warp(block.timestamp + 100);
        assertEq(token.flowWithdrawableAmount(flowId), 0);
    }

    function testUnauthorizedWithdrawTargetReverts() public {
        vm.prank(sender);
        uint256 flowId = token.createFlow(recipient, 1 ether, 0, 100 ether);

        vm.warp(block.timestamp + 10);

        vm.prank(thirdParty);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlowableNanoToken.UnauthorizedFlowWithdrawal.selector,
                thirdParty,
                recipient,
                thirdParty
            )
        );
        token.withdrawFlow(flowId, thirdParty, 1 ether);
    }

    function testThirdPartyCanWithdrawToRecipient() public {
        vm.prank(sender);
        uint256 flowId = token.createFlow(recipient, 1 ether, 0, 100 ether);

        vm.warp(block.timestamp + 10);

        vm.prank(thirdParty);
        bool ok = token.withdrawFlow(flowId, recipient, 3 ether);

        assertTrue(ok);
        assertEq(token.balanceOf(recipient), 3 ether);
    }
}
