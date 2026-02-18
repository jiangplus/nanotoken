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
    bytes32 internal constant MULTISIG_TRANSFER_TYPEHASH =
        keccak256(
            "MultiSigTransfer(uint256 accountId,address to,uint256 amount,uint256 objectId,bytes objectData,uint256 nonce,uint256 deadline)"
        );
    bytes32 internal constant MULTISIG_UPDATE_TYPEHASH =
        keccak256(
            "MultiSigUpdate(uint256 accountId,bytes32 ownersHash,uint256 threshold,uint256 nonce,uint256 deadline)"
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
    uint256 internal owner1Pk;
    uint256 internal owner2Pk;
    uint256 internal owner3Pk;
    address internal owner1;
    address internal owner2;
    address internal owner3;
    uint256 internal owner1SessionPk;
    address internal owner1SessionKey;

    function setUp() public {
        token = new NanoToken(1_000_000 ether);
        signerPk = 0xA11CE;
        signer = vm.addr(signerPk);
        sessionPk = 0xB0B;
        sessionKey = vm.addr(sessionPk);
        owner1Pk = 0x1001;
        owner2Pk = 0x1002;
        owner3Pk = 0x1003;
        owner1 = vm.addr(owner1Pk);
        owner2 = vm.addr(owner2Pk);
        owner3 = vm.addr(owner3Pk);
        owner1SessionPk = 0x2001;
        owner1SessionKey = vm.addr(owner1SessionPk);
    }

    function testInitialSupplyMintedToDeployer() public view {
        assertEq(token.totalSupply(), 1_000_000 ether);
        assertEq(token.balanceOf(address(this)), 1_000_000 ether);
    }

    function testOwnerIsCreator() public view {
        assertEq(token.owner(), address(this));
    }

    function testInitialMaxSupplyEqualsInitialSupply() public view {
        assertEq(token.maxSupply(), 1_000_000 ether);
    }

    function testOwnerCanSetMinterCreditAndMinterCanMint() public {
        token.setMaxSupply(1_000_100 ether);
        token.setMinterCredit(user, 100 ether);

        vm.prank(user);
        bool ok = token.mint(recipient, 25 ether);

        assertTrue(ok);
        assertEq(token.balanceOf(recipient), 25 ether);
        assertEq(token.totalSupply(), 1_000_025 ether);
        assertEq(token.minterCredits(user), 75 ether);
    }

    function testMinterCannotExceedCredit() public {
        token.setMaxSupply(1_000_100 ether);
        token.setMinterCredit(user, 10 ether);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                NanoToken.InsufficientMinterCredit.selector, user, 10 ether, 11 ether
            )
        );
        token.mint(recipient, 11 ether);
    }

    function testNonOwnerCannotSetMinterCredit() public {
        vm.prank(user);
        vm.expectRevert();
        token.setMinterCredit(user, 100 ether);
    }

    function testOwnerCanAdjustMinterCredit() public {
        token.setMaxSupply(1_000_100 ether);
        token.setMinterCredit(user, 100 ether);
        token.setMinterCredit(user, 40 ether);

        vm.prank(user);
        token.mint(recipient, 40 ether);
        assertEq(token.minterCredits(user), 0);
    }

    function testNonOwnerCannotSetMaxSupply() public {
        vm.prank(user);
        vm.expectRevert();
        token.setMaxSupply(2_000_000 ether);
    }

    function testOwnerCanAdjustMaxSupply() public {
        token.setMaxSupply(2_000_000 ether);
        assertEq(token.maxSupply(), 2_000_000 ether);
    }

    function testCannotSetMaxSupplyBelowCurrentSupply() public {
        vm.expectRevert(
            abi.encodeWithSelector(NanoToken.InvalidMaxSupply.selector, 999_999 ether, 1_000_000 ether)
        );
        token.setMaxSupply(999_999 ether);
    }

    function testMintCannotExceedMaxSupply() public {
        token.setMinterCredit(user, 1 ether);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                NanoToken.MaxSupplyExceeded.selector, 1_000_000 ether, 1_000_001 ether
            )
        );
        token.mint(recipient, 1 ether);
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

    function testCreateAndTransferFromMultiSig() public {
        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;
        uint256 accountId = token.createMultiSigAccount(owners, 2);
        address msAccount = token.multiSigAccountAddress(accountId);
        token.transfer(msAccount, 100 ether);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.multiSigNonces(accountId);
        bytes memory objectData = hex"aa";
        bytes32 digest = _multiSigTransferDigest(
            accountId, recipient, 10 ether, 9, objectData, nonce, deadline
        );
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _sign(owner1Pk, digest);
        signatures[1] = _sign(owner2Pk, digest);

        bool ok =
            token.transferFromMultiSig(accountId, recipient, 10 ether, 9, objectData, deadline, signatures);

        assertTrue(ok);
        assertEq(token.balanceOf(msAccount), 90 ether);
        assertEq(token.balanceOf(recipient), 10 ether);
    }

    function testCreateMultiSigRejectsZeroOwner() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = address(0);

        vm.expectRevert(abi.encodeWithSelector(NanoToken.InvalidMultiSigOwner.selector, address(0)));
        token.createMultiSigAccount(owners, 2);
    }

    function testCreateMultiSigAllowsDuplicateOwner() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner1;

        uint256 accountId = token.createMultiSigAccount(owners, 2);
        assertEq(token.multiSigThreshold(accountId), 2);
        assertTrue(token.multiSigOwners(accountId, owner1));
    }

    function testMultiSigTransferAcceptsSessionKeySignatures() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner2;
        uint256 accountId = token.createMultiSigAccount(owners, 2);
        address msAccount = token.multiSigAccountAddress(accountId);
        token.transfer(msAccount, 100 ether);

        vm.prank(owner1);
        token.setSessionKey(owner1SessionKey, true);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.multiSigNonces(accountId);
        bytes memory objectData = hex"bb";
        bytes32 digest = _multiSigTransferDigest(
            accountId, recipient, 20 ether, 10, objectData, nonce, deadline
        );
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _sign(owner1SessionPk, digest);
        signatures[1] = _sign(owner2Pk, digest);

        token.transferFromMultiSig(accountId, recipient, 20 ether, 10, objectData, deadline, signatures);
        assertEq(token.balanceOf(msAccount), 80 ether);
        assertEq(token.balanceOf(recipient), 20 ether);
    }

    function testUpdateMultiSigAccountWithThresholdSignatures() public {
        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;
        uint256 accountId = token.createMultiSigAccount(owners, 2);

        address[] memory newOwners = new address[](2);
        newOwners[0] = owner1;
        newOwners[1] = owner3;

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.multiSigNonces(accountId);
        bytes32 digest = _multiSigUpdateDigest(accountId, newOwners, 1, nonce, deadline);
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _sign(owner1Pk, digest);
        signatures[1] = _sign(owner2Pk, digest);

        token.updateMultiSigAccount(accountId, newOwners, 1, deadline, signatures);

        assertEq(token.multiSigThreshold(accountId), 1);
        assertTrue(token.multiSigOwners(accountId, owner1));
        assertFalse(token.multiSigOwners(accountId, owner2));
        assertTrue(token.multiSigOwners(accountId, owner3));
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

    function testOwnerCanRecoverAccount() public {
        token.transfer(user, 100 ether);

        uint256 moved = token.recoverAccount(user, recipient);

        assertEq(moved, 100 ether);
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(recipient), 100 ether);
    }

    function testNonOwnerCannotRecoverAccount() public {
        vm.prank(user);
        vm.expectRevert();
        token.recoverAccount(signer, recipient);
    }

    function testOwnerCanRecoverBlacklistedAccount() public {
        token.transfer(user, 100 ether);
        token.setBlacklist(user, true);

        uint256 moved = token.recoverAccount(user, recipient);

        assertEq(moved, 100 ether);
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(recipient), 100 ether);
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

    function _multiSigTransferDigest(
        uint256 accountId,
        address to,
        uint256 amount,
        uint256 objectId,
        bytes memory objectData,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                MULTISIG_TRANSFER_TYPEHASH,
                accountId,
                to,
                amount,
                objectId,
                keccak256(objectData),
                nonce,
                deadline
            )
        );
        return _typedDataDigest(structHash);
    }

    function _multiSigUpdateDigest(
        uint256 accountId,
        address[] memory owners,
        uint256 threshold,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                MULTISIG_UPDATE_TYPEHASH,
                accountId,
                keccak256(abi.encodePacked(owners)),
                threshold,
                nonce,
                deadline
            )
        );
        return _typedDataDigest(structHash);
    }

    function _typedDataDigest(bytes32 structHash) internal view returns (bytes32) {
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

    function _sign(uint256 pk, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
