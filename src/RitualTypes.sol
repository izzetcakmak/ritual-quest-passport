// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Data-Availability storage pointer used by several Ritual precompiles (e.g. LLM
/// conversation history): DA platform ("gcs"|"hf"|"pinata"), object path, and the key name
/// (in encryptedSecrets) for DA credentials. Solidity's abi.decode cannot target an inline
/// anonymous tuple type, so precompile responses containing a StorageRef must be decoded
/// against this named struct instead.
struct StorageRef {
    string platform;
    string path;
    string keyRef;
}
