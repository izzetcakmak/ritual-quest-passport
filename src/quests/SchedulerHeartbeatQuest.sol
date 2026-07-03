// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RitualAddresses} from "../RitualAddresses.sol";
import {RitualPassport} from "../RitualPassport.sol";
import {IRitualWallet} from "../interfaces/IRitualWallet.sol";
import {IScheduler} from "../interfaces/IScheduler.sol";

/// @title SchedulerHeartbeatQuest
/// @notice Quest #3: register for a Ritual Chain Scheduler-driven recurring "heartbeat".
/// Completing `REQUIRED_HEARTBEATS` executions grants the SCHEDULER badge.
/// @dev Only contracts can call `Scheduler.schedule` (EOAs cannot), so this contract calls it
/// on the user's behalf and is itself the `payer` (funded via `depositForFees`, owner-only) —
/// the same pattern as the `ScheduledHTTPConsumer` example in the `ritual-dapp-scheduler` skill.
/// This keeps the flow simple for a testnet demo: the project owner sponsors scheduling gas
/// for every user's quest instead of requiring each user to pre-authorize this contract via
/// `RitualWallet`/`approveScheduler`.
contract SchedulerHeartbeatQuest {
    uint32 public constant REQUIRED_HEARTBEATS = 3;

    RitualPassport public immutable PASSPORT;
    address public immutable OWNER;

    mapping(address user => uint256 count) public heartbeatCount;
    mapping(address user => uint256 callId) public activeScheduleId;

    event HeartbeatScheduled(address indexed user, uint256 indexed callId, uint32 numCalls, uint32 frequency);
    event Heartbeat(address indexed user, uint256 executionIndex, uint256 totalHeartbeats);
    event QuestCompleted(address indexed user);

    modifier onlyOwner() {
        require(msg.sender == OWNER, "SchedulerHeartbeatQuest: not owner");
        _;
    }

    modifier onlyScheduler() {
        require(msg.sender == RitualAddresses.SCHEDULER, "SchedulerHeartbeatQuest: only Scheduler");
        _;
    }

    constructor(RitualPassport passport) {
        PASSPORT = passport;
        OWNER = msg.sender;
    }

    /// @notice Owner tops up this contract's RitualWallet balance, which funds every user's
    /// scheduled heartbeat executions (`payer = address(this)`).
    function depositForFees(uint256 lockDuration) external payable onlyOwner {
        IRitualWallet(RitualAddresses.RITUAL_WALLET).deposit{value: msg.value}(lockDuration);
    }

    /// @notice Registers `msg.sender` for `REQUIRED_HEARTBEATS` recurring heartbeat executions.
    /// @param frequency Blocks between executions (must be >= 1).
    /// @param gasLimit Gas allotted per heartbeat execution.
    /// @param maxFeePerGas EIP-1559 max fee per gas for scheduled executions.
    function startHeartbeat(uint32 frequency, uint32 gasLimit, uint256 maxFeePerGas) external {
        require(activeScheduleId[msg.sender] == 0, "SchedulerHeartbeatQuest: already scheduled");
        require(frequency >= 1, "SchedulerHeartbeatQuest: frequency must be >= 1");

        // Placeholder executionIndex (0) — the Scheduler overwrites bytes 4-35 of `data` with
        // the real executionIndex at execution time. `user` is preserved as the 2nd argument.
        bytes memory data = abi.encodeWithSelector(this.heartbeat.selector, uint256(0), msg.sender);

        uint256 callId = IScheduler(RitualAddresses.SCHEDULER).schedule(
            data,
            gasLimit,
            uint32(block.number) + frequency, // startBlock
            REQUIRED_HEARTBEATS, // numCalls
            frequency,
            200, // ttl: blocks the Scheduler has to settle each execution
            maxFeePerGas,
            0, // maxPriorityFeePerGas
            0, // value
            address(this) // payer
        );

        activeScheduleId[msg.sender] = callId;
        emit HeartbeatScheduled(msg.sender, callId, REQUIRED_HEARTBEATS, frequency);
    }

    function heartbeat(uint256 executionIndex, address user) external onlyScheduler {
        uint256 total = ++heartbeatCount[user];
        emit Heartbeat(user, executionIndex, total);

        if (total == REQUIRED_HEARTBEATS) {
            PASSPORT.grantBadge(user, PASSPORT.BADGE_SCHEDULER());
            emit QuestCompleted(user);
        }
    }

    function cancelHeartbeat() external {
        uint256 callId = activeScheduleId[msg.sender];
        require(callId != 0, "SchedulerHeartbeatQuest: no active schedule");
        IScheduler(RitualAddresses.SCHEDULER).cancel(callId);
        activeScheduleId[msg.sender] = 0;
    }

    receive() external payable {}
}
