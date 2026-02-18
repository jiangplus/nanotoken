import { createContractSdk } from './core.js';
import { NanoTokenAbi } from './abis/NanoToken.abi.js';
import { FlowableNanoTokenAbi } from './abis/FlowableNanoToken.abi.js';
import { NanoTokenFactoryAbi } from './abis/NanoTokenFactory.abi.js';
import { FlowableNanoTokenFactoryAbi } from './abis/FlowableNanoTokenFactory.abi.js';
import { NanoTokenWrapperAbi } from './abis/NanoTokenWrapper.abi.js';

export function createNanoTokenSdk(config) {
  return createContractSdk({ ...config, abi: NanoTokenAbi });
}

export function createFlowableNanoTokenSdk(config) {
  return createContractSdk({ ...config, abi: FlowableNanoTokenAbi });
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
