#!/usr/bin/env bash
# Shared helpers for the quest scripts. Source this file after `source .env`.
set -euo pipefail

: "${RITUAL_RPC_URL:?Set RITUAL_RPC_URL (see .env)}"
: "${PRIVATE_KEY:?Set PRIVATE_KEY (see .env)}"

RITUAL_WALLET_ADDR="0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948"
TEE_SERVICE_REGISTRY_ADDR="0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F"

# Capability ids (TEEServiceRegistry)
CAPABILITY_HTTP_CALL=0
CAPABILITY_LLM=1

deployer_address() {
  cast wallet address --private-key "$PRIVATE_KEY"
}

# find_executor <capability_id> -> prints the first valid teeAddress for that capability
find_executor() {
  local capability="$1"
  cast call "$TEE_SERVICE_REGISTRY_ADDR" \
    "getServicesByCapability(uint8,bool)(((address,address,uint8,bytes,string,bytes32,uint8),bool,bytes32)[])" \
    "$capability" true --rpc-url "$RITUAL_RPC_URL" \
    | grep -oE '0x[0-9a-fA-F]{40}' | sed -n '2p'
  # 2nd address in the encoded tuple list is the first entry's teeAddress
  # (1st address is paymentAddress).
}

# ensure_wallet_balance <min_wei> <deposit_wei> <lock_blocks> -> tops up RitualWallet if the
# balance is below min OR the lock no longer covers a comfortable async window. Async
# commitments require lockUntil >= commit_block + ttl; blocks are ~200ms so locks expire fast.
ensure_wallet_balance() {
  local min_wei="$1" deposit_wei="$2" lock_blocks="$3"
  local who; who=$(deployer_address)
  local bal lock now
  bal=$(cast call "$RITUAL_WALLET_ADDR" "balanceOf(address)(uint256)" "$who" --rpc-url "$RITUAL_RPC_URL"); bal=${bal%% *}
  lock=$(cast call "$RITUAL_WALLET_ADDR" "lockUntil(address)(uint256)" "$who" --rpc-url "$RITUAL_RPC_URL"); lock=${lock%% *}
  now=$(cast block-number --rpc-url "$RITUAL_RPC_URL")
  if [ "$bal" -lt "$min_wei" ] || [ "$lock" -lt $((now + 50000)) ]; then
    local value="$deposit_wei"
    [ "$bal" -ge "$min_wei" ] && value=2000000000000000 # 0.002 RITUAL just to extend the lock
    echo "RitualWallet top-up needed (balance=$bal lockUntil=$lock now=$now) — depositing $value wei, lock $lock_blocks blocks..."
    cast send "$RITUAL_WALLET_ADDR" "deposit(uint256)" "$lock_blocks" \
      --value "$value" --private-key "$PRIVATE_KEY" --rpc-url "$RITUAL_RPC_URL"
  fi
}

# wait_for_receipt <tx_hash> [max_attempts] [sleep_secs] -> polls cast receipt (async) until mined
wait_for_receipt() {
  local tx="$1" attempts="${2:-30}" sleep_s="${3:-5}"
  for _ in $(seq 1 "$attempts"); do
    if cast receipt "$tx" --rpc-url "$RITUAL_RPC_URL" --async 2>/dev/null | grep -q "^status"; then
      cast receipt "$tx" --rpc-url "$RITUAL_RPC_URL" --async
      return 0
    fi
    sleep "$sleep_s"
  done
  echo "Timed out waiting for receipt of $tx" >&2
  return 1
}
