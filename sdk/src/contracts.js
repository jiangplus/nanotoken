import { createContractSdk } from './core.js';
import { NanoTokenAbi } from './abis/NanoToken.abi.js';
import { FlowableNanoTokenAbi } from './abis/FlowableNanoToken.abi.js';
import { NanoTokenFactoryAbi } from './abis/NanoTokenFactory.abi.js';
import { FlowableNanoTokenFactoryAbi } from './abis/FlowableNanoTokenFactory.abi.js';
import { NanoTokenWrapperAbi } from './abis/NanoTokenWrapper.abi.js';
import {
  setSessionKeyDirect,
  signSetSessionKeyWithSig,
  submitSetSessionKeyWithSig,
  signTransferWithSig,
  submitTransferWithSig,
  signMultiSigTransferApproval,
  submitMultiSigTransfer,
  signMultiSigUpdateApproval,
  submitMultiSigUpdate,
} from './nanoTokenSignatures.js';

function withNanoTokenHelpers(sdk) {
  return {
    ...sdk,
    sessionKeys: {
      setDirect: (params) => setSessionKeyDirect(sdk, params),
      signWithSig: (params) => signSetSessionKeyWithSig(sdk, params),
      submitWithSig: (params) => submitSetSessionKeyWithSig(sdk, params),
    },
    signatures: {
      signTransferWithSig: (params) => signTransferWithSig(sdk, params),
      submitTransferWithSig: (params) => submitTransferWithSig(sdk, params),
      signMultiSigTransferApproval: (params) => signMultiSigTransferApproval(sdk, params),
      submitMultiSigTransfer: (params) => submitMultiSigTransfer(sdk, params),
      signMultiSigUpdateApproval: (params) => signMultiSigUpdateApproval(sdk, params),
      submitMultiSigUpdate: (params) => submitMultiSigUpdate(sdk, params),
    },
  };
}

export function createNanoTokenSdk(config) {
  return withNanoTokenHelpers(createContractSdk({ ...config, abi: NanoTokenAbi }));
}

export function createFlowableNanoTokenSdk(config) {
  return withNanoTokenHelpers(createContractSdk({ ...config, abi: FlowableNanoTokenAbi }));
}

export function createNanoTokenFactorySdk(config) {
  return createContractSdk({ ...config, abi: NanoTokenFactoryAbi });
}

export function createFlowableNanoTokenFactorySdk(config) {
  return createContractSdk({ ...config, abi: FlowableNanoTokenFactoryAbi });
}

export function createNanoTokenWrapperSdk(config) {
  return createContractSdk({ ...config, abi: NanoTokenWrapperAbi });
}
