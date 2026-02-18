import { encodePacked, getAddress, keccak256 } from 'viem';

const EIP712_VERSION = '1';

const TRANSFER_WITH_SIG_TYPES = {
  TransferWithSig: [
    { name: 'from', type: 'address' },
    { name: 'to', type: 'address' },
    { name: 'amount', type: 'uint256' },
    { name: 'objectId', type: 'uint256' },
    { name: 'objectData', type: 'bytes' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
};

const SET_SESSION_KEY_WITH_SIG_TYPES = {
  SetSessionKeyWithSig: [
    { name: 'account', type: 'address' },
    { name: 'sessionKey', type: 'address' },
    { name: 'enabled', type: 'bool' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
};

const MULTISIG_TRANSFER_TYPES = {
  MultiSigTransfer: [
    { name: 'accountId', type: 'uint256' },
    { name: 'to', type: 'address' },
    { name: 'amount', type: 'uint256' },
    { name: 'objectId', type: 'uint256' },
    { name: 'objectData', type: 'bytes' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
};

const MULTISIG_UPDATE_TYPES = {
  MultiSigUpdate: [
    { name: 'accountId', type: 'uint256' },
    { name: 'ownersHash', type: 'bytes32' },
    { name: 'threshold', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
};

function requireWalletClient(walletClient) {
  if (!walletClient) throw new Error('walletClient is required');
  if (!walletClient.account) throw new Error('walletClient.account is required');
}

async function buildDomain(tokenSdk, tokenName) {
  const name = tokenName ?? (await tokenSdk.read('name'));
  const chainId = await tokenSdk.contract.publicClient.getChainId();

  return {
    name,
    version: EIP712_VERSION,
    chainId,
    verifyingContract: tokenSdk.address,
  };
}

function normalizeAddress(address) {
  return getAddress(address);
}

function addressToBigInt(address) {
  return BigInt(normalizeAddress(address));
}

export function orderSignaturesByOwner(approvals) {
  const seen = new Set();
  const normalized = approvals.map((a) => {
    const owner = normalizeAddress(a.owner);
    const key = owner.toLowerCase();
    if (seen.has(key)) {
      throw new Error(`duplicate owner in approvals: ${owner}`);
    }
    seen.add(key);
    return { owner, signature: a.signature };
  });

  normalized.sort((a, b) => {
    const av = addressToBigInt(a.owner);
    const bv = addressToBigInt(b.owner);
    return av < bv ? -1 : av > bv ? 1 : 0;
  });

  return normalized;
}

export function signaturesFromOrderedApprovals(approvals) {
  return approvals.map((a) => a.signature);
}

export async function signTransferWithSig(tokenSdk, {
  walletClient,
  from,
  to,
  amount,
  objectId = 0n,
  objectData = '0x',
  nonce,
  deadline,
  tokenName,
}) {
  requireWalletClient(walletClient);

  const messageNonce = nonce ?? (await tokenSdk.read('nonces', [from]));
  const messageDeadline = deadline ?? (BigInt(Math.floor(Date.now() / 1000)) + 3600n);
  const domain = await buildDomain(tokenSdk, tokenName);

  const signature = await walletClient.signTypedData({
    account: walletClient.account,
    domain,
    types: TRANSFER_WITH_SIG_TYPES,
    primaryType: 'TransferWithSig',
    message: {
      from,
      to,
      amount,
      objectId,
      objectData,
      nonce: messageNonce,
      deadline: messageDeadline,
    },
  });

  return {
    signature,
    nonce: messageNonce,
    deadline: messageDeadline,
  };
}

export async function submitTransferWithSig(tokenSdk, {
  relayerAccount,
  from,
  to,
  amount,
  objectId = 0n,
  objectData = '0x',
  deadline,
  signature,
}) {
  return tokenSdk.write(
    'transferWithSig',
    [from, to, amount, objectId, objectData, deadline, signature],
    { account: relayerAccount },
  );
}

export async function signSetSessionKeyWithSig(tokenSdk, {
  walletClient,
  account,
  sessionKey,
  enabled,
  nonce,
  deadline,
  tokenName,
}) {
  requireWalletClient(walletClient);

  const messageNonce = nonce ?? (await tokenSdk.read('sessionKeyNonces', [account]));
  const messageDeadline = deadline ?? (BigInt(Math.floor(Date.now() / 1000)) + 3600n);
  const domain = await buildDomain(tokenSdk, tokenName);

  const signature = await walletClient.signTypedData({
    account: walletClient.account,
    domain,
    types: SET_SESSION_KEY_WITH_SIG_TYPES,
    primaryType: 'SetSessionKeyWithSig',
    message: {
      account,
      sessionKey,
      enabled,
      nonce: messageNonce,
      deadline: messageDeadline,
    },
  });

  return {
    signature,
    nonce: messageNonce,
    deadline: messageDeadline,
  };
}

export async function submitSetSessionKeyWithSig(tokenSdk, {
  relayerAccount,
  account,
  sessionKey,
  enabled,
  deadline,
  signature,
}) {
  return tokenSdk.write(
    'setSessionKeyWithSig',
    [account, sessionKey, enabled, deadline, signature],
    { account: relayerAccount },
  );
}

export async function signMultiSigTransferApproval(tokenSdk, {
  walletClient,
  accountId,
  to,
  amount,
  objectId = 0n,
  objectData = '0x',
  nonce,
  deadline,
  tokenName,
}) {
  requireWalletClient(walletClient);

  const messageNonce = nonce ?? (await tokenSdk.read('multiSigNonces', [accountId]));
  const messageDeadline = deadline ?? (BigInt(Math.floor(Date.now() / 1000)) + 3600n);
  const domain = await buildDomain(tokenSdk, tokenName);

  const signature = await walletClient.signTypedData({
    account: walletClient.account,
    domain,
    types: MULTISIG_TRANSFER_TYPES,
    primaryType: 'MultiSigTransfer',
    message: {
      accountId,
      to,
      amount,
      objectId,
      objectData,
      nonce: messageNonce,
      deadline: messageDeadline,
    },
  });

  return {
    owner: walletClient.account.address,
    signature,
    nonce: messageNonce,
    deadline: messageDeadline,
  };
}

export async function submitMultiSigTransfer(tokenSdk, {
  relayerAccount,
  accountId,
  to,
  amount,
  objectId = 0n,
  objectData = '0x',
  deadline,
  approvals,
}) {
  const ordered = orderSignaturesByOwner(approvals);
  const signatures = signaturesFromOrderedApprovals(ordered);

  return tokenSdk.write(
    'transferFromMultiSig',
    [accountId, to, amount, objectId, objectData, deadline, signatures],
    { account: relayerAccount },
  );
}

export function computeOwnersHash(owners) {
  const normalized = owners.map(normalizeAddress);
  return keccak256(encodePacked(Array(normalized.length).fill('address'), normalized));
}

export async function signMultiSigUpdateApproval(tokenSdk, {
  walletClient,
  accountId,
  owners,
  threshold,
  nonce,
  deadline,
  tokenName,
}) {
  requireWalletClient(walletClient);

  const messageNonce = nonce ?? (await tokenSdk.read('multiSigNonces', [accountId]));
  const messageDeadline = deadline ?? (BigInt(Math.floor(Date.now() / 1000)) + 3600n);
  const domain = await buildDomain(tokenSdk, tokenName);

  const ownersHash = computeOwnersHash(owners);

  const signature = await walletClient.signTypedData({
    account: walletClient.account,
    domain,
    types: MULTISIG_UPDATE_TYPES,
    primaryType: 'MultiSigUpdate',
    message: {
      accountId,
      ownersHash,
      threshold,
      nonce: messageNonce,
      deadline: messageDeadline,
    },
  });

  return {
    owner: walletClient.account.address,
    signature,
    nonce: messageNonce,
    deadline: messageDeadline,
  };
}

export async function submitMultiSigUpdate(tokenSdk, {
  relayerAccount,
  accountId,
  owners,
  threshold,
  deadline,
  approvals,
}) {
  const ordered = orderSignaturesByOwner(approvals);
  const signatures = signaturesFromOrderedApprovals(ordered);

  return tokenSdk.write(
    'updateMultiSigAccount',
    [accountId, owners, threshold, deadline, signatures],
    { account: relayerAccount },
  );
}

export async function setSessionKeyDirect(tokenSdk, { walletClient, sessionKey, enabled }) {
  requireWalletClient(walletClient);
  return tokenSdk.write('setSessionKey', [sessionKey, enabled], { account: walletClient.account });
}
