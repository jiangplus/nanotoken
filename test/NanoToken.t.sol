// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NanoToken} from "src/NanoToken.sol";

contract NanoTokenTest is Test {
    bytes32 internal constant TRANSFER_WITH_SIG_TYPEHASH =
        keccak256(
            "TransferWithSig(address from,address to,uint256 amount,uint256 objectId,bytes objectData,uint256 nonce,uint256 deadline)"
        );
    bytes32 internal constant SET_SESSION_KEY_WITH_SIG_TYPEHASH =
        keccak256(
            "SetSessionKeyWithSig(address account,address sessionKey,bool enabled,uint256 nonce,uint256 deadline)"
        );

    event TransferWithData(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 objectId,
        bytes objectData
    );

    NanoToken internal token;
    address internal user = address(0xBEEF);
    address internal recipient = address(0xCAFE);
    address internal allowedRecipient = address(0xABCD);
    uint256 internal signerPk;
    address internal signer;
    uint256 internal sessionPk;
    address internal sessionKey;

    function setUp() public {
        token = new NanoToken(1_000_000 ether);
        signerPk = 0xA11CE;
        signer = vm.addr(signerPk);
        sessionPk = 0xB0B;
        sessionKey = vm.addr(sessionPk);
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

    function testTransferWithData() public {
        bytes memory objectData = hex"1234abcd";

        vm.expectEmit(true, true, false, true);
        emit TransferWithData(address(this), recipient, 100 ether, 42, objectData);

        bool ok = token.transferWithData(recipient, 100 ether, 42, objectData);

        assertTrue(ok);
        assertEq(token.balanceOf(recipient), 100 ether);
        assertEq(token.balanceOf(address(this)), 999_900 ether);
    }

    function testBatchTransferWithData() public {
        address[] memory tos = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory objectIds = new uint256[](2);
        bytes[] memory objectDatas = new bytes[](2);

        tos[0] = recipient;
        tos[1] = allowedRecipient;
        amounts[0] = 40 ether;
        amounts[1] = 60 ether;
        objectIds[0] = 101;
        objectIds[1] = 202;
        objectDatas[0] = hex"aaaa";
        objectDatas[1] = hex"bbbb";

        bool ok = token.batchTransferWithData(tos, amounts, objectIds, objectDatas);
        assertTrue(ok);
        assertEq(token.balanceOf(recipient), 40 ether);
        assertEq(token.balanceOf(allowedRecipient), 60 ether);
        assertEq(token.balanceOf(address(this)), 999_900 ether);
    }

    function testTransferWithSig() public {
        token.transfer(signer, 100 ether);
        bytes memory objectData = hex"beef";
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(signer);
        bytes32 digest =
            _transferWithSigDigest(signer, recipient, 10 ether, 7, objectData, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        bool ok = token.transferWithSig(signer, recipient, 10 ether, 7, objectData, deadline, sig);

        assertTrue(ok);
        assertEq(token.balanceOf(signer), 90 ether);
        assertEq(token.balanceOf(recipient), 10 ether);
        assertEq(token.nonces(signer), nonce + 1);
    }

    function testTransferWithSigRejectsReplay() public {
        token.transfer(signer, 100 ether);
        bytes memory objectData = hex"beef";
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(signer);
        bytes32 digest =
            _transferWithSigDigest(signer, recipient, 10 ether, 7, objectData, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        token.transferWithSig(signer, recipient, 10 ether, 7, objectData, deadline, sig);

        vm.expectRevert(NanoToken.InvalidSignature.selector);
        token.transferWithSig(signer, recipient, 10 ether, 7, objectData, deadline, sig);
    }

    function testTransferWithSigRejectsExpiredSignature() public {
        token.transfer(signer, 100 ether);
        bytes memory objectData = hex"beef";
        uint256 deadline = block.timestamp + 1;
        uint256 nonce = token.nonces(signer);
        bytes32 digest =
            _transferWithSigDigest(signer, recipient, 10 ether, 7, objectData, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.warp(deadline + 1);

        vm.expectRevert(abi.encodeWithSelector(NanoToken.ExpiredSignature.selector, deadline));
        token.transferWithSig(signer, recipient, 10 ether, 7, objectData, deadline, sig);
    }

    function testUserCanSetAndUnsetSessionKey() public {
        vm.prank(user);
        token.setSessionKey(sessionKey, true);
        assertTrue(token.sessionKeys(user, sessionKey));

        vm.prank(user);
        token.setSessionKey(sessionKey, false);
        assertFalse(token.sessionKeys(user, sessionKey));
    }

    function testSessionKeyCanTransferForUser() public {
        token.transfer(user, 100 ether);
        vm.prank(user);
        token.setSessionKey(sessionKey, true);

        vm.prank(sessionKey);
        token.transferFromSession(user, recipient, 10 ether, 77, hex"aa");

        assertEq(token.balanceOf(user), 90 ether);
        assertEq(token.balanceOf(recipient), 10 ether);
    }

    function testSessionKeyCanBatchTransferForUser() public {
        token.transfer(user, 100 ether);
        vm.prank(user);
        token.setSessionKey(sessionKey, true);

        address[] memory tos = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory objectIds = new uint256[](2);
        bytes[] memory objectDatas = new bytes[](2);

        tos[0] = recipient;
        tos[1] = allowedRecipient;
        amounts[0] = 15 ether;
        amounts[1] = 25 ether;
        objectIds[0] = 1;
        objectIds[1] = 2;
        objectDatas[0] = hex"01";
        objectDatas[1] = hex"02";

        vm.prank(sessionKey);
        bool ok = token.batchTransferFromSession(user, tos, amounts, objectIds, objectDatas);

        assertTrue(ok);
        assertEq(token.balanceOf(user), 60 ether);
        assertEq(token.balanceOf(recipient), 15 ether);
        assertEq(token.balanceOf(allowedRecipient), 25 ether);
    }

    function testUnauthorizedSessionKeyCannotTransferForUser() public {
        token.transfer(user, 100 ether);

        vm.prank(sessionKey);
        vm.expectRevert(
            abi.encodeWithSelector(NanoToken.UnauthorizedSessionKey.selector, user, sessionKey)
        );
        token.transferFromSession(user, recipient, 10 ether, 77, hex"aa");
    }

    function testBatchTransferWithDataRejectsArrayLengthMismatch() public {
        address[] memory tos = new address[](2);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory objectIds = new uint256[](2);
        bytes[] memory objectDatas = new bytes[](2);

        tos[0] = recipient;
        tos[1] = allowedRecipient;
        amounts[0] = 1 ether;
        objectIds[0] = 1;
        objectIds[1] = 2;
        objectDatas[0] = hex"01";
        objectDatas[1] = hex"02";

        vm.expectRevert(NanoToken.ArrayLengthMismatch.selector);
        token.batchTransferWithData(tos, amounts, objectIds, objectDatas);
    }

    function testTransferWithSigAcceptsSessionKeySignature() public {
        token.transfer(user, 100 ether);
        vm.prank(user);
        token.setSessionKey(sessionKey, true);

        bytes memory objectData = hex"beef";
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(user);
        bytes32 digest =
            _transferWithSigDigest(user, recipient, 10 ether, 7, objectData, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        token.transferWithSig(user, recipient, 10 ether, 7, objectData, deadline, sig);

        assertEq(token.balanceOf(user), 90 ether);
        assertEq(token.balanceOf(recipient), 10 ether);
        assertEq(token.nonces(user), nonce + 1);
    }

    function testSetSessionKeyWithSig() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.sessionKeyNonces(signer);
        bytes32 digest = _setSessionKeyWithSigDigest(signer, sessionKey, true, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        token.setSessionKeyWithSig(signer, sessionKey, true, deadline, sig);

        assertTrue(token.sessionKeys(signer, sessionKey));
        assertEq(token.sessionKeyNonces(signer), nonce + 1);
    }

    function testSetSessionKeyWithSigRejectsReplay() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.sessionKeyNonces(signer);
        bytes32 digest = _setSessionKeyWithSigDigest(signer, sessionKey, true, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        token.setSessionKeyWithSig(signer, sessionKey, true, deadline, sig);

        vm.expectRevert(NanoToken.InvalidSignature.selector);
        token.setSessionKeyWithSig(signer, sessionKey, true, deadline, sig);
    }

    function testSetSessionKeyWithSigRejectsExpiredSignature() public {
        uint256 deadline = block.timestamp + 1;
        uint256 nonce = token.sessionKeyNonces(signer);
        bytes32 digest = _setSessionKeyWithSigDigest(signer, sessionKey, true, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.warp(deadline + 1);

        vm.expectRevert(abi.encodeWithSelector(NanoToken.ExpiredSignature.selector, deadline));
        token.setSessionKeyWithSig(signer, sessionKey, true, deadline, sig);
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

    function _transferWithSigDigest(
        address from,
        address to,
        uint256 amount,
        uint256 objectId,
        bytes memory objectData,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_WITH_SIG_TYPEHASH,
                from,
                to,
                amount,
                objectId,
                keccak256(objectData),
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("Nano Token")),
                keccak256(bytes("1")),
                block.chainid,
                address(token)
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _setSessionKeyWithSigDigest(
        address account,
        address key,
        bool enabled,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                SET_SESSION_KEY_WITH_SIG_TYPEHASH,
                account,
                key,
                enabled,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("Nano Token")),
                keccak256(bytes("1")),
                block.chainid,
                address(token)
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
