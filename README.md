# Nano Token Protocol

This repository contains a token protocol centered on `NanoToken` and `FlowableNanoToken`, plus deployment factories, a shared wrapper, and a `viem` JavaScript SDK.

## Contracts

Source files are in `/Users/jiang/london/nano_token/src`.

### 1) `NanoToken.sol`

An extended ERC-20 with:

- configurable constructor parameters:
  - `admin`
  - `name`
  - `symbol`
  - `decimals`
  - `initialSupply`
- max supply control:
  - `maxSupply` initialized at deployment
  - owner can adjust via `setMaxSupply`
  - minting cannot exceed `maxSupply`
- delegated minters with credit budget:
  - owner sets credit via `setMinterCredit`
  - minter mints via `mint`
  - credit decreases on mint
- blacklist controls:
  - owner-managed `setBlacklist`
  - blocked addresses cannot send or receive
- conditional whitelist mode:
  - owner-managed `setWhitelist`
  - when whitelist is non-empty, restricted senders can only send to whitelisted recipients or burn
  - owner, whitelisted senders, and `address(this)` are exempt
- data-carrying transfers:
  - `transferWithData`
  - `batchTransferWithData`
- session keys:
  - direct set via `setSessionKey`
  - relayed signed set via `setSessionKeyWithSig` (EIP-712 + nonce + deadline)
- gasless signed transfer:
  - `transferWithSig` (user signature or active session key signature)
- session delegated transfer:
  - `transferFromSession`
  - `batchTransferFromSession`
- counter-based multisig accounts:
  - create via `createMultiSigAccount(owners, threshold)`
  - account address: `address(uint160(accountId))`
  - transfer via `transferFromMultiSig` (threshold signatures)
  - update owners/threshold via `updateMultiSigAccount` (threshold signatures)
  - multisig signatures must be ordered by resolved owner address
- admin recovery:
  - `recoverAccount(oldAccount, newAccount)` moves full balance

### 2) `FlowableNanoToken.sol`

Inherits `NanoToken` and adds Flow-style streaming payments.

Flow features:

- create: `createFlow`
- fund: `depositFlow`
- recipient withdraw: `withdrawFlow`, `withdrawMaxFlow`
- sender refund (unstreamed balance): `refundFlow`
- pause/resume by sender: `pauseFlow`, `resumeFlow`
- void by sender or recipient: `voidFlow`
- debt views:
  - `flowTotalDebt`
  - `flowCoveredDebt`
  - `flowUncoveredDebt`
  - `flowWithdrawableAmount`
  - `flowRefundableAmount`

### 3) `NanoTokenFactory.sol`

Deploys configurable `NanoToken` instances:

- `createNanoToken(admin, name, symbol, decimals, initialSupply)`

Registry tracking:

- `isNanoTokenFromFactory[token]`
- `allNanoTokens[]`
- `totalNanoTokens()`

### 4) `FlowableNanoTokenFactory.sol`

Deploys configurable `FlowableNanoToken` instances:

- `createFlowableNanoToken(admin, name, symbol, decimals, initialSupply)`

Registry tracking:

- `isFlowableNanoTokenFromFactory[token]`
- `allFlowableNanoTokens[]`
- `totalFlowableNanoTokens()`

### 5) `NanoTokenWrapper.sol`

A shared wrapper for many NanoToken pairs.

Use case:

- wrapper accepts an external ERC-20 (underlying)
- wrapper mints corresponding `NanoToken`
- wrapper burns `NanoToken` and returns underlying ERC-20

Functions:

- owner configures pair: `setPair(nanoToken, underlying)`
- wrap: `wrap(nanoToken, amount, to)`
- unwrap: `unwrap(nanoToken, amount, to)`

Notes:

- wrapper is reusable across multiple NanoToken contracts
- wrapper must be granted minter credit on each NanoToken it wraps
- unwrap requires user approval for `burnFrom` amount

## SDK (`viem`)

SDK lives in `/Users/jiang/london/nano_token/sdk`.

### Exposed contract SDK creators

- `createNanoTokenSdk`
- `createFlowableNanoTokenSdk`
- `createNanoTokenFactorySdk`
- `createFlowableNanoTokenFactorySdk`
- `createNanoTokenWrapperSdk`

Each contract SDK supports generic calls to all functions:

- `read(functionName, args?, options?)`
- `simulate(functionName, args?, options?)`
- `write(functionName, args?, options?)`
- `estimateGas(functionName, args?, options?)`
- `watchEvent(eventName, options?)`

### Advanced signature helpers

The SDK includes high-level helpers for EIP-712 and multisig:

- session key helpers:
  - `setSessionKeyDirect`
  - `signSetSessionKeyWithSig`
  - `submitSetSessionKeyWithSig`
- transfer signature helpers:
  - `signTransferWithSig`
  - `submitTransferWithSig`
- multisig helpers:
  - `signMultiSigTransferApproval`
  - `submitMultiSigTransfer`
  - `signMultiSigUpdateApproval`
  - `submitMultiSigUpdate`
  - `computeOwnersHash`
- ordering utilities:
  - `orderSignaturesByOwner`
  - `signaturesFromOrderedApprovals`

Important:

- multisig approvals must be submitted in owner-address ascending order (resolved owners)
- use `orderSignaturesByOwner` before submit to avoid reverts

## Testing

Tests are in `/Users/jiang/london/nano_token/test`.

Current suites:

- `NanoToken.t.sol`
- `FlowableNanoToken.t.sol`
- `NanoTokenWrapper.t.sol`

Run tests:

```bash
forge test
```

## Build

```bash
forge build
```

## SDK Install

```bash
cd sdk
npm install
```

## SDK ABI Refresh

After contract ABI changes:

```bash
npm --prefix sdk run update-abis
```
