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
    bytes32 private constant MULTISIG_TRANSFER_TYPEHASH =
        keccak256(
            "MultiSigTransfer(uint256 accountId,address to,uint256 amount,uint256 objectId,bytes objectData,uint256 nonce,uint256 deadline)"
        );
    bytes32 private constant MULTISIG_UPDATE_TYPEHASH =
        keccak256(
            "MultiSigUpdate(uint256 accountId,bytes32 ownersHash,uint256 threshold,uint256 nonce,uint256 deadline)"
        );

    mapping(address => bool) public blacklisted;
    mapping(address => bool) public whitelisted;
    mapping(address => mapping(address => bool)) public sessionKeys;
    mapping(address => uint256) public minterCredits;
    mapping(address => uint256) public nonces;
    mapping(address => uint256) public sessionKeyNonces;
    mapping(uint256 => mapping(address => bool)) public multiSigOwners;
    mapping(uint256 => address[]) private multiSigOwnerList;
    mapping(uint256 => uint256) public multiSigThreshold;
    mapping(uint256 => uint256) public multiSigNonces;
    uint256 public nextMultiSigAccountId;
    uint256 public maxSupply;
    uint256 public whitelistCount;
    bool private recoveryTransferActive;

    error BlacklistedAddress(address account);
    error WhitelistRestrictedTransfer(address from, address to);
    error ExpiredSignature(uint256 deadline);
    error InvalidSignature();
    error UnauthorizedSessionKey(address account, address sessionKey);
    error ArrayLengthMismatch();
    error InvalidThreshold();
    error MultiSigAccountNotFound(uint256 accountId);
    error MultiSigInvalidSignatures();
    error InsufficientMinterCredit(address minter, uint256 available, uint256 requested);
    error MaxSupplyExceeded(uint256 maxSupply, uint256 requestedTotalSupply);
    error InvalidMaxSupply(uint256 maxSupply, uint256 currentSupply);

    event BlacklistUpdated(address indexed account, bool isBlacklisted);
    event WhitelistUpdated(address indexed account, bool isWhitelisted);
    event SessionKeyUpdated(address indexed account, address indexed sessionKey, bool enabled);
    event MinterCreditUpdated(address indexed minter, uint256 credit);
    event MinterMinted(address indexed minter, address indexed to, uint256 amount);
    event MaxSupplyUpdated(uint256 maxSupply);
    event AccountRecovered(address indexed oldAccount, address indexed newAccount, uint256 amount);
    event MultiSigAccountCreated(uint256 indexed accountId, uint256 threshold);
    event MultiSigAccountUpdated(uint256 indexed accountId, uint256 threshold);
    event TransferWithData(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 objectId,
        bytes objectData
    );

    constructor(uint256 initialSupply) ERC20("Nano Token", "NANO") Ownable(msg.sender) EIP712("Nano Token", "1") {
        maxSupply = initialSupply;
        _mint(msg.sender, initialSupply);
        nextMultiSigAccountId = 1;
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

    function setMinterCredit(address minter, uint256 credit) external onlyOwner {
        minterCredits[minter] = credit;
        emit MinterCreditUpdated(minter, credit);
    }

    function setMaxSupply(uint256 newMaxSupply) external onlyOwner {
        uint256 supply = totalSupply();
        if (newMaxSupply < supply) {
            revert InvalidMaxSupply(newMaxSupply, supply);
        }
        maxSupply = newMaxSupply;
        emit MaxSupplyUpdated(newMaxSupply);
    }

    function mint(address to, uint256 amount) external returns (bool) {
        uint256 credit = minterCredits[msg.sender];
        if (credit < amount) {
            revert InsufficientMinterCredit(msg.sender, credit, amount);
        }
        uint256 newSupply = totalSupply() + amount;
        if (newSupply > maxSupply) {
            revert MaxSupplyExceeded(maxSupply, newSupply);
        }

        minterCredits[msg.sender] = credit - amount;
        _mint(to, amount);
        emit MinterMinted(msg.sender, to, amount);
        return true;
    }

    function createMultiSigAccount(address[] calldata owners, uint256 threshold) external returns (uint256 accountId) {
        _validateOwnersAndThreshold(owners, threshold);

        accountId = nextMultiSigAccountId;
        nextMultiSigAccountId += 1;

        address[] storage ownerList = multiSigOwnerList[accountId];
        for (uint256 i = 0; i < owners.length; i++) {
            address owner = owners[i];
            if (multiSigOwners[accountId][owner]) {
                revert MultiSigInvalidSignatures();
            }
            multiSigOwners[accountId][owner] = true;
            ownerList.push(owner);
        }

        multiSigThreshold[accountId] = threshold;
        emit MultiSigAccountCreated(accountId, threshold);
    }

    function multiSigAccountAddress(uint256 accountId) public pure returns (address) {
        return address(uint160(accountId));
    }

    function getMultiSigOwners(uint256 accountId) external view returns (address[] memory) {
        return multiSigOwnerList[accountId];
    }

    function recoverAccount(address oldAccount, address newAccount) external onlyOwner returns (uint256 amount) {
        amount = balanceOf(oldAccount);
        if (amount == 0 || oldAccount == newAccount) {
            return amount;
        }

        recoveryTransferActive = true;
        _transfer(oldAccount, newAccount, amount);
        recoveryTransferActive = false;
        emit AccountRecovered(oldAccount, newAccount, amount);
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

    function transferFromMultiSig(
        uint256 accountId,
        address to,
        uint256 amount,
        uint256 objectId,
        bytes calldata objectData,
        uint256 deadline,
        bytes[] calldata signatures
    ) external returns (bool) {
        _requireMultiSigAccountExists(accountId);
        if (block.timestamp > deadline) {
            revert ExpiredSignature(deadline);
        }

        uint256 nonce = multiSigNonces[accountId];
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
        _validateMultiSigApprovals(accountId, _hashTypedDataV4(structHash), signatures);
        multiSigNonces[accountId] = nonce + 1;

        address from = multiSigAccountAddress(accountId);
        _transfer(from, to, amount);
        emit TransferWithData(from, to, amount, objectId, objectData);
        return true;
    }

    function updateMultiSigAccount(
        uint256 accountId,
        address[] calldata newOwners,
        uint256 newThreshold,
        uint256 deadline,
        bytes[] calldata signatures
    ) external {
        _requireMultiSigAccountExists(accountId);
        _validateOwnersAndThreshold(newOwners, newThreshold);
        if (block.timestamp > deadline) {
            revert ExpiredSignature(deadline);
        }

        uint256 nonce = multiSigNonces[accountId];
        bytes32 structHash = keccak256(
            abi.encode(
                MULTISIG_UPDATE_TYPEHASH,
                accountId,
                keccak256(abi.encodePacked(newOwners)),
                newThreshold,
                nonce,
                deadline
            )
        );
        _validateMultiSigApprovals(accountId, _hashTypedDataV4(structHash), signatures);
        multiSigNonces[accountId] = nonce + 1;

        address[] storage ownerList = multiSigOwnerList[accountId];
        for (uint256 i = 0; i < ownerList.length; i++) {
            multiSigOwners[accountId][ownerList[i]] = false;
        }
        delete multiSigOwnerList[accountId];

        address[] storage newOwnerList = multiSigOwnerList[accountId];
        for (uint256 i = 0; i < newOwners.length; i++) {
            address owner = newOwners[i];
            if (multiSigOwners[accountId][owner]) {
                revert MultiSigInvalidSignatures();
            }
            multiSigOwners[accountId][owner] = true;
            newOwnerList.push(owner);
        }
        multiSigThreshold[accountId] = newThreshold;
        emit MultiSigAccountUpdated(accountId, newThreshold);
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
        if (!recoveryTransferActive) {
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

    function _requireMultiSigAccountExists(uint256 accountId) internal view {
        if (accountId == 0 || accountId >= nextMultiSigAccountId) {
            revert MultiSigAccountNotFound(accountId);
        }
    }

    function _validateOwnersAndThreshold(address[] calldata owners, uint256 threshold) internal pure {
        if (owners.length == 0 || threshold == 0 || threshold > owners.length) {
            revert InvalidThreshold();
        }
    }

    function _validateMultiSigApprovals(
        uint256 accountId,
        bytes32 digest,
        bytes[] calldata signatures
    ) internal view {
        uint256 threshold = multiSigThreshold[accountId];
        if (signatures.length < threshold) {
            revert MultiSigInvalidSignatures();
        }

        address[] storage owners = multiSigOwnerList[accountId];
        uint256 approvedCount;
        address lastOwner;

        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = ECDSA.recover(digest, signatures[i]);
            address owner = _resolveMultiSigOwner(accountId, signer, owners);
            if (owner == address(0) || owner <= lastOwner) {
                revert MultiSigInvalidSignatures();
            }

            lastOwner = owner;
            approvedCount += 1;
            if (approvedCount >= threshold) {
                return;
            }
        }

        revert MultiSigInvalidSignatures();
    }

    function _resolveMultiSigOwner(
        uint256 accountId,
        address signer,
        address[] storage owners
    ) internal view returns (address) {
        if (multiSigOwners[accountId][signer]) {
            return signer;
        }

        for (uint256 i = 0; i < owners.length; i++) {
            address owner = owners[i];
            if (sessionKeys[owner][signer]) {
                return owner;
            }
        }
        return address(0);
    }

}
