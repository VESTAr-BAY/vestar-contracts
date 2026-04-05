# VESTAr Implementation

이 폴더는 `interfaces/vestar`를 실제로 구현한 VESTAr v1 계약 모음이다.
현재 구조는 `registry -> factory -> election instance` 흐름으로 동작하며,
election 내부는 lifecycle / eligibility / open / private / settlement 모듈로 나뉜다.

## Folder Meaning

- `registry/`
  주최자 정보와 Status Karma 연동처럼, election 바깥에서 공용으로 쓰는 레지스트리 구현체를 둔다.

- `factory/`
  election 인스턴스를 생성하고 초기값을 연결하는 팩토리 구현체를 둔다.

- `election/base/`
  election 공용 저장소와 여러 모듈이 함께 쓰는 상태변수를 둔다.

- `election/modules/`
  lifecycle, eligibility, open vote, private vote, settlement처럼 election 내부 책임을 기능별로 분리한다.

- `election/`
  모듈들을 최종 조합한 `VESTArElectionCore` 베이스와 실제 배포 계약 `VESTArElection`을 둔다.

## File Meaning

- `registry/VESTArOrganizerRegistry.sol`
  organizer profile, verified 상태, organizer 생성 자격 판정 구현체

- `registry/VESTArKarmaRegistry.sol`
  Status Karma / KarmaTiers를 읽어 tier와 eligibility를 해석하는 구현체

- `factory/VESTArElectionFactory.sol`
  organizer/karma registry를 참조해 실제 `VESTArElection`을 배포하는 팩토리 구현체

- `election/base/VESTArElectionStorage.sol`
  election 공통 상태변수, ballot 정책 helper, 결제 helper 저장소

- `election/modules/VESTArElectionLifecycleImpl.sol`
  상태 전이, cancel, key reveal, finalize 구현

- `election/modules/VESTArElectionEligibilityImpl.sol`
  karma/tier, resetInterval, 단위 기간, 남은 ballot 계산 구현

- `election/modules/VESTArOpenVoteModuleImpl.sol`
  Open Tally 투표 제출, 중복 후보 차단, 실시간 tally 구현

- `election/modules/VESTArPrivateVoteModuleImpl.sol`
  Private Tally 암호문 제출, 공개키/커밋 조회 구현

- `election/modules/VESTArSettlementModuleImpl.sol`
  mockUSDT 기준 ballot 단위 과금과 50:50 정산 구현

- `election/VESTArElectionCore.sol`
  각 모듈을 조합하는 공통 코어 베이스

- `election/VESTArElection.sol`
  factory가 실제로 배포하는 concrete election 계약. candidate allowlist와 group 메타데이터 관리까지 포함
