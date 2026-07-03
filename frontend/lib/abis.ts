export const ritualPassportAbi = [
  {
    name: 'badgesOf', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ type: 'uint8' }],
  },
  {
    name: 'tokenIdOf', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'tokenURI', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ type: 'string' }],
  },
] as const;

export const aiOracleQuestAbi = [
  {
    name: 'askOracle', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'llmInput', type: 'bytes' }],
    outputs: [{ name: 'hasError', type: 'bool' }, { name: 'errorMessage', type: 'string' }],
  },
] as const;

export const httpDataQuestAbi = [
  {
    name: 'fetchData', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'httpInput', type: 'bytes' }],
    outputs: [{ name: 'statusCode', type: 'uint16' }, { name: 'errorMessage', type: 'string' }],
  },
] as const;

export const schedulerQuestAbi = [
  {
    name: 'startHeartbeat', type: 'function', stateMutability: 'nonpayable',
    inputs: [
      { name: 'frequency', type: 'uint32' },
      { name: 'gasLimit', type: 'uint32' },
      { name: 'maxFeePerGas', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    name: 'heartbeatCount', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'activeScheduleId', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'REQUIRED_HEARTBEATS', type: 'function', stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint32' }],
  },
] as const;

export const ritualWalletAbi = [
  {
    name: 'deposit', type: 'function', stateMutability: 'payable',
    inputs: [{ name: 'lockDuration', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'balanceOf', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'lockUntil', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
] as const;

export const teeServiceRegistryAbi = [
  {
    name: 'getServicesByCapability', type: 'function', stateMutability: 'view',
    inputs: [
      { name: 'capability', type: 'uint8' },
      { name: 'checkValidity', type: 'bool' },
    ],
    outputs: [{
      type: 'tuple[]',
      components: [
        {
          name: 'node', type: 'tuple', components: [
            { name: 'paymentAddress', type: 'address' },
            { name: 'teeAddress', type: 'address' },
            { name: 'teeType', type: 'uint8' },
            { name: 'publicKey', type: 'bytes' },
            { name: 'endpoint', type: 'string' },
            { name: 'certPubKeyHash', type: 'bytes32' },
            { name: 'capability', type: 'uint8' },
          ],
        },
        { name: 'isValid', type: 'bool' },
        { name: 'workloadId', type: 'bytes32' },
      ],
    }],
  },
] as const;
