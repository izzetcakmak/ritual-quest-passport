// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Fixed Ritual Chain (id 1979) system contract & precompile addresses.
/// @dev Source: ritual-foundation/ritual-dapp-skills reference (skills/ritual-dapp-contracts).
library RitualAddresses {
    // Precompiles (async, short-running)
    address constant HTTP_PRECOMPILE = address(0x0801);
    address constant LLM_PRECOMPILE = address(0x0802);

    // Precompiles (native/sync)
    address constant JQ_PRECOMPILE = address(0x0803);

    // System contracts
    address constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address constant ASYNC_JOB_TRACKER = 0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5;
    address constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address constant TEE_SERVICE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    address constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address constant SECRETS_ACCESS_CONTROL = 0xf9BF1BC8A3e79B9EBeD0fa2Db70D0513fecE32FD;

    // TEEServiceRegistry capability ids
    uint8 constant CAPABILITY_HTTP_CALL = 0;
    uint8 constant CAPABILITY_LLM = 1;
}
