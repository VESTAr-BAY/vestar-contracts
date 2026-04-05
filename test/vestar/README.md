# VESTAr Tests

이 폴더는 `src/vestar` 실제 구현을 검증하는 테스트 모음이다.
단위 테스트는 정책 규칙을 분리해서 확인하고,
통합 테스트는 `registry -> factory -> election -> vote -> finalize -> settle` 전체 흐름을 확인한다.

## Folder Meaning

- `base/`
  공통 테스트 설정, 공통 주소, 공통 helper를 두는 곳

- `registry/`
  OrganizerRegistry, KarmaRegistry 테스트

- `factory/`
  ElectionFactory 테스트

- `election/`
  election 내부 모듈별 테스트

- `integration/`
  registry -> factory -> election 전체 흐름을 붙여 보는 통합 테스트

## File Meaning

- `base/VESTArTestBase.sol`
  공통 setup 베이스

- `registry/VESTArOrganizerRegistry.t.sol`
  organizer profile / verified 상태 테스트

- `registry/VESTArKarmaRegistry.t.sol`
  karma source / tier eligibility 테스트

- `factory/VESTArElectionFactory.t.sol`
  election 생성 / snapshot 연결 / treasury 설정 테스트

- `election/VESTArElectionLifecycle.t.sol`
  상태 전이 / finalize / key reveal 테스트

- `election/VESTArElectionEligibility.t.sol`
  karma tier / ballot / period / resetInterval 계산 테스트

- `election/VESTArOpenVote.t.sol`
  Open Tally 후보 제출 / 중복 후보 차단 / ballot 단위 과금 / 실시간 집계 테스트

- `election/VESTArPrivateVote.t.sol`
  Private Tally 암호문 제출 / 공개키 / 커밋 테스트

- `election/VESTArSettlement.t.sol`
  ballot pricing / mockUSDT 수납 / 50:50 정산 테스트

- `integration/VESTArEndToEnd.t.sol`
  Open/Private 실제 happy path와 group 기능까지 포함한 전체 플로우 테스트
