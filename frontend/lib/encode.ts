import { encodeAbiParameters, parseAbiParameters } from 'viem';
import type { Address, Hex } from 'viem';

/**
 * ABI-encodes the 13-field HTTP Call precompile (0x0801) request.
 * Field layout per the Ritual precompile reference (ritual-dapp-http skill).
 */
export function encodeHTTPRequest(executor: Address, url: string): Hex {
  return encodeAbiParameters(
    parseAbiParameters(
      'address, bytes[], uint256, bytes[], bytes, string, uint8, string[], string[], bytes, uint256, uint8, bool',
    ),
    [
      executor,
      [],            // encryptedSecrets
      100n,          // ttl (blocks)
      [],            // secretSignatures
      '0x',          // userPublicKey
      url,
      1,             // method: GET
      ['Accept'],
      ['application/json'],
      '0x',          // body
      0n,            // dkmsKeyIndex
      0,             // dkmsKeyFormat
      false,         // piiEnabled
    ],
  );
}

/**
 * ABI-encodes the 30-field LLM Call precompile (0x0802) request for a stateless one-shot
 * question (empty convoHistory StorageRef — no DA credentials needed).
 * GLM-4.7-FP8 is a reasoning model: maxCompletionTokens >= 4096 and ttl >= 300 blocks.
 */
export function encodeLLMRequest(executor: Address, prompt: string): Hex {
  const messagesJson = JSON.stringify([{ role: 'user', content: prompt }]);

  return encodeAbiParameters(
    parseAbiParameters([
      'address, bytes[], uint256, bytes[], bytes,',
      'string, string, int256, string, bool, int256, string, string,',
      'uint256, bool, int256, string, bytes, int256, string, string, bool,',
      'int256, bytes, bytes, int256, int256, string, bool,',
      '(string,string,string)',
    ].join('')),
    [
      executor,
      [], 300n, [], '0x',
      messagesJson,
      'zai-org/GLM-4.7-FP8',
      0n, '', false, 4096n, '', '',
      1n, true, 0n, 'medium', '0x', -1n, 'auto', '',
      false,                 // stream
      700n, '0x', '0x', -1n, 1000n, '',
      false,                 // piiEnabled
      ['', '', ''],          // convoHistory: empty StorageRef (stateless)
    ],
  );
}
