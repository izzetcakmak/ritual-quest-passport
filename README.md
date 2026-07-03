# Ritual Quest Passport

**🌐 Live dApp: https://ritual-quest-passport.vercel.app**

🇹🇷 [Türkçe README](README.tr.md)

An on-chain quest system built around a **soulbound (non-transferable) "Ritual Passport" NFT**
on the Ritual Chain testnet (chain id **1979**). Not another generic swap/bridge demo — each of
the three quests exercises something a normal EVM chain cannot do natively:

1. 🧠 **On-chain AI inference** — a smart contract runs a real LLM (GLM-4.7, inside a TEE)
2. 🌐 **Trustless HTTP calls** — a transaction fetches live data from a real HTTPS API
3. ⏱️ **Native scheduled execution** — recurring calls run autonomously, no keeper bots

Completing each quest mints/updates a soulbound badge on the user's Passport NFT — a
verifiable, on-chain record of real testnet engagement, readable by anyone (e.g. for future
Discord role gating or contribution checks).

## Architecture

- **[`RitualPassport`](src/RitualPassport.sol)** — soulbound ERC-721. At most one token per
  address; badges are tracked as a `uint8` bitmask (`badgesOf(address)`). Only authorized
  quest contracts can call `grantBadge`. `tokenURI` returns fully on-chain base64 JSON
  (including the earned-badge list) — no external metadata server.
- **[`AIOracleQuest`](src/quests/AIOracleQuest.sol)** — asks a question through the LLM
  precompile (`0x0802`, `zai-org/GLM-4.7-FP8`). A settled, non-error response grants
  `BADGE_AI_ORACLE`.
- **[`HTTPDataQuest`](src/quests/HTTPDataQuest.sol)** — fetches external data through the
  HTTP Call precompile (`0x0801`). A 2xx response with no executor error grants
  `BADGE_HTTP_DATA`.
- **[`SchedulerHeartbeatQuest`](src/quests/SchedulerHeartbeatQuest.sol)** — registers the
  user for 3 recurring "heartbeat" calls via Ritual's native Scheduler system contract. The
  third heartbeat grants `BADGE_SCHEDULER`. Execution fees are sponsored from the quest
  contract's own RitualWallet balance (`depositForFees`, owner-only) — users don't need
  their own deposit for this quest.

The contracts only forward the precompile call and decode the response envelope; the complex
ABI encoding of LLM/HTTP requests (13–30 fields) is deliberately done off-chain (in the
frontend and in `scripts/*.sh`) — cheaper on gas and the pattern Ritual recommends.

## Deployed addresses (chain 1979)

| Contract | Address |
|---|---|
| RitualPassport | `0x36AAC257c662A35008c40EDe3A022b0b78f44f83` |
| AIOracleQuest | `0x81Dbb44d907b65967874b5ce8C66db0c109eF1E7` |
| HTTPDataQuest | `0x3a18F9282aBeC3c86DF1f1259f2989Ea33aDaBDe` |
| SchedulerHeartbeatQuest | `0xEF9D3CdA66868CEef7C0D5172AaC7ABd9323aD50` |

Explorer: `https://explorer.ritualfoundation.org/address/<address>`

All three quests have been completed end-to-end with real transactions on testnet: the
on-chain LLM produced a real answer, the HTTP call fetched the live ETH price, and the
Scheduler fired 3 autonomous heartbeats — resulting in `badgesOf(owner) == 7` (all badges).

## Getting started

```bash
forge build
forge test -vv   # 21 unit tests (precompiles mocked with vm.mockCall)
```

> **Note:** OpenZeppelin v5.0.2 is used (v5.1+ `Bytes.sol` helpers require the Cancun-only
> `mcopy` opcode). Ritual's reference `foundry.toml` targets `evm_version = "shanghai"`, so an
> older OZ release keeps compatibility.

## Deploy your own

```bash
cp .env.example .env
# Fill in PRIVATE_KEY (deployer/owner EOA). NEVER commit the real value.

source .env
forge script script/Deploy.s.sol:DeployScript --rpc-url "$RITUAL_RPC_URL" --broadcast -vvv
# Paste the 4 printed addresses back into .env
```

The deploy script wires up quest authorization on the Passport automatically.

## Frontend (public quest UI)

`frontend/` contains a Next.js 14 + wagmi v2 + viem app: connect wallet → 3 quest buttons →
live badge showcase. The UX:

1. **Connect Wallet** (MetaMask or any injected wallet) — offers to add/switch to the Ritual
   network (1979) automatically.
2. Each quest is one button: the app discovers a TEE executor from `TEEServiceRegistry`,
   auto-deposits the `RitualWallet` fee escrow when needed (0.05 RITUAL for HTTP, 0.5 for
   LLM — checking both balance *and* lock expiry), ABI-encodes the precompile request,
   submits the transaction, and confirms the badge bit actually landed on-chain before
   declaring success.
3. Badges display live as glowing medals; completing all three unlocks a **Share on X** button.

```bash
cd frontend
npm install
npm run dev     # http://localhost:3000
npm run build   # production build (deployable to Vercel)
```

Deployed contract addresses ship as defaults in `frontend/lib/addresses.ts` and can be
overridden with `NEXT_PUBLIC_*_ADDRESS` env vars after a redeploy.

## CLI scripts

Each quest can also be completed from the command line with plain `cast` (no Node.js):

```bash
./scripts/complete_http_quest.sh                 # default: CoinGecko ETH price
./scripts/complete_ai_quest.sh "your question"
./scripts/complete_scheduler_quest.sh            # default frequency: 15 blocks
```

Each script discovers an executor, tops up the RitualWallet deposit (balance + lock check),
encodes the request, submits, and prints the resulting badge state. Re-running with the same
wallet is safe (badges are idempotent).

## Fee / deposit notes (observed on testnet)

- HTTP call: ~0.01 RITUAL deposit is plenty; actual cost is far lower.
- LLM call (`GLM-4.7-FP8`): worst-case escrow is ~0.31 RITUAL per in-flight call; a 0.5
  RITUAL deposit is safe. `maxCompletionTokens >= 4096` is required (reasoning model), and
  `ttl >= 300` blocks.
- Scheduler: 3 heartbeats × (gasLimit × maxFeePerGas) — a few 0.001 RITUAL; 0.1 RITUAL in
  the quest contract covers dozens of users.
- **RitualWallet locks expire fast**: async calls require the deposit to be *locked* through
  `commit_block + ttl`, and blocks are ~200ms — a 100k-block lock lasts only ~6 hours. The
  frontend and scripts check `lockUntil` and re-extend automatically (2M blocks ≈ 4–5 days).
  The Scheduler quest contract's sponsor deposit must be re-extended by the owner
  periodically via `depositForFees`.

## Deliberately out of scope

- **Discord bot** — intentionally not included. `RitualPassport.badgesOf(address)` is public
  and view, so any bot (or a collab.land-style service) can verify a user's signed wallet
  address against it and assign roles — no new design needed.
- Contract source verification on the explorer currently fails with a 403 from Ritual's
  custom verifier endpoint; the contracts work fine but don't show as "Verified" yet.
