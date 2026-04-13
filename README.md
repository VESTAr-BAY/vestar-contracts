# VESTAr Contracts

Smart-contract stack for organizer gating, clone-based election deployment, open/private voting, and settlement on Status Network Testnet.

## English

### Overview

This repository contains the current VESTAr on-chain runtime used by the frontend and backend.

- `VESTArOrganizerRegistry` stores organizer profile data and verification state.
- `VESTArKarmaRegistry` reads Status `Karma` and `KarmaTiers` and translates eligibility.
- `VESTArElectionFactory` validates organizer eligibility and deploys election clones.
- `VESTArElection` is the per-election runtime assembled from lifecycle, eligibility, open vote, private vote, and settlement modules.
- `MockUSDT` is the 6-decimal ERC20 used for paid-vote flows on testnet.

### Contract Topology

```mermaid
flowchart LR
  Admin[Platform admin]
  Organizer[Organizer wallet]
  Voter[Voter wallet]
  Status[Status Karma + KarmaTiers]
  OrgReg[VESTArOrganizerRegistry]
  KarmaReg[VESTArKarmaRegistry]
  Factory[VESTArElectionFactory]
  Impl[VESTArElection implementation]
  MockUSDT[MockUSDT]
  Worker[Backend workers / indexer]

  subgraph Election[VESTArElection clone]
    Life[Lifecycle]
    Elig[Eligibility]
    Open[Open vote]
    Private[Private vote]
    Settle[Settlement]
  end

  Admin --> OrgReg
  Admin --> KarmaReg
  Admin --> Factory
  Organizer --> OrgReg
  Organizer --> Factory
  Status --> KarmaReg
  OrgReg --> Factory
  KarmaReg --> Factory
  Factory -->|clone from| Impl
  Factory -->|initialize| Election
  Voter --> Election
  MockUSDT --> Election
  Worker --> Election
```

### Runtime Modules

| Module | Responsibility |
| --- | --- |
| `Lifecycle` | State calculation, `syncState`, cancel, close, key reveal, finalize |
| `Eligibility` | Karma checks, ballot-period rules, remaining ballot calculation |
| `Open vote` | Plaintext candidate submission, duplicate detection, candidate allowlist, live on-chain tallies |
| `Private vote` | Ciphertext submission, public key getters, commitment-based reveal path |
| `Settlement` | ERC20 collection, 50:50 revenue split, refunds |
| `Factory` | Organizer eligibility checks, clone deployment, canonical `ElectionCreated` event |

### Sequence: Organizer Eligibility And Election Creation

```mermaid
sequenceDiagram
  actor Organizer
  participant OrgReg as OrganizerRegistry
  participant KarmaReg as KarmaRegistry
  participant Factory as ElectionFactory
  participant Impl as ElectionImplementation
  participant Election as VESTArElection clone

  Organizer->>OrgReg: upsertOrganizerProfile(...)
  Organizer->>Factory: createElection(config, initialCandidateHashes)
  Factory->>OrgReg: isVerified(...) / canCreateElection(...)
  Factory->>KarmaReg: tierIdOf(...)
  Factory->>Impl: clone()
  Factory->>Election: initialize(electionId, config, hashes, organizer, ...)
  Election-->>Factory: initialized runtime instance
  Factory-->>Organizer: tx receipt
  Factory-->>Organizer: ElectionCreated(seriesId, electionId, electionAddress, ...)
```

### Sequence: Ballot Submission

```mermaid
sequenceDiagram
  actor Voter
  participant Token as MockUSDT / ERC20
  participant Election as VESTArElection

  alt OPEN election
    Voter->>Election: submitOpenVote(candidateKeys)
    Election->>Election: syncState + canSubmitBallot + allowlist checks
    opt paid ballot
      Election->>Token: transferFrom(voter, election, costPerBallot)
    end
    Election->>Election: increment candidate tallies
    Election-->>Voter: OpenVoteSubmitted(...)
  else PRIVATE election
    Voter->>Election: submitEncryptedVote(encryptedBallot)
    Election->>Election: syncState + canSubmitBallot + ciphertext presence check
    opt paid ballot
      Election->>Token: transferFrom(voter, election, costPerBallot)
    end
    Election-->>Voter: EncryptedVoteSubmitted(...)
  end
```

### Sequence: Lifecycle, Reveal, Finalize, Settlement

```mermaid
sequenceDiagram
  participant Worker as backend workers
  actor Admin as platform admin / organizer
  participant Election as VESTArElection
  participant Token as ERC20 treasury flow

  Worker->>Election: syncState()
  Election-->>Worker: Scheduled / Active / Closed / KeyRevealPending / KeyRevealed / Finalized

  alt PRIVATE election after resultRevealAt
    Worker->>Election: revealPrivateKey(privateKeyData)
    Election-->>Worker: PrivateKeyRevealed + state=KeyRevealed
  end

  Admin->>Election: finalizeResults(resultSummary)
  Election-->>Admin: ResultFinalized(...)

  opt paid election and no refunds
    Admin->>Election: settleRevenue()
    Election->>Token: transfer 50% to platform treasury
    Election->>Token: transfer 50% remainder to organizer
    Election-->>Admin: RevenueSettled(...)
  end
```

### On-Chain Rules Checked In Code

- `seriesId` must be non-zero and the initial candidate hash list must be non-empty.
- `startAt < endAt` and `resultRevealAt >= endAt` are enforced in config validation.
- `FREE` elections must use zero cost. `PAID` elections must set a token address and positive price.
- `PRIVATE` elections must set a public key, a private-key commitment hash, and `keySchemeVersion == 1`.
- `ONE_PER_INTERVAL` requires a positive `resetInterval`.
- `UNLIMITED_PAID` is single-choice only and currently hard-checks `costPerBallot == 66_000`.
- Verified organizers can create elections with karma tier `0`. Unverified organizers need tier `>= 1`.
- Open ballots reject duplicate candidate selections on-chain.
- `revealPrivateKey(bytes)` is restricted to the platform admin or delegated reveal managers.
- `finalizeResults(...)` requires `Closed` for `OPEN` elections and `KeyRevealed` for `PRIVATE` elections.
- Revenue splits 50:50, with odd remainder flowing to the organizer.

### Repository Map

```text
contracts/
├─ abi/
│  ├─ VESTArElection.json
│  ├─ VESTArElectionFactory.json
│  ├─ VESTArOrganizerRegistry.json
│  ├─ VESTArKarmaRegistry.json
│  ├─ MockUSDT.json
│  └─ status-testnet.addresses.json
├─ script/
│  ├─ DeployMockUSDT.s.sol
│  ├─ DeployVESTArFactoryOnly.s.sol
│  ├─ DeployVESTArStack.s.sol
│  └─ SyncStatusArtifacts.sh
├─ src/
│  ├─ access/
│  ├─ config/
│  ├─ interfaces/vestar/
│  ├─ libraries/vestar/VESTArTypes.sol
│  ├─ mocks/MockUSDT.sol
│  └─ vestar/
│     ├─ registry/
│     ├─ factory/
│     └─ election/
└─ test/
```

### Status Testnet Deployment

| Item | Value |
| --- | --- |
| Network | `Status Network Testnet` |
| Chain ID | `1660990954` |
| RPC | `https://public.sepolia.rpc.status.network` |
| EVM | `paris` |
| OrganizerRegistry | `0x31891950a0B5b289fFdA7478DeaE3CED0FB4c4D5` |
| KarmaRegistry | `0x09F78697C55C318eABb532f65c03b5E4a5222429` |
| ElectionImplementation | `0x2604Fe2ae34D4292FE50418303C18aA5bD32Ba83` |
| VESTArElectionFactory | `0x4173b26b14748fe6342b2c444334095ecB7f0854` |
| MockUSDT | `0x0cf5032E38C729744953dC44EB0F0e3cC6F21855` |

### Development

Build:

```bash
forge build
```

Test:

```bash
forge test
```

Deploy the full stack:

```bash
forge script script/DeployVESTArStack.s.sol:DeployVESTArStackScript \
  --rpc-url status_testnet \
  --broadcast \
  --gas-price 0 \
  --priority-gas-price 0
```

Deploy `MockUSDT` only:

```bash
forge script script/DeployMockUSDT.s.sol:DeployMockUSDTScript \
  --rpc-url status_testnet \
  --broadcast \
  --gas-price 0 \
  --priority-gas-price 0
```

Refresh ABI handoff artifacts:

```bash
./script/SyncStatusArtifacts.sh
```

## 한국어

### 개요

이 저장소는 현재 VESTAr 프론트엔드와 백엔드가 사용하는 온체인 런타임을 담는다.

- `VESTArOrganizerRegistry`는 organizer profile과 verification 상태를 저장한다.
- `VESTArKarmaRegistry`는 Status `Karma`, `KarmaTiers`를 읽어 자격 판정을 해석한다.
- `VESTArElectionFactory`는 organizer 생성 자격을 검증하고 election clone을 배포한다.
- `VESTArElection`은 lifecycle, eligibility, open vote, private vote, settlement 모듈을 조합한 개별 election 런타임이다.
- `MockUSDT`는 테스트넷 유료 투표 플로우에 쓰는 6-decimal ERC20이다.

### 컨트랙트 토폴로지

```mermaid
flowchart LR
  Admin[플랫폼 관리자]
  Organizer[주최자 지갑]
  Voter[유권자 지갑]
  Status[Status Karma + KarmaTiers]
  OrgReg[VESTArOrganizerRegistry]
  KarmaReg[VESTArKarmaRegistry]
  Factory[VESTArElectionFactory]
  Impl[VESTArElection implementation]
  MockUSDT[MockUSDT]
  Worker[backend worker / indexer]

  subgraph Election[VESTArElection clone]
    Life[Lifecycle]
    Elig[Eligibility]
    Open[Open vote]
    Private[Private vote]
    Settle[Settlement]
  end

  Admin --> OrgReg
  Admin --> KarmaReg
  Admin --> Factory
  Organizer --> OrgReg
  Organizer --> Factory
  Status --> KarmaReg
  OrgReg --> Factory
  KarmaReg --> Factory
  Factory -->|clone from| Impl
  Factory -->|initialize| Election
  Voter --> Election
  MockUSDT --> Election
  Worker --> Election
```

### 런타임 모듈

| 모듈 | 책임 |
| --- | --- |
| `Lifecycle` | 상태 계산, `syncState`, cancel, close, key reveal, finalize |
| `Eligibility` | karma 검사, ballot period 규칙, 남은 ballot 계산 |
| `Open vote` | 평문 후보 제출, 중복 선택 차단, 후보 allowlist, 온체인 실시간 tally |
| `Private vote` | 암호문 제출, 공개키 getter, commitment 기반 reveal 경로 |
| `Settlement` | ERC20 수납, 50:50 정산, refund |
| `Factory` | organizer 자격 검증, clone 배포, 정식 `ElectionCreated` 이벤트 발행 |

### 시퀀스: organizer 자격 검증과 election 생성

```mermaid
sequenceDiagram
  actor Organizer as 주최자
  participant OrgReg as OrganizerRegistry
  participant KarmaReg as KarmaRegistry
  participant Factory as ElectionFactory
  participant Impl as ElectionImplementation
  participant Election as VESTArElection clone

  Organizer->>OrgReg: upsertOrganizerProfile(...)
  Organizer->>Factory: createElection(config, initialCandidateHashes)
  Factory->>OrgReg: isVerified(...) / canCreateElection(...)
  Factory->>KarmaReg: tierIdOf(...)
  Factory->>Impl: clone()
  Factory->>Election: initialize(electionId, config, hashes, organizer, ...)
  Election-->>Factory: runtime instance 초기화
  Factory-->>Organizer: tx receipt
  Factory-->>Organizer: ElectionCreated(seriesId, electionId, electionAddress, ...)
```

### 시퀀스: ballot 제출

```mermaid
sequenceDiagram
  actor Voter as 유권자
  participant Token as MockUSDT / ERC20
  participant Election as VESTArElection

  alt OPEN election
    Voter->>Election: submitOpenVote(candidateKeys)
    Election->>Election: syncState + canSubmitBallot + allowlist 검사
    opt paid ballot
      Election->>Token: transferFrom(voter, election, costPerBallot)
    end
    Election->>Election: 후보 tally 증가
    Election-->>Voter: OpenVoteSubmitted(...)
  else PRIVATE election
    Voter->>Election: submitEncryptedVote(encryptedBallot)
    Election->>Election: syncState + canSubmitBallot + 암호문 존재 여부 검사
    opt paid ballot
      Election->>Token: transferFrom(voter, election, costPerBallot)
    end
    Election-->>Voter: EncryptedVoteSubmitted(...)
  end
```

### 시퀀스: lifecycle, reveal, finalize, settlement

```mermaid
sequenceDiagram
  participant Worker as backend worker
  actor Admin as 플랫폼 관리자 / organizer
  participant Election as VESTArElection
  participant Token as ERC20 treasury flow

  Worker->>Election: syncState()
  Election-->>Worker: Scheduled / Active / Closed / KeyRevealPending / KeyRevealed / Finalized

  alt PRIVATE election and resultRevealAt 경과 후
    Worker->>Election: revealPrivateKey(privateKeyData)
    Election-->>Worker: PrivateKeyRevealed + state=KeyRevealed
  end

  Admin->>Election: finalizeResults(resultSummary)
  Election-->>Admin: ResultFinalized(...)

  opt paid election and refund 비활성 상태
    Admin->>Election: settleRevenue()
    Election->>Token: platform treasury로 50% 전송
    Election->>Token: organizer로 잔여 50% 전송
    Election-->>Admin: RevenueSettled(...)
  end
```

### 코드상 강제 규칙

- `seriesId`는 0일 수 없다. 초기 candidate hash 목록은 비어 있을 수 없다.
- config 검증에서 `startAt < endAt`, `resultRevealAt >= endAt`를 강제한다.
- `FREE` election은 비용이 0이어야 한다. `PAID` election은 토큰 주소와 양수 가격이 필요하다.
- `PRIVATE` election은 공개키, private-key commitment hash, `keySchemeVersion == 1`을 반드시 설정해야 한다.
- `ONE_PER_INTERVAL`은 양수 `resetInterval`이 필요하다.
- `UNLIMITED_PAID`는 단일 선택만 허용하고 현재 `costPerBallot == 66_000`을 강제한다.
- verified organizer는 karma tier `0`이어도 생성 가능하다. unverified organizer는 tier `1` 이상이 필요하다.
- open ballot은 온체인에서 중복 후보 선택을 거절한다.
- `revealPrivateKey(bytes)`는 플랫폼 관리자 또는 위임된 reveal manager만 호출 가능하다.
- `finalizeResults(...)`는 `OPEN` election에서 `Closed`, `PRIVATE` election에서 `KeyRevealed` 상태를 요구한다.
- 수익은 50:50으로 분배하며, 홀수 잔차는 organizer에게 귀속한다.

### 저장소 맵

```text
contracts/
├─ abi/
│  ├─ VESTArElection.json
│  ├─ VESTArElectionFactory.json
│  ├─ VESTArOrganizerRegistry.json
│  ├─ VESTArKarmaRegistry.json
│  ├─ MockUSDT.json
│  └─ status-testnet.addresses.json
├─ script/
│  ├─ DeployMockUSDT.s.sol
│  ├─ DeployVESTArFactoryOnly.s.sol
│  ├─ DeployVESTArStack.s.sol
│  └─ SyncStatusArtifacts.sh
├─ src/
│  ├─ access/
│  ├─ config/
│  ├─ interfaces/vestar/
│  ├─ libraries/vestar/VESTArTypes.sol
│  ├─ mocks/MockUSDT.sol
│  └─ vestar/
│     ├─ registry/
│     ├─ factory/
│     └─ election/
└─ test/
```

### Status Testnet 배포 정보

| 항목 | 값 |
| --- | --- |
| 네트워크 | `Status Network Testnet` |
| 체인 ID | `1660990954` |
| RPC | `https://public.sepolia.rpc.status.network` |
| EVM | `paris` |
| OrganizerRegistry | `0x31891950a0B5b289fFdA7478DeaE3CED0FB4c4D5` |
| KarmaRegistry | `0x09F78697C55C318eABb532f65c03b5E4a5222429` |
| ElectionImplementation | `0x2604Fe2ae34D4292FE50418303C18aA5bD32Ba83` |
| VESTArElectionFactory | `0x4173b26b14748fe6342b2c444334095ecB7f0854` |
| MockUSDT | `0x0cf5032E38C729744953dC44EB0F0e3cC6F21855` |

### 개발

빌드:

```bash
forge build
```

테스트:

```bash
forge test
```

전체 스택 배포:

```bash
forge script script/DeployVESTArStack.s.sol:DeployVESTArStackScript \
  --rpc-url status_testnet \
  --broadcast \
  --gas-price 0 \
  --priority-gas-price 0
```

`MockUSDT`만 배포:

```bash
forge script script/DeployMockUSDT.s.sol:DeployMockUSDTScript \
  --rpc-url status_testnet \
  --broadcast \
  --gas-price 0 \
  --priority-gas-price 0
```

ABI handoff 산출물 갱신:

```bash
./script/SyncStatusArtifacts.sh
```
