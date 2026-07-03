// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RitualAddresses} from "../src/RitualAddresses.sol";
import {RitualPassport} from "../src/RitualPassport.sol";
import {SchedulerHeartbeatQuest} from "../src/quests/SchedulerHeartbeatQuest.sol";
import {IScheduler} from "../src/interfaces/IScheduler.sol";

contract SchedulerHeartbeatQuestTest is Test {
    RitualPassport passport;
    SchedulerHeartbeatQuest quest;
    address owner = address(this);
    address user = makeAddr("user");

    function setUp() public {
        passport = new RitualPassport();
        quest = new SchedulerHeartbeatQuest(passport);
        passport.setQuestAuthorized(address(quest), true);

        // Scheduler.schedule(...) always returns callId = 42 regardless of arguments.
        vm.mockCall(RitualAddresses.SCHEDULER, abi.encodeWithSelector(IScheduler.schedule.selector), abi.encode(uint256(42)));
        vm.mockCall(RitualAddresses.SCHEDULER, abi.encodeWithSelector(IScheduler.cancel.selector), bytes(""));
    }

    function test_OnlyOwnerCanDepositForFees() public {
        vm.deal(makeAddr("notOwner"), 1 ether);
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("SchedulerHeartbeatQuest: not owner");
        quest.depositForFees{value: 0.1 ether}(1000);
    }

    function test_StartHeartbeat_RegistersSchedule() public {
        vm.prank(user);
        quest.startHeartbeat(10, 300_000, 1 gwei);

        assertEq(quest.activeScheduleId(user), 42);
    }

    function test_StartHeartbeat_RevertsIfAlreadyScheduled() public {
        vm.startPrank(user);
        quest.startHeartbeat(10, 300_000, 1 gwei);

        vm.expectRevert("SchedulerHeartbeatQuest: already scheduled");
        quest.startHeartbeat(10, 300_000, 1 gwei);
        vm.stopPrank();
    }

    function test_OnlySchedulerCanCallHeartbeat() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert("SchedulerHeartbeatQuest: only Scheduler");
        quest.heartbeat(0, user);
    }

    function test_ThirdHeartbeat_GrantsBadge() public {
        vm.startPrank(RitualAddresses.SCHEDULER);
        quest.heartbeat(0, user);
        assertFalse(passport.hasBadge(user, passport.BADGE_SCHEDULER()));

        quest.heartbeat(1, user);
        assertFalse(passport.hasBadge(user, passport.BADGE_SCHEDULER()));

        quest.heartbeat(2, user);
        vm.stopPrank();

        assertTrue(passport.hasBadge(user, passport.BADGE_SCHEDULER()));
        assertEq(quest.heartbeatCount(user), 3);
    }

    function test_CancelHeartbeat() public {
        vm.startPrank(user);
        quest.startHeartbeat(10, 300_000, 1 gwei);
        quest.cancelHeartbeat();
        vm.stopPrank();

        assertEq(quest.activeScheduleId(user), 0);
    }

    function test_CancelHeartbeat_RevertsWithoutActiveSchedule() public {
        vm.prank(user);
        vm.expectRevert("SchedulerHeartbeatQuest: no active schedule");
        quest.cancelHeartbeat();
    }
}
