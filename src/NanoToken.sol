// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract NanoToken is ERC20, ERC20Burnable, Ownable, EIP712 {
    bytes32 private constant TRANSFER_WITH_SIG_TYPEHASH =
        keccak256(
            "TransferWithSig(address from,address to,uint256 amount,uint256 objectId,bytes objectData,uint256 nonce,uint256 deadline)"
        );
    bytes32 private constant SET_SESSION_KEY_WITH_SIG_TYPEHASH =
        keccak256(
            "SetSessionKeyWithSig(address account,address sessionKey,bool enabled,uint256 nonce,uint256 deadline)"
        );

    mapping(address => bool) public blacklisted;
    mapping(address => bool) public whitelisted;
    mapping(address => mapping(address => bool)) public sessionKeys;
    mapping(address => uint256) public nonces;
    mapping(address => uint256) public sessionKeyNonces;
    uint256 public whitelistCount;

    error BlacklistedAddress(address account);
    error WhitelistRestrictedTransfer(address from, address to);
    error ExpiredSignature(uint256 deadline);
    error InvalidSignature();
    error UnauthorizedSessionKey(address account, address sessionKey);
    error ArrayLengthMismatch();

    event BlacklistUpdated(address indexed account, bool isBlacklisted);
    event WhitelistUpdated(address indexed account, bool isWhitelisted);
    event SessionKeyUpdated(address indexed account, address indexed sessionKey, bool enabled);
    event TransferWithData(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 objectId,
        bytes objectData
    );

    constructor(uint256 initialSupply) ERC20("Nano Token", "NANO") Ownable(msg.sender) EIP712("Nano Token", "1") {
        _mint(msg.sender, initialSupply);
    }

    function setBlacklist(address account, bool isBlacklisted) external onlyOwner {
        blacklisted[account] = isBlacklisted;
        emit BlacklistUpdated(account, isBlacklisted);
    }

    function setWhitelist(address account, bool isWhitelisted) external onlyOwner {
        bool current = whitelisted[account];
        if (current == isWhitelisted) {
            return;
        }

        whitelisted[account] = isWhitelisted;
        if (isWhitelisted) {
            whitelistCount += 1;
        } else {
            whitelistCount -= 1;
        }
        emit WhitelistUpdated(account, isWhitelisted);
    }

    function setSessionKey(address sessionKey, bool enabled) external {
        sessionKeys[msg.sender][sessionKey] = enabled;
        emit SessionKeyUpdated(msg.sender, sessionKey, enabled);
    }

    function setSessionKeyWithSig(
        address account,
        address sessionKey,
        bool enabled,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) {
            revert ExpiredSignature(deadline);
        }

        uint256 nonce = sessionKeyNonces[account];
        bytes32 structHash = keccak256(
            abi.encode(
                SET_SESSION_KEY_WITH_SIG_TYPEHASH,
                account,
                sessionKey,
                enabled,
                nonce,
                deadline
            )
        );
        if (ECDSA.recover(_hashTypedDataV4(structHash), signature) != account) {
            revert InvalidSignature();
        }

        sessionKeyNonces[account] = nonce + 1;
        sessionKeys[account][sessionKey] = enabled;
        emit SessionKeyUpdated(account, sessionKey, enabled);
    }

    function transferWithData(
        address to,
        uint256 amount,
        uint256 objectId,
        bytes calldata objectData
    ) external returns (bool) {
        _transfer(msg.sender, to, amount);
        emit TransferWithData(msg.sender, to, amount, objectId, objectData);
        return true;
    }

    function batchTransferWithData(
        address[] calldata to,
        uint256[] calldata amount,
        uint256[] calldata objectId,
        bytes[] calldata objectData
    ) external returns (bool) {
        _validateBatchInputs(to.length, amount.length, objectId.length, objectData.length);
        for (uint256 i = 0; i < to.length; i++) {
            _transfer(msg.sender, to[i], amount[i]);
            emit TransferWithData(msg.sender, to[i], amount[i], objectId[i], objectData[i]);
        }
        return true;
    }

    function transferFromSession(
        address from,
        address to,
        uint256 amount,
        uint256 objectId,
        bytes calldata objectData
    ) external returns (bool) {
        if (!sessionKeys[from][msg.sender]) {
            revert UnauthorizedSessionKey(from, msg.sender);
        }

        _transfer(from, to, amount);
        emit TransferWithData(from, to, amount, objectId, objectData);
        return true;
    }

    function batchTransferFromSession(
        address from,
        address[] calldata to,
        uint256[] calldata amount,
        uint256[] calldata objectId,
        bytes[] calldata objectData
    ) external returns (bool) {
        if (!sessionKeys[from][msg.sender]) {
            revert UnauthorizedSessionKey(from, msg.sender);
        }

        _validateBatchInputs(to.length, amount.length, objectId.length, objectData.length);
        for (uint256 i = 0; i < to.length; i++) {
            _transfer(from, to[i], amount[i]);
            emit TransferWithData(from, to[i], amount[i], objectId[i], objectData[i]);
        }
        return true;
    }

    function transferWithSig(
        address from,
        address to,
        uint256 amount,
        uint256 objectId,
        bytes calldata objectData,
        uint256 deadline,
        bytes calldata signature
    ) external returns (bool) {
        if (block.timestamp > deadline) {
            revert ExpiredSignature(deadline);
        }

        uint256 nonce = nonces[from];
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
        address signer = ECDSA.recover(_hashTypedDataV4(structHash), signature);
        if (signer != from && !sessionKeys[from][signer]) {
            revert InvalidSignature();
        }
        nonces[from] = nonce + 1;
        _transfer(from, to, amount);
        emit TransferWithData(from, to, amount, objectId, objectData);
        return true;
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && blacklisted[from]) {
            revert BlacklistedAddress(from);
        }
        if (to != address(0) && blacklisted[to]) {
            revert BlacklistedAddress(to);
        }

        if (from != address(0) && whitelistCount > 0 && !_isWhitelistExemptSender(from)) {
            if (to != address(0) && !whitelisted[to]) {
                revert WhitelistRestrictedTransfer(from, to);
            }
        }

        super._update(from, to, value);
    }

    function _isWhitelistExemptSender(address sender) internal view returns (bool) {
        return sender == owner() || whitelisted[sender];
    }

    function _validateBatchInputs(
        uint256 toLength,
        uint256 amountLength,
        uint256 objectIdLength,
        uint256 objectDataLength
    ) internal pure {
        if (toLength != amountLength || toLength != objectIdLength || toLength != objectDataLength) {
            revert ArrayLengthMismatch();
        }
    }
}
