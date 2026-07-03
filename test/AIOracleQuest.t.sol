// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RitualAddresses} from "../src/RitualAddresses.sol";
import {RitualPassport} from "../src/RitualPassport.sol";
import {AIOracleQuest} from "../src/quests/AIOracleQuest.sol";
import {StorageRef} from "../src/RitualTypes.sol";

contract AIOracleQuestTest is Test {
    RitualPassport passport;
    AIOracleQuest quest;
    address user = makeAddr("user");

    function setUp() public {
        passport = new RitualPassport();
        quest = new AIOracleQuest(passport);
        passport.setQuestAuthorized(address(quest), true);
    }

    function _mockLLMResponse(bool hasError, string memory errorMessage) internal {
        bytes memory innerResponse = abi.encode(
            hasError, bytes(""), bytes(""), errorMessage, StorageRef({platform: "", path: "", keyRef: ""})
        );
        bytes memory spcEnvelope = abi.encode(bytes("simulated-input"), innerResponse);
        vm.mockCall(RitualAddresses.LLM_PRECOMPILE, bytes(""), spcEnvelope);
    }

    function test_SuccessfulInference_GrantsBadge() public {
        _mockLLMResponse(false, "");

        vm.prank(user);
        (bool hasError, string memory err) = quest.askOracle(bytes("any-encoded-llm-input"));

        assertFalse(hasError);
        assertEq(err, "");
        assertTrue(passport.hasBadge(user, passport.BADGE_AI_ORACLE()));
    }

    function test_ErrorResponse_DoesNotGrantBadge() public {
        _mockLLMResponse(true, "context length exceeded");

        vm.prank(user);
        (bool hasError, string memory err) = quest.askOracle(bytes("any-encoded-llm-input"));

        assertTrue(hasError);
        assertEq(err, "context length exceeded");
        assertFalse(passport.hasBadge(user, passport.BADGE_AI_ORACLE()));
        assertEq(passport.balanceOf(user), 0);
    }

    function test_UnsettledSimulation_Reverts() public {
        // eth_call simulation: actualOutput is empty — should revert with a clear message
        // instead of silently granting a badge or decoding garbage.
        bytes memory spcEnvelope = abi.encode(bytes("simulated-input"), bytes(""));
        vm.mockCall(RitualAddresses.LLM_PRECOMPILE, bytes(""), spcEnvelope);

        vm.expectRevert("AIOracleQuest: not settled yet (submit a real tx, not eth_call)");
        quest.askOracle(bytes("any-encoded-llm-input"));
    }
}
