#!/usr/bin/env bash
# Completes Quest #2 (HTTPDataQuest) on Ritual testnet: fetches an external URL through the
# HTTP Call precompile (0x0801) and grants BADGE_HTTP_DATA on a settled 2xx response.
#
# Usage: ./scripts/complete_http_quest.sh [url]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source .env
source scripts/common.sh

: "${HTTP_DATA_QUEST_ADDRESS:?Run script/Deploy.s.sol first and set HTTP_DATA_QUEST_ADDRESS in .env}"

URL="${1:-https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd}"

echo "Finding an HTTP_CALL executor..."
EXECUTOR=$(find_executor "$CAPABILITY_HTTP_CALL")
echo "Executor: $EXECUTOR"

ensure_wallet_balance 10000000000000000 50000000000000000 2000000 # 0.01 min, deposit 0.05 RITUAL

HTTP_INPUT=$(cast abi-encode \
  "f(address,bytes[],uint256,bytes[],bytes,string,uint8,string[],string[],bytes,uint256,uint8,bool)" \
  "$EXECUTOR" "[]" 100 "[]" "0x" \
  "$URL" 1 '["Accept"]' '["application/json"]' "0x" 0 0 false)

echo "Submitting fetchData(bytes)..."
TX=$(cast send "$HTTP_DATA_QUEST_ADDRESS" "fetchData(bytes)" "$HTTP_INPUT" \
  --private-key "$PRIVATE_KEY" --rpc-url "$RITUAL_RPC_URL" --gas-limit 2000000 --async)
echo "tx: $TX"
wait_for_receipt "$TX"

WHO=$(deployer_address)
echo "badgesOf($WHO) = $(cast call "$RITUAL_PASSPORT_ADDRESS" "badgesOf(address)(uint8)" "$WHO" --rpc-url "$RITUAL_RPC_URL")"
