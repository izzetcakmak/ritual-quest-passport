// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RitualAddresses} from "../src/RitualAddresses.sol";
import {RitualPassport} from "../src/RitualPassport.sol";
import {HTTPDataQuest} from "../src/quests/HTTPDataQuest.sol";

contract HTTPDataQuestTest is Test {
    RitualPassport passport;
    HTTPDataQuest quest;
    address user = makeAddr("user");

    function setUp() public {
        passport = new RitualPassport();
        quest = new HTTPDataQuest(passport);
        passport.setQuestAuthorized(address(quest), true);
    }

    function _mockHTTPResponse(uint16 statusCode, bytes memory body, string memory errorMessage) internal {
        bytes memory innerResponse =
            abi.encode(statusCode, new string[](0), new string[](0), body, errorMessage);
        bytes memory spcEnvelope = abi.encode(bytes("simulated-input"), innerResponse);
        vm.mockCall(RitualAddresses.HTTP_PRECOMPILE, bytes(""), spcEnvelope);
    }

    function test_Success200_GrantsBadge() public {
        _mockHTTPResponse(200, bytes('{"ethereum":{"usd":3500}}'), "");

        vm.prank(user);
        (uint16 status, string memory err) = quest.fetchData(bytes("any-encoded-http-input"));

        assertEq(status, 200);
        assertEq(err, "");
        assertTrue(passport.hasBadge(user, passport.BADGE_HTTP_DATA()));
    }

    function test_HTTPError404_DoesNotGrantBadge() public {
        _mockHTTPResponse(404, bytes(""), "");

        vm.prank(user);
        (uint16 status,) = quest.fetchData(bytes("any-encoded-http-input"));

        assertEq(status, 404);
        assertFalse(passport.hasBadge(user, passport.BADGE_HTTP_DATA()));
    }

    function test_ExecutorError_DoesNotGrantBadge() public {
        _mockHTTPResponse(0, bytes(""), "executor timeout");

        vm.prank(user);
        (, string memory err) = quest.fetchData(bytes("any-encoded-http-input"));

        assertEq(err, "executor timeout");
        assertFalse(passport.hasBadge(user, passport.BADGE_HTTP_DATA()));
    }

    function test_UnsettledSimulation_Reverts() public {
        bytes memory spcEnvelope = abi.encode(bytes("simulated-input"), bytes(""));
        vm.mockCall(RitualAddresses.HTTP_PRECOMPILE, bytes(""), spcEnvelope);

        vm.expectRevert("HTTPDataQuest: not settled yet (submit a real tx, not eth_call)");
        quest.fetchData(bytes("any-encoded-http-input"));
    }
}
