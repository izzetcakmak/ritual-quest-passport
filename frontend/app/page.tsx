'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  useAccount,
  useConnect,
  useDisconnect,
  useSwitchChain,
  useWriteContract,
} from 'wagmi';
import { createPublicClient, http, parseEther } from 'viem';
import type { Address, Hex } from 'viem';
import { ritualChain, FAUCET_URL, EXPLORER_URL } from '@/lib/chain';
import {
  RITUAL_PASSPORT, AI_ORACLE_QUEST, HTTP_DATA_QUEST, SCHEDULER_QUEST,
  RITUAL_WALLET, TEE_SERVICE_REGISTRY,
  BADGE_AI_ORACLE, BADGE_HTTP_DATA, BADGE_SCHEDULER,
  CAPABILITY_HTTP_CALL, CAPABILITY_LLM,
} from '@/lib/addresses';
import {
  ritualPassportAbi, aiOracleQuestAbi, httpDataQuestAbi, schedulerQuestAbi,
  ritualWalletAbi, teeServiceRegistryAbi,
} from '@/lib/abis';
import { encodeHTTPRequest, encodeLLMRequest } from '@/lib/encode';

// All chain reads and receipt waits go through this client, pinned to the Ritual RPC —
// never through the connected wallet's provider, which may be on a different network.
const ritualClient = createPublicClient({ chain: ritualChain, transport: http() });

type QuestState =
  | { phase: 'idle' }
  | { phase: 'finding-executor' }
  | { phase: 'depositing' }
  | { phase: 'submitting' }
  | { phase: 'waiting'; txHash: Hex }
  | { phase: 'polling' }
  | { phase: 'done'; txHash?: Hex }
  | { phase: 'error'; message: string };

function shortAddr(a: string) {
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

function errMsg(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  return m.length > 220 ? m.slice(0, 220) + '…' : m;
}

export default function Home() {
  // `chainId` from useAccount is the wallet's actual network (may be any chain);
  // wagmi's useChainId only reports config chains and misses a wallet sitting elsewhere.
  const { address, isConnected, chainId: walletChainId } = useAccount();
  const { connect, connectors, isPending: connecting } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();

  const wrongChain = isConnected && walletChainId !== ritualChain.id;

  const [badgeBits, setBadgeBits] = useState(0);
  const [httpState, setHttpState] = useState<QuestState>({ phase: 'idle' });
  const [aiState, setAiState] = useState<QuestState>({ phase: 'idle' });
  const [schedState, setSchedState] = useState<QuestState>({ phase: 'idle' });
  const [prompt, setPrompt] = useState(
    'In one short sentence, what makes Ritual Chain different from a normal EVM chain?',
  );
  const [heartbeats, setHeartbeats] = useState<number | null>(null);

  // Badges are read through the same pinned ritualClient the quest flows use — one code
  // path, one source of truth. Refreshes on connect/account-switch and every 12s.
  const readBadges = useCallback(async (who: Address): Promise<number> => {
    const bits = await ritualClient.readContract({
      address: RITUAL_PASSPORT,
      abi: ritualPassportAbi,
      functionName: 'badgesOf',
      args: [who],
    });
    return Number(bits);
  }, []);

  useEffect(() => {
    // Account switched or disconnected: clear per-account UI state immediately so one
    // wallet's completed quests never show against another wallet's passport.
    setBadgeBits(0);
    setHttpState({ phase: 'idle' });
    setAiState({ phase: 'idle' });
    setSchedState({ phase: 'idle' });
    setHeartbeats(null);
    if (!address) return;

    let cancelled = false;
    const refresh = () => {
      readBadges(address)
        .then((bits) => { if (!cancelled) setBadgeBits(bits); })
        .catch(() => { /* transient RPC failure — next tick retries */ });
    };
    refresh();
    const timer = setInterval(refresh, 12_000);
    return () => { cancelled = true; clearInterval(timer); };
  }, [address, readBadges]);

  // Polls until the expected badge bit appears on-chain (settlement can lag the receipt).
  // Returns true if the badge was confirmed, false if it never showed up.
  const confirmBadge = useCallback(
    async (who: Address, badge: number, attempts = 10): Promise<boolean> => {
      for (let i = 0; i < attempts; i++) {
        const bits = await readBadges(who);
        setBadgeBits(bits);
        if ((bits & badge) !== 0) return true;
        await new Promise((r) => setTimeout(r, 3000));
      }
      return false;
    },
    [readBadges],
  );

  const findExecutor = useCallback(
    async (capability: number): Promise<Address> => {
      const services = await ritualClient.readContract({
        address: TEE_SERVICE_REGISTRY,
        abi: teeServiceRegistryAbi,
        functionName: 'getServicesByCapability',
        args: [capability, true],
      });
      const valid = services.filter((s) => s.isValid);
      if (valid.length === 0) throw new Error('No executors available for this capability right now — try again later.');
      // Pick a random valid executor to spread load.
      return valid[Math.floor(Math.random() * valid.length)].node.teeAddress;
    },
    [],
  );

  const ensureDeposit = useCallback(
    async (minWei: bigint, depositWei: bigint, setState: (s: QuestState) => void) => {
      if (!address) throw new Error('Wallet not connected');
      const [balance, lockUntil, currentBlock] = await Promise.all([
        ritualClient.readContract({
          address: RITUAL_WALLET,
          abi: ritualWalletAbi,
          functionName: 'balanceOf',
          args: [address],
        }),
        ritualClient.readContract({
          address: RITUAL_WALLET,
          abi: ritualWalletAbi,
          functionName: 'lockUntil',
          args: [address],
        }),
        ritualClient.getBlockNumber(),
      ]);
      // Async commitments require the lock to cover commit_block + ttl; blocks are ~200ms
      // here, so demand a generous remaining window and re-deposit (which extends the
      // monotonic lock) whenever balance or lock is short.
      const lockOk = lockUntil >= currentBlock + 50_000n;
      if (balance >= minWei && lockOk) return;
      setState({ phase: 'depositing' });
      const topUp = balance >= minWei ? parseEther('0.002') : depositWei;
      const hash = await writeContractAsync({
        address: RITUAL_WALLET,
        abi: ritualWalletAbi,
        functionName: 'deposit',
        args: [2_000_000n], // lock duration in blocks (~4-5 days at ~200ms blocks)
        value: topUp,
        chainId: ritualChain.id,
      });
      await ritualClient.waitForTransactionReceipt({ hash, timeout: 120_000 });
    },
    [address, writeContractAsync],
  );

  // Quest 1: HTTP data fetch
  const runHttpQuest = useCallback(async () => {
    try {
      if (!address) throw new Error('Wallet not connected');
      setHttpState({ phase: 'finding-executor' });
      const executor = await findExecutor(CAPABILITY_HTTP_CALL);
      await ensureDeposit(parseEther('0.01'), parseEther('0.05'), setHttpState);
      setHttpState({ phase: 'submitting' });
      const input = encodeHTTPRequest(
        executor,
        'https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd',
      );
      const hash = await writeContractAsync({
        address: HTTP_DATA_QUEST,
        abi: httpDataQuestAbi,
        functionName: 'fetchData',
        args: [input],
        gas: 2_000_000n,
        chainId: ritualChain.id,
      });
      setHttpState({ phase: 'waiting', txHash: hash });
      const receipt = await ritualClient.waitForTransactionReceipt({ hash, timeout: 180_000 });
      if (receipt.status !== 'success') throw new Error('Transaction reverted');
      // The tx settling doesn't guarantee the badge: the HTTP call itself may have returned
      // an error / non-2xx. Only report success once the badge bit is visible on-chain.
      if (await confirmBadge(address, BADGE_HTTP_DATA)) {
        setHttpState({ phase: 'done', txHash: hash });
      } else {
        setHttpState({
          phase: 'error',
          message: 'Transaction settled but no badge was granted — the HTTP call likely failed (non-200 or executor error). Please try again.',
        });
      }
    } catch (e) {
      setHttpState({ phase: 'error', message: errMsg(e) });
    }
  }, [address, findExecutor, ensureDeposit, writeContractAsync, confirmBadge]);

  // Quest 2: on-chain AI inference
  const runAiQuest = useCallback(async () => {
    try {
      if (!address) throw new Error('Wallet not connected');
      setAiState({ phase: 'finding-executor' });
      const executor = await findExecutor(CAPABILITY_LLM);
      // GLM-4.7-FP8 worst-case escrow is ~0.31 RITUAL per in-flight call.
      await ensureDeposit(parseEther('0.4'), parseEther('0.5'), setAiState);
      setAiState({ phase: 'submitting' });
      const input = encodeLLMRequest(executor, prompt.trim() || 'What is Ritual Chain?');
      const hash = await writeContractAsync({
        address: AI_ORACLE_QUEST,
        abi: aiOracleQuestAbi,
        functionName: 'askOracle',
        args: [input],
        gas: 5_000_000n,
        chainId: ritualChain.id,
      });
      setAiState({ phase: 'waiting', txHash: hash });
      const receipt = await ritualClient.waitForTransactionReceipt({ hash, timeout: 300_000 });
      if (receipt.status !== 'success') throw new Error('Transaction reverted');
      // A settled tx can still carry an AI error (hasError=true) — no badge in that case.
      if (await confirmBadge(address, BADGE_AI_ORACLE)) {
        setAiState({ phase: 'done', txHash: hash });
      } else {
        setAiState({
          phase: 'error',
          message: 'Transaction settled but no badge was granted — the AI call likely returned an error. Please try again.',
        });
      }
    } catch (e) {
      setAiState({ phase: 'error', message: errMsg(e) });
    }
  }, [address, findExecutor, ensureDeposit, writeContractAsync, confirmBadge, prompt]);

  // Quest 3: scheduler heartbeat
  const runSchedulerQuest = useCallback(async () => {
    try {
      if (!address) throw new Error('Wallet not connected');
      const active = await ritualClient.readContract({
        address: SCHEDULER_QUEST,
        abi: schedulerQuestAbi,
        functionName: 'activeScheduleId',
        args: [address],
      });
      if (active === 0n) {
        setSchedState({ phase: 'submitting' });
        const hash = await writeContractAsync({
          address: SCHEDULER_QUEST,
          abi: schedulerQuestAbi,
          functionName: 'startHeartbeat',
          args: [15, 300_000, 2_000_000_000n], // every 15 blocks, 300k gas, 2 gwei
          chainId: ritualChain.id,
        });
        setSchedState({ phase: 'waiting', txHash: hash });
        const receipt = await ritualClient.waitForTransactionReceipt({ hash, timeout: 120_000 });
        if (receipt.status !== 'success') throw new Error('Transaction reverted');
      }
      setSchedState({ phase: 'polling' });
      // 3 heartbeats × 15 blocks × ~0.3s ≈ 15s; poll generously.
      for (let i = 0; i < 40; i++) {
        const [count, bits] = await Promise.all([
          ritualClient.readContract({
            address: SCHEDULER_QUEST,
            abi: schedulerQuestAbi,
            functionName: 'heartbeatCount',
            args: [address],
          }),
          ritualClient.readContract({
            address: RITUAL_PASSPORT,
            abi: ritualPassportAbi,
            functionName: 'badgesOf',
            args: [address],
          }),
        ]);
        setHeartbeats(Number(count));
        setBadgeBits(Number(bits));
        if ((Number(bits) & BADGE_SCHEDULER) !== 0) {
          setSchedState({ phase: 'done' });
          return;
        }
        await new Promise((r) => setTimeout(r, 5000));
      }
      throw new Error('Timed out waiting for heartbeats — the schedule is registered, check back in a minute.');
    } catch (e) {
      setSchedState({ phase: 'error', message: errMsg(e) });
    }
  }, [address, writeContractAsync]);

  const anyBusy = useMemo(
    () =>
      [httpState, aiState, schedState].some(
        (s) => !['idle', 'done', 'error'].includes(s.phase),
      ),
    [httpState, aiState, schedState],
  );

  const earnedCount =
    (badgeBits & BADGE_AI_ORACLE ? 1 : 0) +
    (badgeBits & BADGE_HTTP_DATA ? 1 : 0) +
    (badgeBits & BADGE_SCHEDULER ? 1 : 0);

  return (
    <div className="container">
      <div className="header">
        <h1>🎖️ Ritual Quest Passport</h1>
        {isConnected ? (
          <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
            <span className="addr">{shortAddr(address!)}</span>
            <button className="btn secondary" onClick={() => disconnect()}>Disconnect</button>
          </div>
        ) : (
          <button
            className="btn"
            disabled={connecting}
            onClick={() => connect({ connector: connectors[0], chainId: ritualChain.id })}
          >
            {connecting ? 'Connecting…' : 'Connect Wallet'}
          </button>
        )}
      </div>

      <p className="subtitle">
        Complete 3 quests on the <strong>Ritual Chain testnet</strong> and earn soulbound badges on
        your on-chain Passport NFT. Each quest exercises something a normal EVM chain can&apos;t do:
        on-chain AI inference, trustless HTTP calls, and native scheduled execution.
      </p>

      {wrongChain && (
        <div className="notice">
          Wrong network.{' '}
          <button className="btn" style={{ padding: '6px 12px', fontSize: 13 }} onClick={() => switchChain({ chainId: ritualChain.id })}>
            Switch to Ritual Testnet (1979)
          </button>
        </div>
      )}

      {!isConnected && (
        <div className="notice">
          You&apos;ll need a browser wallet (e.g. MetaMask) and free testnet RITUAL from the{' '}
          <a href={FAUCET_URL} target="_blank" rel="noreferrer">Ritual faucet</a>. Connecting will
          offer to add the Ritual network automatically.
        </div>
      )}

      {/* Passport status */}
      <div className="card passport">
        <div className="passport-head">
          <h2>Your Passport</h2>
          <span className="progress-pill">
            {earnedCount} / 3 badges
          </span>
        </div>
        <p>
          A soulbound (non-transferable) NFT that records which quests you&apos;ve completed.
          Anyone can verify it on-chain — useful for future Discord roles or contribution checks.
        </p>
        <div className="medal-row">
          <BadgeMedal
            earned={!!(badgeBits & BADGE_AI_ORACLE)}
            icon="🧠"
            name="AI Oracle"
            desc="Talked to the on-chain AI"
          />
          <BadgeMedal
            earned={!!(badgeBits & BADGE_HTTP_DATA)}
            icon="🌐"
            name="HTTP Data"
            desc="Fetched real-world data"
          />
          <BadgeMedal
            earned={!!(badgeBits & BADGE_SCHEDULER)}
            icon="⏱️"
            name="Scheduler"
            desc="Ran autonomous execution"
          />
        </div>
        {badgeBits === 7 ? (
          <div className="complete-banner">
            <div className="status ok" style={{ marginTop: 0 }}>
              🏆 All three badges earned — your passport is complete!
            </div>
            <a
              className="btn"
              style={{ textDecoration: 'none' }}
              href={`https://twitter.com/intent/tweet?text=${encodeURIComponent(
                'I just earned all 3 badges on Ritual Quest Passport 🎖️ — talked to an on-chain AI, fetched real-world data trustlessly, and ran autonomous scheduled execution on @ritualnet testnet. Builder by @izzetcakmak35\n\nhttps://ritual-quest-passport.vercel.app',
              )}`}
              target="_blank"
              rel="noreferrer"
            >
              Share on X 🐦
            </a>
          </div>
        ) : (
          isConnected && earnedCount > 0 && (
            <div className="status info">Keep going — {3 - earnedCount} more badge{3 - earnedCount > 1 ? 's' : ''} to complete your passport!</div>
          )
        )}
      </div>

      {/* Quest 1: HTTP */}
      <div className="card">
        <h2>🌐 Quest 1 — Fetch Real-World Data</h2>
        <p>
          Your transaction makes a real HTTPS request (current ETH price from CoinGecko) through
          Ritual&apos;s TEE-verified HTTP precompile and settles the result on-chain. Costs ~0.01
          testnet RITUAL (auto-deposited to RitualWallet if needed).
        </p>
        <button
          className="btn"
          disabled={!isConnected || wrongChain || anyBusy || !!(badgeBits & BADGE_HTTP_DATA)}
          onClick={runHttpQuest}
        >
          {badgeBits & BADGE_HTTP_DATA ? 'Completed ✓' : 'Fetch ETH Price On-Chain'}
        </button>
        <QuestStatus state={httpState} />
      </div>

      {/* Quest 2: AI */}
      <div className="card">
        <h2>🧠 Quest 2 — Ask the On-Chain AI</h2>
        <p>
          Your transaction runs a real LLM inference (GLM-4.7, executing inside a TEE) directly
          from a smart contract. Needs ~0.5 testnet RITUAL escrow (auto-deposited; unused portion
          refunds after settlement). Settlement can take up to a minute.
        </p>
        <input
          className="input"
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          maxLength={300}
          placeholder="Ask the on-chain AI anything…"
        />
        <button
          className="btn"
          disabled={!isConnected || wrongChain || anyBusy || !!(badgeBits & BADGE_AI_ORACLE)}
          onClick={runAiQuest}
        >
          {badgeBits & BADGE_AI_ORACLE ? 'Completed ✓' : 'Ask the AI On-Chain'}
        </button>
        <QuestStatus state={aiState} />
      </div>

      {/* Quest 3: Scheduler */}
      <div className="card">
        <h2>⏱️ Quest 3 — Schedule Autonomous Execution</h2>
        <p>
          Registers you for 3 recurring &quot;heartbeat&quot; calls executed autonomously by
          Ritual&apos;s native Scheduler — no keeper bots, no cron servers. Execution fees are
          sponsored by the quest contract; you only pay gas for one registration transaction.
        </p>
        <button
          className="btn"
          disabled={!isConnected || wrongChain || anyBusy || !!(badgeBits & BADGE_SCHEDULER)}
          onClick={runSchedulerQuest}
        >
          {badgeBits & BADGE_SCHEDULER ? 'Completed ✓' : 'Start Heartbeat Schedule'}
        </button>
        {schedState.phase === 'polling' && heartbeats !== null && (
          <div className="status info">Heartbeats so far: {heartbeats} / 3…</div>
        )}
        <QuestStatus state={schedState} />
      </div>

      <div className="footer">
        <div>
          Contracts on Ritual Chain (id 1979): Passport{' '}
          <a href={`${EXPLORER_URL}/address/${RITUAL_PASSPORT}`} target="_blank" rel="noreferrer">
            {shortAddr(RITUAL_PASSPORT)}
          </a>
          {' · '}
          <a href={`${EXPLORER_URL}/address/${AI_ORACLE_QUEST}`} target="_blank" rel="noreferrer">AI Quest</a>
          {' · '}
          <a href={`${EXPLORER_URL}/address/${HTTP_DATA_QUEST}`} target="_blank" rel="noreferrer">HTTP Quest</a>
          {' · '}
          <a href={`${EXPLORER_URL}/address/${SCHEDULER_QUEST}`} target="_blank" rel="noreferrer">Scheduler Quest</a>
        </div>
        <div>
          Need testnet RITUAL? <a href={FAUCET_URL} target="_blank" rel="noreferrer">Get some from the faucet</a>.
          Testnet only — tokens have no real value.
        </div>
      </div>
    </div>
  );
}

function BadgeMedal({
  earned, icon, name, desc,
}: { earned: boolean; icon: string; name: string; desc: string }) {
  return (
    <div className={`medal ${earned ? 'earned' : ''}`}>
      <div className="medal-icon">{earned ? icon : '🔒'}</div>
      <div className="medal-name">{name}</div>
      <div className="medal-desc">{earned ? desc : 'Not earned yet'}</div>
      {earned && <div className="medal-check">✓ EARNED</div>}
    </div>
  );
}

function QuestStatus({ state }: { state: QuestState }) {
  switch (state.phase) {
    case 'idle':
      return null;
    case 'finding-executor':
      return <div className="status info">Finding a TEE executor…</div>;
    case 'depositing':
      return <div className="status info">Depositing fee escrow into RitualWallet (confirm in wallet)…</div>;
    case 'submitting':
      return <div className="status info">Submitting transaction (confirm in wallet)…</div>;
    case 'waiting':
      return (
        <div className="status info">
          Waiting for on-chain settlement… tx:{' '}
          <a href={`${EXPLORER_URL}/tx/${state.txHash}`} target="_blank" rel="noreferrer">
            {state.txHash.slice(0, 14)}…
          </a>
        </div>
      );
    case 'polling':
      return <div className="status info">Schedule registered — waiting for autonomous executions…</div>;
    case 'done':
      return (
        <div className="status ok">
          ✓ Quest completed — badge granted!{' '}
          {state.txHash && (
            <a href={`${EXPLORER_URL}/tx/${state.txHash}`} target="_blank" rel="noreferrer">View tx</a>
          )}
        </div>
      );
    case 'error':
      return <div className="status err">✗ {state.message}</div>;
  }
}
