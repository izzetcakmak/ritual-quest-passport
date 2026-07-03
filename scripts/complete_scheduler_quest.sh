#!/usr/bin/env bash
# Completes Quest #3 (SchedulerHeartbeatQuest) on Ritual testnet: registers the caller for
# REQUIRED_HEARTBEATS (3) recurring Scheduler executions and grants BADGE_SCHEDULER once all
# three have fired. Scheduling gas is paid from the quest contract's own RitualWallet balance
# (see `depositForFees`, owner-only) — the caller does not need their own deposit for this quest.
#
# Usage: ./scripts/complete_scheduler_quest.sh [frequency_blocks]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source .env
source scripts/common.sh

: "${SCHEDULER_QUEST_ADDRESS:?Run script/Deploy.s.sol first and set SCHEDULER_QUEST_ADDRESS in .env}"

FREQUENCY="${1:-15}" # blocks between executions

WHO=$(deployer_address)
ACTIVE=$(cast call "$SCHEDULER_QUEST_ADDRESS" "activeScheduleId(address)(uint256)" "$WHO" --rpc-url "$RITUAL_RPC_URL")
ACTIVE=${ACTIVE%% *}
if [ "$ACTIVE" != "0" ]; then
  echo "Already scheduled (callId=$ACTIVE) — waiting for it to complete instead of re-registering."
else
  echo "Registering for $((3)) heartbeats every $FREQUENCY blocks..."
  TX=$(cast send "$SCHEDULER_QUEST_ADDRESS" "startHeartbeat(uint32,uint32,uint256)" \
    "$FREQUENCY" 300000 2000000000 \
    --private-key "$PRIVATE_KEY" --rpc-url "$RITUAL_RPC_URL" --async)
  echo "tx: $TX"
  wait_for_receipt "$TX"
fi

echo "Polling heartbeatCount / badge state..."
for _ in $(seq 1 20); do
  COUNT=$(cast call "$SCHEDULER_QUEST_ADDRESS" "heartbeatCount(address)(uint256)" "$WHO" --rpc-url "$RITUAL_RPC_URL")
  BADGES=$(cast call "$RITUAL_PASSPORT_ADDRESS" "badgesOf(address)(uint8)" "$WHO" --rpc-url "$RITUAL_RPC_URL")
  echo "  heartbeatCount=$COUNT badges=$BADGES"
  if [ $(( ${BADGES%% *} & 4 )) -ne 0 ]; then
    echo "SCHEDULER badge granted."
    exit 0
  fi
  sleep 10
done
echo "Still waiting after ~200s — check RitualWallet balance on $SCHEDULER_QUEST_ADDRESS and retry." >&2
