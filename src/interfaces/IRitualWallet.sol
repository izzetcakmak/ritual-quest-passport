// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice RitualWallet: escrow contract that funds precompile/scheduler fees.
/// @dev Address: 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948 (fixed across Ritual deployments).
interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;
    function depositFor(address user, uint256 lockDuration) external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function lockUntil(address account) external view returns (uint256);
}
