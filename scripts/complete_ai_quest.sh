#!/usr/bin/env bash
# Completes Quest #1 (AIOracleQuest) on Ritual testnet: asks Ritual's on-chain LLM (precompile
# 0x0802, model zai-org/GLM-4.7-FP8) a one-shot question and grants BADGE_AI_ORACLE on a
# non-error settled response. Uses an empty (stateless) convoHistory StorageRef — no DA/GCS
# credentials required.
#
# Usage: ./scripts/complete_ai_quest.sh ["your question"]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source .env
source scripts/common.sh

: "${AI_ORACLE_QUEST_ADDRESS:?Run script/Deploy.s.sol first and set AI_ORACLE_QUEST_ADDRESS in .env}"

PROMPT="${1:-In one short sentence, what makes Ritual Chain different from a normal EVM chain?}"

echo "Finding an LLM executor..."
EXECUTOR=$(find_executor "$CAPABILITY_LLM")
echo "Executor: $EXECUTOR"

ensure_wallet_balance 400000000000000000 500000000000000000 2000000 # 0.4 min, deposit 0.5 RITUAL
# GLM-4.7-FP8 worst-case escrow is ~0.31 RITUAL per in-flight call (see ritual-dapp-llm skill).

MESSAGES=$(printf '[{"role":"user","content":"%s"}]' "$PROMPT")

LLM_INPUT=$(cast abi-encode \
  "f(address,bytes[],uint256,bytes[],bytes,string,string,int256,string,bool,int256,string,string,uint256,bool,int256,string,bytes,int256,string,string,bool,int256,bytes,bytes,int256,int256,string,bool,(string,string,string))" \
  "$EXECUTOR" "[]" 300 "[]" "0x" \
  "$MESSAGES" "zai-org/GLM-4.7-FP8" \
  0 "" false 4096 "" "" 1 true 0 "medium" "0x" -1 "auto" "" false 700 "0x" "0x" -1 1000 "" false \
  '("","","")')

echo "Submitting askOracle(bytes) — LLM inference can take up to ~60s to settle..."
TX=$(cast send "$AI_ORACLE_QUEST_ADDRESS" "askOracle(bytes)" "$LLM_INPUT" \
  --private-key "$PRIVATE_KEY" --rpc-url "$RITUAL_RPC_URL" --gas-limit 5000000 --async)
echo "tx: $TX"
wait_for_receipt "$TX" 40 5

WHO=$(deployer_address)
echo "badgesOf($WHO) = $(cast call "$RITUAL_PASSPORT_ADDRESS" "badgesOf(address)(uint8)" "$WHO" --rpc-url "$RITUAL_RPC_URL")"
