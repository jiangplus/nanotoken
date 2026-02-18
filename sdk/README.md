# nano-token-sdk (viem)

JavaScript SDK for interacting with:

- `NanoToken`
- `FlowableNanoToken`
- `NanoTokenFactory`
- `FlowableNanoTokenFactory`
- `NanoTokenWrapper`

It supports calling **all functions** through generic `read`, `write`, `simulate`, and `estimateGas` methods.
It also includes high-level helpers for:

- EIP-712 signature-based transfer/session-key transactions
- multisig transfer/update approval signing
- deterministic owner-sorted multisig signature ordering

## Install

```bash
cd sdk
npm install
```

## Usage

```js
import { createPublicClient, createWalletClient, http } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { sepolia } from 'viem/chains'
import {
  createNanoTokenSdk,
  createFlowableNanoTokenFactorySdk,
} from './src/index.js'

const account = privateKeyToAccount('0x...')

const publicClient = createPublicClient({ chain: sepolia, transport: http() })
const walletClient = createWalletClient({ chain: sepolia, transport: http(), account })

const nano = createNanoTokenSdk({
  address: '0xYourNanoToken',
  publicClient,
  walletClient,
})

// read any view/pure function
const owner = await nano.read('owner')

// simulate any write
const sim = await nano.simulate('setMinterCredit', ['0xMinter', 1000000000000000000n])

// send any write tx
const hash = await nano.write('setMinterCredit', ['0xMinter', 1000000000000000000n])

const factory = createFlowableNanoTokenFactorySdk({
  address: '0xYourFactory',
  publicClient,
  walletClient,
})

await factory.write('createFlowableNanoToken', [
  account.address,
  'Flow Token',
  'FLOW',
  18,
  1_000_000n * 10n ** 18n,
])

// direct session key tx
await nano.sessionKeys.setDirect({
  walletClient,
  sessionKey: '0xSessionKey',
  enabled: true,
})

// sign + relay session key update
const sessionSig = await nano.sessionKeys.signWithSig({
  walletClient,
  account: account.address,
  sessionKey: '0xSessionKey',
  enabled: true,
})
await nano.sessionKeys.submitWithSig({
  relayerAccount: account,
  account: account.address,
  sessionKey: '0xSessionKey',
  enabled: true,
  deadline: sessionSig.deadline,
  signature: sessionSig.signature,
})

// sign + relay transferWithSig
const transferSig = await nano.signatures.signTransferWithSig({
  walletClient,
  from: account.address,
  to: '0xRecipient',
  amount: 10n * 10n ** 18n,
  objectId: 1n,
  objectData: '0x',
})
await nano.signatures.submitTransferWithSig({
  relayerAccount: account,
  from: account.address,
  to: '0xRecipient',
  amount: 10n * 10n ** 18n,
  objectId: 1n,
  objectData: '0x',
  deadline: transferSig.deadline,
  signature: transferSig.signature,
})
```

## API

Each creator returns an object with:

- `read(functionName, args?, options?)`
- `simulate(functionName, args?, options?)`
- `write(functionName, args?, options?)`
- `estimateGas(functionName, args?, options?)`
- `watchEvent(eventName, options?)`
- `address`, `abi`, `contract`

Contract creators:

- `createNanoTokenSdk`
- `createFlowableNanoTokenSdk`
- `createNanoTokenFactorySdk`
- `createFlowableNanoTokenFactorySdk`
- `createNanoTokenWrapperSdk`

Raw ABIs are also exported from `src/index.js`.

## Signature & Multisig Helpers

Helpers are exported both:

- directly from `src/index.js`, and
- under `nano.sessionKeys` / `nano.signatures` for `NanoToken` and `FlowableNanoToken` SDKs.

Session key helpers:

- `setSessionKeyDirect`
- `signSetSessionKeyWithSig`
- `submitSetSessionKeyWithSig`

Transfer-with-signature helpers:

- `signTransferWithSig`
- `submitTransferWithSig`

Multisig helpers:

- `signMultiSigTransferApproval`
- `submitMultiSigTransfer`
- `signMultiSigUpdateApproval`
- `submitMultiSigUpdate`
- `orderSignaturesByOwner`
- `signaturesFromOrderedApprovals`

Important:

- `NanoToken` requires multisig signatures ordered by resolved owner address.
- Use `orderSignaturesByOwner([...])` before submit to enforce deterministic ordering and avoid contract reverts.

## Regenerate ABIs after contract changes

From repo root:

```bash
npm --prefix sdk run update-abis
```
