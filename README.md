# Ritual Quest Passport

**🌐 Canlı dApp: https://ritual-quest-passport.vercel.app**

Ritual Chain testnet (chain id **1979**) üzerinde çalışan, **soulbound (devredilemez) bir "Ritual
Passport" NFT** etrafında kurulu bir on-chain quest sistemi. Jenerik bir swap/bridge demosu değil
— Ritual'ın asıl farkını (zincir üstünde LLM inference, HTTP çağrıları ve otonom
zamanlanmış görevler) fiilen kullanan 3 görevden oluşuyor. Bu, hem Ritual'ın vizyonuna uygun
gerçek bir kullanım örneği hem de ileride Discord rolü / airdrop taraması için ölçülebilir,
on-chain doğrulanabilir bir "kanıt" katmanı.

## Mimarî

- **[`RitualPassport`](src/RitualPassport.sol)** — soulbound ERC-721. Her kullanıcıya en fazla 1
  token; rozetler `uint8` bitmask olarak (`badgesOf(address)`) tutuluyor. Sadece yetkili quest
  kontratları `grantBadge` çağırabiliyor. `tokenURI` on-chain, base64 JSON döndürüyor (rozet
  listesi dahil) — harici bir metadata sunucusu gerekmiyor.
- **[`AIOracleQuest`](src/quests/AIOracleQuest.sol)** — LLM precompile'ı (`0x0802`,
  `zai-org/GLM-4.7-FP8`) kullanarak on-chain bir soru sorar. Hatasız (settled) bir cevap
  `BADGE_AI_ORACLE` kazandırır.
- **[`HTTPDataQuest`](src/quests/HTTPDataQuest.sol)** — HTTP Call precompile'ı (`0x0801`) ile
  harici bir URL'den veri çeker. 2xx + hatasız yanıt `BADGE_HTTP_DATA` kazandırır.
- **[`SchedulerHeartbeatQuest`](src/quests/SchedulerHeartbeatQuest.sol)** — Ritual'ın Scheduler
  sistem kontratı üzerinden kullanıcıyı 3 kez tekrarlayan bir "heartbeat" çağrısına kaydeder.
  Üçüncü çağrı `BADGE_SCHEDULER` kazandırır. Zamanlama ücretleri kontratın kendi RitualWallet
  bakiyesinden karşılanır (`depositForFees`, sadece owner) — kullanıcının kendi RitualWallet
  yatırımına gerek yok.

Kontratlar sadece precompile çağrısını yapıp cevabı çözümlüyor; LLM/HTTP isteklerinin karmaşık
ABI encoding'i (13-30 alan) kasıtlı olarak zincir dışında yapılıyor (`scripts/*.sh`, bkz.
aşağı) — bu hem gas açısından daha verimli hem de Ritual'ın önerdiği pattern.

## Testnette deploy edilmiş adresler (chain 1979)

| Kontrat | Adres |
|---|---|
| RitualPassport | `0x36AAC257c662A35008c40EDe3A022b0b78f44f83` |
| AIOracleQuest | `0x81Dbb44d907b65967874b5ce8C66db0c109eF1E7` |
| HTTPDataQuest | `0x3a18F9282aBeC3c86DF1f1259f2989Ea33aDaBDe` |
| SchedulerHeartbeatQuest | `0xEF9D3CdA66868CEef7C0D5172AaC7ABd9323aD50` |

Explorer: `https://explorer.ritualfoundation.org/address/<adres>`

Owner cüzdanı bu üç görevi de testnette gerçek işlemlerle tamamladı — tek bir işlemde LLM modeli
gerçek bir cevap üretti, HTTP çağrısı ETH fiyatını çekti ve Scheduler 3 kez heartbeat tetikledi.
Sonuç: `badgesOf(owner) == 7` (tüm rozetler, `AI Oracle, HTTP Data, Scheduler`).

## Kurulum

```bash
forge install   # zaten yapıldıysa gerekmez (lib/ altında forge-std + openzeppelin-contracts v5.0.2)
forge build
forge test -vv  # 21 unit test (vm.mockCall ile precompile mock'lanıyor)
```

> **Not:** OpenZeppelin v5.0.2 kullanılıyor (v5.1+'daki `Bytes.sol` yardımcıları `mcopy` opcode'una
> ihtiyaç duyuyor — Cancun-only). Ritual dokümantasyonundaki örnek `foundry.toml`
> `evm_version = "shanghai"` önerdiği için daha eski bir OZ sürümüyle uyumluluk tercih edildi.

## Deploy

```bash
cp .env.example .env
# .env içine PRIVATE_KEY'ini gir (deployer/owner EOA). ASLA commit etme.

source .env
forge script script/Deploy.s.sol:DeployScript --rpc-url "$RITUAL_RPC_URL" --broadcast -vvv
# Çıktıdaki 4 adresi .env'e (RITUAL_PASSPORT_ADDRESS, AI_ORACLE_QUEST_ADDRESS, ...) yapıştır.
```

Deploy script otomatik olarak 3 quest kontratını `RitualPassport.setQuestAuthorized` ile
yetkilendiriyor.

## Görevleri testnette çalıştırma

Her görev için hazır bir bash scripti var (sadece `cast` kullanıyor, Node.js gerekmiyor):

```bash
./scripts/complete_http_quest.sh                       # varsayılan URL: CoinGecko ETH fiyatı
./scripts/complete_http_quest.sh "https://api.example.com/..."

./scripts/complete_ai_quest.sh                          # varsayılan soru
./scripts/complete_ai_quest.sh "Ritual Chain'de agent nasıl çalışır?"

./scripts/complete_scheduler_quest.sh                   # varsayılan frequency: 15 blok
./scripts/complete_scheduler_quest.sh 20
```

Her script kendi başına: gerekli executor'ı `TEEServiceRegistry`'den bulur, `RitualWallet`
bakiyesini gerekirse doldurur (deposit), isteği ABI-encode eder, işlemi gönderir ve rozet
durumunu (`badgesOf`) yazdırır. Aynı cüzdanla tekrar çalıştırmak güvenlidir (rozetler idempotent).

### Manuel adımlar (script'lerin içinde ne olduğu)

Executor bulma (HTTP_CALL=0, LLM=1):
```bash
cast call 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F \
  "getServicesByCapability(uint8,bool)(((address,address,uint8,bytes,string,bytes32,uint8),bool,bytes32)[])" \
  0 true --rpc-url "$RITUAL_RPC_URL"
```

RitualWallet'a yatırım:
```bash
cast send 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948 "deposit(uint256)" 100000 \
  --value 0.5ether --private-key "$PRIVATE_KEY" --rpc-url "$RITUAL_RPC_URL"
```

`cast send` async precompile çağrılarında receipt beklerken donabiliyor (bilinen bir davranış —
node async job'u commit+settle edene kadar receipt sorgusu uzun sürebiliyor). Bu yüzden
script'ler `--async` ile tx hash'i hemen alıp `cast receipt <hash> --async` ile ayrıca
poll ediyor.

## Gaz / deposit notları (testnette gözlemlenen)

- HTTP çağrısı: ~0.01 RITUAL depozito yeterli, gerçek maliyet çok daha düşük.
- LLM çağrısı (`GLM-4.7-FP8`): worst-case escrow ~0.31 RITUAL/eşzamanlı çağrı; 0.5 RITUAL
  depozito güvenli. `maxCompletionTokens >= 4096` şart (reasoning modeli), `ttl >= 300` blok.
- Scheduler: 3 heartbeat × (gasLimit × maxFeePerGas) — birkaç 0.001 RITUAL mertebesinde;
  `depositForFees` ile kontrata 0.05 RITUAL yatırmak fazlasıyla yeterli.
- Ölçülen ortalama blok süresi bu ağda ~200ms (dokümandaki "muhafazakâr" 350ms'den hızlı).

## Frontend (herkese açık quest arayüzü)

`frontend/` altında Next.js 14 + wagmi v2 + viem ile yazılmış, cüzdan bağla → 3 quest butonu →
rozet durumu gösteren bir arayüz var. Kullanıcı deneyimi:

1. **Connect Wallet** (MetaMask vb. injected cüzdan) — Ritual ağı (1979) cüzdanda yoksa
   otomatik ekleme/geçiş teklif edilir.
2. Her quest tek buton: arayüz executor'ı `TEEServiceRegistry`'den bulur, gerekiyorsa
   `RitualWallet` depozitosunu otomatik ister (HTTP için 0.05, LLM için 0.5 RITUAL),
   precompile isteğini ABI-encode eder, işlemi gönderir ve rozet gelene kadar bekler.
3. Rozetler `badgesOf` üzerinden canlı gösterilir; tamamlanan quest butonu "Completed ✓" olur.

```bash
cd frontend
npm install
npm run dev     # http://localhost:3000
npm run build   # prod build (Vercel'e deploy edilebilir)
```

Deploy edilmiş kontrat adresleri `frontend/lib/addresses.ts` içinde varsayılan olarak gömülü;
yeniden deploy durumunda `NEXT_PUBLIC_*_ADDRESS` env değişkenleriyle override edilebilir.

## Kapsam dışı bırakılanlar (bilinçli olarak)

- **Discord bot** kasıtlı olarak dahil edilmedi. `RitualPassport.badgesOf(address)` public ve
  view olduğu için, ileride bir bot (veya collab.land benzeri bir servis) kullanıcının imzalı
  cüzdan adresini bu fonksiyonla sorgulayıp role atayabilir — sıfırdan tasarım gerekmiyor.
- Kontrat kaynak doğrulaması (`forge verify-contract --verifier custom`) Ritual'ın custom
  verifier endpoint'inde 403 ile başarısız oldu; kontratlar çalışıyor ama explorer'da henüz
  "Verified" görünmüyor.
