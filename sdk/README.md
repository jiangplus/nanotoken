# nano-token-sdk (viem)

JavaScript SDK for interacting with:

- `NanoToken`
- `FlowableNanoToken`
- `NanoTokenFactory`
- `FlowableNanoTokenFactory`
- `NanoTokenWrapper`

It supports calling **all functions** through generic `read`, `write`, `simulate`, and `estimateGas` methods.

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

## Regenerate ABIs after contract changes

From repo root:

```bash
npm --prefix sdk run update-abis
```
