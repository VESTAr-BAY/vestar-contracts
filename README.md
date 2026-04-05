# VESTAr Contracts

## English

### Overview

VESTAr is a platform that provides a transparent voting system for K-pop fans.  
This repository contains the implemented MVP smart contract stack that powers the VESTAr platform on Status Network, along with tests, deployment scripts, and ABI handoff files.

The operational rule is simple:

- the backend prepares election drafts and private-election crypto material
- the organizer wallet signs `createElection(config)`
- voters submit ballots from their own wallets
- the chain remains the final source of truth

### Implemented MVP Rules

- `VisibilityMode.OPEN` and `VisibilityMode.PRIVATE`
- `PaymentMode.FREE` and `PaymentMode.PAID`
- `BallotPolicy.ONE_PER_ELECTION`, `BallotPolicy.ONE_PER_INTERVAL`, and `BallotPolicy.UNLIMITED_PAID`
- ERC20 ballot pricing through `costPerBallot`
- optional `resetInterval` windows when `BallotPolicy.ONE_PER_INTERVAL` is selected
- one successful transaction = one ballot
- multi-choice ballots still cost one ballot, not one vote per candidate
- open ballots reject duplicate candidate selections on-chain
- private ballots are encrypted on the client and validated after reveal
- `ONE_PER_ELECTION` means one ballot for the entire election
- `UNLIMITED_PAID` means unlimited paid single-choice voting mode
- revenue settlement is 50:50 between platform treasury and organizer
- odd remainder goes to the organizer
- verified organizers can create elections with karma `0`
- unverified organizers require karma tier `>= 1`
- candidate groups are supported as on-chain metadata and bindings

### Contract Architecture

- `OrganizerRegistry`
  organizer profile, verification state, and election creation eligibility
- `KarmaRegistry`
  adapter for Status `Karma` and `KarmaTiers`
- `ElectionFactory`
  validates organizer eligibility, clones election instances, records canonical election addresses
- `ElectionImplementation`
  template contract used by the factory for clone deployment
- `VESTArElection`
  the actual per-election runtime contract users interact with
- `MockUSDT`
  6-decimal ERC20 used for local/testnet paid-vote flows

### Main On-Chain Features

- election lifecycle:
  `Scheduled -> Active -> Closed -> KeyRevealPending -> KeyRevealed -> Finalized`
- open voting:
  plaintext candidate selection with on-chain validation and live tallies
- private voting:
  encrypted ballot submission, commitment-based private key reveal, post-reveal verification
- settlement:
  ERC20 collection during voting and final split after result finalization
- group metadata:
  organizer-defined groups plus candidate-to-group bindings before the election starts

### Repository Layout

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
│  ├─ interfaces/vestar/
│  ├─ libraries/vestar/VESTArTypes.sol
│  ├─ mocks/MockUSDT.sol
│  └─ vestar/
│     ├─ election/VESTArElection.sol
│     ├─ factory/VESTArElectionFactory.sol
│     └─ registry/
└─ test/vestar/
```

### Status Network Target

Current target network:

- Network: `Status Network Testnet`
- Chain ID: `1660990954`
- RPC: `https://public.sepolia.rpc.status.network`
- EVM version: `paris`

Status integration addresses:

- Karma: `0x7ec5Dc75D09fAbcD55e76077AFa5d4b77D112fde`
- KarmaTiers: `0xc7fCD786a161f42bDaF66E18a67C767C23cFd30C`

### Current Testnet Deployment

Current deployed addresses are maintained in:

- `abi/status-testnet.addresses.json`

### ABI Handoff

Use the `abi/` folder when handing contracts to frontend or backend teams.

- contract ABIs are exported as plain JSON arrays
- deployed Status testnet addresses are included in `abi/status-testnet.addresses.json`
- `abi/README.md` explains which ABI goes to which client use case
- `script/SyncStatusArtifacts.sh` refreshes the ABI bundle and address manifest from the latest deployment

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

Deploy MockUSDT only:

```bash
forge script script/DeployMockUSDT.s.sol:DeployMockUSDTScript \
  --rpc-url status_testnet \
  --broadcast \
  --gas-price 0 \
  --priority-gas-price 0
```

### Notes

- payment uses ERC20, not native ETH
- the factory deploys clone instances; users should not interact with the implementation address directly
- private key reveal is limited to platform admin or delegated reveal managers
- candidate groups are metadata and binding helpers, not a separate tally engine

## 한국어

### 개요

VESTAr는 K-pop 팬을 위한 투명한 투표 시스템을 제공하는 플랫폼입니다.  
이 저장소에는 Status Network 위에서 VESTAr 플랫폼을 구동하는 MVP 기준의 실제 스마트 컨트랙트 스택과 테스트, 배포 스크립트, ABI 전달 파일이 들어 있습니다.

운영 흐름은 단순합니다.

- 백엔드가 election draft와 private election용 암호화 재료를 준비합니다
- organizer 지갑이 `createElection(config)`를 서명합니다
- 유저는 자기 지갑으로 ballot을 제출합니다
- 최종 권위는 항상 체인입니다

### 구현된 MVP 정책

- `VisibilityMode.OPEN`, `VisibilityMode.PRIVATE`
- `PaymentMode.FREE`, `PaymentMode.PAID`
- `BallotPolicy.ONE_PER_ELECTION`, `BallotPolicy.ONE_PER_INTERVAL`, `BallotPolicy.UNLIMITED_PAID`
- `costPerBallot` 기반 ERC20 결제
- `BallotPolicy.ONE_PER_INTERVAL`일 때만 `resetInterval` 기반 ballot 단위 기간 사용
- 성공한 트랜잭션 1회 = ballot 1개
- 다중 선택이어도 비용은 후보 수가 아니라 ballot 1개 기준
- Open ballot은 중복 후보를 온체인에서 즉시 거절
- Private ballot은 클라이언트에서 암호화하고 reveal 후 검증
- `ONE_PER_ELECTION`은 선거 전체에서 1 ballot만 허용하는 모드
- `UNLIMITED_PAID`는 무제한 유료 단일선택 모드
- 수익 정산은 platform treasury와 organizer 50:50
- 홀수 잔차는 organizer 귀속
- verified organizer는 karma `0`이어도 생성 가능
- unverified organizer는 karma tier `1` 이상 필요
- 후보 그룹은 온체인 메타데이터와 binding 형태로 지원

### 컨트랙트 구조

- `OrganizerRegistry`
  주최자 프로필, 인증 상태, 생성 가능 여부 관리
- `KarmaRegistry`
  Status `Karma`, `KarmaTiers`를 VESTAr 규칙으로 읽는 어댑터
- `ElectionFactory`
  organizer 자격을 검증하고 election clone을 만들며 정식 주소를 기록
- `ElectionImplementation`
  factory가 clone 배포 시 기준으로 쓰는 템플릿 계약
- `VESTArElection`
  유저와 organizer가 실제로 상호작용하는 개별 election 계약
- `MockUSDT`
  로컬/테스트넷 유료 투표 플로우용 6 decimals ERC20

### 주요 온체인 기능

- 상태 전이:
  `Scheduled -> Active -> Closed -> KeyRevealPending -> KeyRevealed -> Finalized`
- Open voting:
  평문 후보 제출, 온체인 유효성 검사, 실시간 tally
- Private voting:
  암호화 ballot 제출, commitment 기반 private key reveal, reveal 후 공개 검증
- settlement:
  투표 중 ERC20 수납, 결과 확정 후 최종 분배
- group metadata:
  organizer가 투표 시작 전에 그룹 정의와 후보-그룹 연결 설정

### 저장소 구조

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
│  ├─ interfaces/vestar/
│  ├─ libraries/vestar/VESTArTypes.sol
│  ├─ mocks/MockUSDT.sol
│  └─ vestar/
│     ├─ election/VESTArElection.sol
│     ├─ factory/VESTArElectionFactory.sol
│     └─ registry/
└─ test/vestar/
```

### Status Network 대상

현재 주요 대상 네트워크:

- 네트워크: `Status Network Testnet`
- 체인 ID: `1660990954`
- RPC: `https://public.sepolia.rpc.status.network`
- EVM version: `paris`

Status 연동 주소:

- Karma: `0x7ec5Dc75D09fAbcD55e76077AFa5d4b77D112fde`
- KarmaTiers: `0xc7fCD786a161f42bDaF66E18a67C767C23cFd30C`

### 현재 테스트넷 배포 주소

현재 배포 주소는 아래 파일을 기준으로 봅니다.

- `abi/status-testnet.addresses.json`

### ABI 전달

프론트/백에 계약을 넘길 때는 `abi/` 폴더를 사용하면 됩니다.

- ABI는 순수 JSON 배열 형태로 분리되어 있습니다
- Status testnet 배포 주소는 `abi/status-testnet.addresses.json`에 들어 있습니다
- 어떤 ABI를 어디에 붙이면 되는지는 `abi/README.md`에 정리돼 있습니다
- 최신 배포 기준 ABI/주소 갱신은 `script/SyncStatusArtifacts.sh`로 한 번에 처리할 수 있습니다

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

MockUSDT만 배포:

```bash
forge script script/DeployMockUSDT.s.sol:DeployMockUSDTScript \
  --rpc-url status_testnet \
  --broadcast \
  --gas-price 0 \
  --priority-gas-price 0
```

### 메모

- 결제는 native ETH가 아니라 ERC20 기준입니다
- factory는 clone 인스턴스를 생성하므로 implementation 주소를 직접 쓰면 안 됩니다
- private key reveal은 platform admin 또는 위임된 reveal manager만 가능합니다
- candidate group은 메타데이터/분류 기능이며 별도 tally 엔진은 아닙니다
