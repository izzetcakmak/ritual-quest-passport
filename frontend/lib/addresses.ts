import type { Address } from 'viem';

// Ritual system contracts — fixed across Ritual Chain deployments, safe to hardcode.
export const RITUAL_WALLET: Address = '0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948';
export const TEE_SERVICE_REGISTRY: Address = '0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F';
export const ASYNC_JOB_TRACKER: Address = '0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5';

// Precompiles
export const HTTP_PRECOMPILE: Address = '0x0000000000000000000000000000000000000801';
export const LLM_PRECOMPILE: Address = '0x0000000000000000000000000000000000000802';

// Our deployed contracts (chain 1979). Overridable via env for redeployments.
export const RITUAL_PASSPORT: Address = (process.env.NEXT_PUBLIC_RITUAL_PASSPORT_ADDRESS ??
  '0x36AAC257c662A35008c40EDe3A022b0b78f44f83') as Address;
export const AI_ORACLE_QUEST: Address = (process.env.NEXT_PUBLIC_AI_ORACLE_QUEST_ADDRESS ??
  '0x81Dbb44d907b65967874b5ce8C66db0c109eF1E7') as Address;
export const HTTP_DATA_QUEST: Address = (process.env.NEXT_PUBLIC_HTTP_DATA_QUEST_ADDRESS ??
  '0x3a18F9282aBeC3c86DF1f1259f2989Ea33aDaBDe') as Address;
export const SCHEDULER_QUEST: Address = (process.env.NEXT_PUBLIC_SCHEDULER_QUEST_ADDRESS ??
  '0xEF9D3CdA66868CEef7C0D5172AaC7ABd9323aD50') as Address;

// Badge bit flags (must match RitualPassport.sol)
export const BADGE_AI_ORACLE = 1;
export const BADGE_HTTP_DATA = 2;
export const BADGE_SCHEDULER = 4;

// TEEServiceRegistry capability ids
export const CAPABILITY_HTTP_CALL = 0;
export const CAPABILITY_LLM = 1;
