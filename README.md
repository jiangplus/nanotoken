# NanoToken

`NanoToken` is an ERC-20 token built with Foundry and OpenZeppelin, extended with:

- role-based compliance controls (`blacklist`, conditional `whitelist`)
- data-carrying transfers
- gasless EIP-712 signed transfers
- user session keys for delegated actions
- counter-based multisig accounts with threshold signatures
- admin recovery flow for compromised accounts
- capped supply with credit-based delegated minters

## Stack

- Solidity `^0.8.20`
- Foundry (Forge)
- OpenZeppelin Contracts `v5.5.0`

## Contract Overview

Primary contract: `src/NanoToken.sol`

Inheritance:

- `ERC20`
- `ERC20Burnable`
- `Ownable`
- `EIP712`

Token metadata:

- Name: `Nano Token`
- Symbol: `NANO`

## Supply Model

### Initial Supply

- The constructor mints `initialSupply` to the deployer (`owner`).
- `maxSupply` is initialized to `initialSupply`.

### Max Supply

- `maxSupply` is a hard cap enforced on all post-deployment minting.
- Owner can adjust cap via `setMaxSupply(uint256 newMaxSupply)`.
- Guardrail: `newMaxSupply` cannot be below current `totalSupply()`.

### Delegated Minters with Credit

- Owner assigns credit: `setMinterCredit(address minter, uint256 credit)`.
- Minter uses `mint(address to, uint256 amount)`.
- Minting rules:
  - caller must have enough `minterCredits`
  - resulting `totalSupply()` must be `<= maxSupply`
  - credit is decremented by minted amount

Design choice:

- Runtime owner minting was removed to force deterministic delegated issuance with explicit credit budgets.

## Transfer and Policy Controls

### Blacklist

- Owner sets blacklist via `setBlacklist(address account, bool isBlacklisted)`.
- If `from` or `to` is blacklisted, transfer reverts.

### Whitelist (Conditional Transfer Mode)

- Owner sets whitelist via `setWhitelist(address account, bool isWhitelisted)`.
- `whitelistCount` tracks whether whitelist mode is active.
- When `whitelistCount == 0`: normal transfers.
- When `whitelistCount > 0`:
  - owner and whitelisted senders can transfer freely
  - other senders can only:
    - transfer to whitelisted recipients, or
    - burn (`to == address(0)`)

Design choice:

- Whitelist is optional and activates only when non-empty, allowing normal operation by default.

## Data-Carrying Transfers

### Single Transfer

`transferWithData(address to, uint256 amount, uint256 objectId, bytes objectData)`

- Performs token transfer
- Emits `TransferWithData(from, to, amount, objectId, objectData)`

### Batch Transfer

`batchTransferWithData(address[] to, uint256[] amount, uint256[] objectId, bytes[] objectData)`

- Executes multiple transfers in one transaction
- Length mismatch across arrays reverts with `ArrayLengthMismatch()`

Design choice:

- `objectId` + `objectData` supports off-chain indexing and protocol metadata without changing ERC-20 storage model.

## Session Keys

Users can delegate permissions to ephemeral keys.

### Direct Session Key Management

`setSessionKey(address sessionKey, bool enabled)`

- User-owned mapping: `sessionKeys[user][sessionKey]`

### Signature-Based Session Key Management

`setSessionKeyWithSig(address account, address sessionKey, bool enabled, uint256 deadline, bytes signature)`

- EIP-712 signed by `account`
- Replay-protected via `sessionKeyNonces[account]`

### Delegated Session Transfers

- `transferFromSession(...)`
- `batchTransferFromSession(...)`

Both require `sessionKeys[from][msg.sender] == true`.

Design choice:

- Session keys are per-user and revocable; they are also accepted in multisig approvals.

## Gasless Signed Transfers

`transferWithSig(address from, address to, uint256 amount, uint256 objectId, bytes objectData, uint256 deadline, bytes signature)`

- Anyone can relay the tx and pay gas
- Signature signer can be:
  - `from`, or
  - an enabled session key of `from`
- Replay-protected via `nonces[from]`
- Emits `TransferWithData`

Design choice:

- Single `bytes signature` API avoids stack-depth pressure and aligns with common relayer workflows.

## Counter-Based Multisig Accounts

Multisig accounts are represented by incremental `uint256` IDs.

### Account Identity

- New account ID from `nextMultiSigAccountId`.
- Account address is deterministic: `address(uint160(accountId))`.

### Create

`createMultiSigAccount(address[] owners, uint256 threshold)`

- Validates owners/threshold
- Stores owner set and threshold

### Transfer with Threshold Signatures

`transferFromMultiSig(uint256 accountId, address to, uint256 amount, uint256 objectId, bytes objectData, uint256 deadline, bytes[] signatures)`

- EIP-712 digest over transfer payload + nonce + deadline
- Nonce: `multiSigNonces[accountId]`
- Requires threshold valid approvals

### Update Owners/Threshold via Multisig

`updateMultiSigAccount(uint256 accountId, address[] newOwners, uint256 newThreshold, uint256 deadline, bytes[] signatures)`

- Also threshold-authorized and nonce-protected
- Replaces owner set and threshold atomically

### Signature Validation Semantics

- Signers resolve to canonical owners:
  - direct owner signature, or
  - session key signature mapped to its owner
- Approvals must be **strictly increasing by resolved owner address**.
- Duplicate, unsorted, or invalid approvals revert with `MultiSigInvalidSignatures()`.

Design choice:

- Ordered signatures enforce uniqueness deterministically and avoid O(n^2) duplicate scans.

## Account Recovery

`recoverAccount(address oldAccount, address newAccount)` (`onlyOwner`)

- Moves full balance from `oldAccount` to `newAccount`
- Emits `AccountRecovered`
- Returns moved amount

Important behavior:

- Recovery bypasses blacklist/whitelist transfer restrictions during execution to guarantee recoverability.

Design choice:

- Explicit admin recovery was prioritized for operational safety in compromised-account scenarios.

## Security and Replay Protections

- EIP-712 domain: `("Nano Token", "1", chainId, verifyingContract)`
- Independent nonce spaces:
  - `nonces[user]` for token transfer signatures
  - `sessionKeyNonces[user]` for session key management signatures
  - `multiSigNonces[accountId]` for multisig actions
- Deadlines enforced on all signed actions

## Key Events and Errors

Notable events:

- `TransferWithData`
- `SessionKeyUpdated`
- `AccountRecovered`
- `MultiSigAccountCreated`, `MultiSigAccountUpdated`
- `MinterCreditUpdated`, `MinterMinted`
- `MaxSupplyUpdated`

Notable custom errors:

- `BlacklistedAddress`
- `WhitelistRestrictedTransfer`
- `ExpiredSignature`
- `InvalidSignature`
- `UnauthorizedSessionKey`
- `ArrayLengthMismatch`
- `InvalidThreshold`
- `MultiSigAccountNotFound`
- `MultiSigInvalidSignatures`
- `InsufficientMinterCredit`
- `MaxSupplyExceeded`
- `InvalidMaxSupply`

## Development

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Format

```bash
forge fmt
```

## Notes and Tradeoffs

- Multisig account addresses are synthetic (`address(uint160(id))`), not deployed smart contract wallets.
- This keeps execution and state centralized in `NanoToken`, reducing integration complexity but making the token contract the single trust/logic anchor.
- Recovery and policy controls are intentionally admin-strong; governance/role decentralization is out of scope for this version.
