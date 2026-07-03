// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Scheduler: on-chain recurring/delayed execution system contract.
/// @dev Address: 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B. Only contracts may call
/// `schedule` (EOAs cannot). The Scheduler always calls back `msg.sender` (the caller of
/// `schedule`) — there is no separate `target` parameter. The callback's first parameter
/// (bytes 4-35 of `data`) is overwritten with the real `executionIndex` at execution time.
interface IScheduler {
    function schedule(
        bytes memory data,
        uint32 gas,
        uint32 startBlock,
        uint32 numCalls,
        uint32 frequency,
        uint32 ttl,
        uint256 maxFeePerGas,
        uint256 maxPriorityFeePerGas,
        uint256 value,
        address payer
    ) external returns (uint256 callId);

    function cancel(uint256 callId) external;
    function getCallState(uint256 callId) external view returns (uint8);
    function approveScheduler(address schedulerContract) external;
    function revokeScheduler(address schedulerContract) external;
}

/// CallState: SCHEDULED=0, EXECUTING=1, COMPLETED=2, CANCELLED=3, EXPIRED=4.
interface IScheduledPredicate {
    function shouldExecute(address caller, uint256 callId, uint256 executionIndex) external view returns (bool);
}
