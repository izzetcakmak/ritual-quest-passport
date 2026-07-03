// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RitualAddresses} from "../RitualAddresses.sol";
import {RitualPassport} from "../RitualPassport.sol";
import {StorageRef} from "../RitualTypes.sol";

/// @title AIOracleQuest
/// @notice Quest #1: ask Ritual's on-chain LLM (precompile 0x0802) a question. A successful
/// (non-error) settled response grants the AI_ORACLE badge.
/// @dev The 30-field LLM Call request must be ABI-encoded off-chain (see the `ritual-dapp-llm`
/// skill for the exact field layout / executor discovery) and passed in as raw `llmInput`
/// bytes. This contract only forwards the bytes and decodes the response envelope — it does
/// not need to know or validate the request encoding.
contract AIOracleQuest {
    RitualPassport public immutable PASSPORT;

    event OracleAsked(address indexed user, bool hasError, string errorMessage);
    event QuestCompleted(address indexed user);

    constructor(RitualPassport passport) {
        PASSPORT = passport;
    }

    function askOracle(bytes calldata llmInput) external returns (bool hasError, string memory errorMessage) {
        (bool ok, bytes memory rawOutput) = RitualAddresses.LLM_PRECOMPILE.call(llmInput);
        require(ok, "AIOracleQuest: precompile call failed");

        // Short-running async envelope: (bytes simmedInput, bytes actualOutput).
        (, bytes memory actualOutput) = abi.decode(rawOutput, (bytes, bytes));
        require(actualOutput.length > 0, "AIOracleQuest: not settled yet (submit a real tx, not eth_call)");

        // completionData / modelMetadata / convoHistory are not needed by this quest — only
        // whether the executor reported an error. Solidity's abi.decode cannot target an
        // inline anonymous tuple, so the trailing StorageRef is decoded against a named struct.
        (hasError,,, errorMessage,) = abi.decode(actualOutput, (bool, bytes, bytes, string, StorageRef));

        emit OracleAsked(msg.sender, hasError, errorMessage);

        if (!hasError) {
            PASSPORT.grantBadge(msg.sender, PASSPORT.BADGE_AI_ORACLE());
            emit QuestCompleted(msg.sender);
        }
    }
}
