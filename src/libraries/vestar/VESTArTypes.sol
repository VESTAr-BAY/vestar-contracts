// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// VESTAr 전역에서 같이 쓰는 enum / struct 타입들을 한 곳에 모아두는 파일
library VESTArTypes {

    enum VisibilityMode {
        OPEN,
        PRIVATE
    }

    // ElectionState는 투표 생명주기 상태를 표현
    enum ElectionState {
        Scheduled, // 투표가 생성됐지만 아직 시작 시간이 안 된 상태
        Active,
        Closed,
        KeyRevealPending, // 투표는 끝났는데 아직 복호화용 개인키를 공개하지 않은 상태
        KeyRevealed,
        Finalized,
        Cancelled
    }

    // 결제 모드 관련 코드 : 무료 투표와 유료 투표를 enum으로 고정해서 의미를 명확하게 표현
    enum PaymentMode {
        FREE,
        PAID
    }

    // ballot 정책 관련 코드 : "선거 전체 1회", "기간마다 1회", "유료 무제한"을 명시적으로 구분
    enum BallotPolicy {
        ONE_PER_ELECTION,
        ONE_PER_INTERVAL,
        UNLIMITED_PAID
    }

    // 주최자 상태 관련 코드 : verified 여부와 카르마 조건을 합쳐 "투표 생성 가능 상태"를 명시적으로 표현
    enum OrganizerCreationStatus {
        VERIFIED_ELIGIBLE,
        UNVERIFIED_ELIGIBLE,
        UNVERIFIED_INELIGIBLE
    }

    struct OrganizerProfile {
        // 주최자 지갑 주소
        address organizer;
        // 주최자 표시 이름 자체가 아니라, 그 이름의 해시값
        bytes32 displayNameHash;
        // 이 주최자가 현재 인증된 공식 주최자인지 여부
        bool verified;
        // 인증이 효력을 가지기 시작한 시각
        uint64 verificationEffectiveTime;
        // 인증이 해제된 시각
        uint64 verificationRevokedTime;
        string brandMetadataURI;
    }

    // ElectionConfig는 투표를 만들 때 필요한 핵심 설정 묶음
    struct ElectionConfig {
        bytes32 electionId;
        VisibilityMode visibilityMode;
        // 제목 자체 대신 해시를 둘 수도 있어서 bytes32 사용
        bytes32 titleHash;
        // 후보 목록 manifest 무결성 확인용 해시
        bytes32 candidateManifestHash;
        // 실제 manifest를 가져올 URI
        string candidateManifestURI;
        // 시작 / 종료 / 결과 공개 시각
        uint64 startAt;
        uint64 endAt;
        uint64 resultRevealAt;
        // 최소 카르마 티어
        uint8 minKarmaTier;
        // ballot 정책 관련 코드 : 전체 기간 1회 / resetInterval마다 1회 / 유료 무제한 중 무엇인지 명시
        BallotPolicy ballotPolicy;
        // 투표 단위 기간 관련 코드 : ONE_PER_INTERVAL일 때만 초 단위 갱신 주기로 사용
        uint64 resetInterval;
        // 결제 모드 관련 코드 : FREE면 무료, PAID면 costPerBallot을 결제해야 함
        PaymentMode paymentMode;
        // 결제 모드 관련 코드 : 후보 수가 아니라 ballot 1개당 결제 비용
        uint256 costPerBallot;
        // 다중 선택 관련 코드 : 한 ballot 안에서 여러 후보를 고를 수 있는지 여부
        bool allowMultipleChoice;
        // 다중 선택 관련 코드 : 한 ballot 안에서 고를 수 있는 최대 후보 수
        uint16 maxSelectionsPerSubmission;
        // 단위 기간 계산 관련 코드 : 로컬 날짜 기준 리셋이 필요할 때 사용할 시차 보정용 오프셋
        int32 timezoneWindowOffset;
        // 결제 토큰 관련 코드 : MVP에서는 mockUSDT 같은 ERC20 주소를 저장하는 용도
        address paymentToken;
        // bytes: 길이가 가변적인 바이너리 데이터. 공개키처럼 길이가 달라질 수 있는 값에 사용
        bytes electionPublicKey;
        // 공개될 private key가 정말 조직이 없는 것인지 확인하는 커밋 해시
        bytes32 privateKeyCommitmentHash;
        // 암호화 스킴 버전
        uint16 keySchemeVersion;
    }

    // 종료 후 결과 요약을 한 번에 반환하거나 저장할 때 씀
    struct ResultSummary {
        // 결과 파일 자체의 무결성을 검증하기 위한 해시
        bytes32 resultManifestHash;
        // 결과 JSON / CSV 같은 산출물 위치
        string resultManifestURI;
        // 총 제출 수
        uint256 totalSubmissions;
        // 유효표 수
        uint256 totalValidVotes;
        // 무효표 수
        uint256 totalInvalidVotes;
    }

    // 그룹 기능 관련 코드 : 후보를 묶는 group의 메타데이터를 온체인에서 읽기 쉽게 표현
    struct GroupDefinition {
        // groupKeyHash: "female-solo" 같은 정규화 그룹 키의 해시
        bytes32 groupKeyHash;
        // metadataHash: 그룹 설명 JSON / 이미지 manifest 무결성 검증용 해시
        bytes32 metadataHash;
        // metadataURI: 그룹 설명이나 배너를 가져올 URI
        string metadataURI;
        // enabled: 이 그룹이 현재 활성 상태인지 여부
        bool enabled;
    }

    // 그룹 기능 관련 코드 : 특정 후보가 어느 group에 속하는지 연결할 때 쓰는 구조체
    struct CandidateGroupBinding {
        bytes32 candidateHash;
        bytes32 groupKeyHash;
    }

    // 투표권 사용량 관련 코드 : 한 유저가 특정 단위 기간에서 ballot을 몇 번 썼는지 표현
    struct BallotUsage {
        // periodKey: 단위 기간 구분용 키
        uint48 periodKey;
        // 이미 제출한 ballot 수
        uint32 submittedBallots;
        // 현재 단위 기간에 아직 제출 가능한 ballot 수
        uint32 remainingBallots;
        // 무제한 유료 반복 투표인지 여부
        bool isUnlimited;
    }

    // 투표 종료 후 수익 정산 결과를 한 번에 읽기 위한 구조체
    struct SettlementSummary {
        // 결제 토큰 주소
        address paymentToken;
        // 플랫폼 몫을 받을 treasury 주소
        address platformTreasury;
        // 총 수납 금액
        uint256 totalRevenueAmount;
        // 플랫폼 몫 50%
        uint256 platformRevenueAmount;
        // organizer 몫 50%
        uint256 organizerRevenueAmount;
        // 이미 정산을 실행했는지 여부
        bool settled;
    }
}
