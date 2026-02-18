import { getContract } from 'viem';

function resolveAccount(optionsAccount, defaultAccount, walletClient) {
  return optionsAccount ?? defaultAccount ?? walletClient?.account;
}

export function createContractSdk({
  address,
  abi,
  publicClient,
  walletClient,
  account,
}) {
  if (!address) throw new Error('address is required');
  if (!abi) throw new Error('abi is required');
  if (!publicClient) throw new Error('publicClient is required');

  const contract = getContract({
    address,
    abi,
    client: {
      public: publicClient,
      wallet: walletClient,
    },
  });

  return {
    address,
    abi,
    contract,
    read(functionName, args = [], options = {}) {
      return publicClient.readContract({
        address,
        abi,
        functionName,
        args,
        ...options,
      });
    },
    simulate(functionName, args = [], options = {}) {
      const resolved = resolveAccount(options.account, account, walletClient);
      return publicClient.simulateContract({
        address,
        abi,
        functionName,
        args,
        account: resolved,
        ...options,
      });
    },
    async write(functionName, args = [], options = {}) {
      if (!walletClient) throw new Error('walletClient is required for write');
      const resolved = resolveAccount(options.account, account, walletClient);
      if (!resolved) {
        throw new Error('account is required for write (pass options.account or set walletClient.account)');
      }

      return walletClient.writeContract({
        address,
        abi,
        functionName,
        args,
        account: resolved,
        ...options,
      });
    },
    estimateGas(functionName, args = [], options = {}) {
      const resolved = resolveAccount(options.account, account, walletClient);
      return publicClient.estimateContractGas({
        address,
        abi,
        functionName,
        args,
        account: resolved,
        ...options,
      });
    },
    watchEvent(eventName, options = {}) {
      return publicClient.watchContractEvent({
        address,
        abi,
        eventName,
        ...options,
      });
    },
  };
}
