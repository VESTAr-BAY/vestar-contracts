// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArTypes} from "../../libraries/vestar/VESTArTypes.sol";

// election 하나의 상태 전이와 결과 공개 흐름을 정의하는 인터페이스

interface IVESTArElectionLifecycle {
    // election이 처음 준비될 때 찍는 로그
    event ElectionInitialized(
        bytes32 indexed electionId,
        address indexed organizer,
        VESTArTypes.VisibilityMode visibilityMode,
        bool organizerVerifiedSnapshot,
        VESTArTypes.PaymentMode paymentMode,
        uint256 costPerBallot
    );

    // previousState -> nextState처럼 전이 전/후를 같이 기록하면 추적이 쉬움
    event ElectionStateUpdated(
        bytes32 indexed electionId,
        VESTArTypes.ElectionState previousState,
        VESTArTypes.ElectionState nextState
    );

    // Private 모드에서 key 공개 시점을 로그로 남김
    event PrivateKeyRevealed(
        bytes32 indexed electionId,
        bytes32 indexed privateKeyCommitmentHash,
        bytes privateKeyData
    );

    // 내부 팀 관리자에게 key reveal 권한을 위임했는지 기록
    event RevealManagerUpdated(address indexed manager, bool allowed);

    // 최종 결과 manifest가 확정됐을 때 남기는 이벤트
    event ResultFinalized(
        bytes32 indexed electionId,
        bytes32 indexed resultManifestHash,
        string resultManifestURI
    );

    // electionId는 bytes32 같은 고정 길이 식별자로 자주 사용
    function electionId() external view returns (bytes32);

    // organizer는 이 election을 만든 주최자 주소
    function organizer() external view returns (address);

    // 플랫폼 owner/admin 주소
    function platformAdmin() external view returns (address);

    // verifiedSnapshot은 "생성 당시 verified였는가"를 고정하기 위한 값
    function organizerVerifiedSnapshot() external view returns (bool);

    // 현재 상태를 enum으로 읽어오는 함수
    function state() external view returns (VESTArTypes.ElectionState);

    // 설정 전체를 struct로 한 번에 읽는 패턴
    function getElectionConfig() external view returns (VESTArTypes.ElectionConfig memory);

    // 결과 요약도 struct 단위로 반환
    function getResultSummary() external view returns (VESTArTypes.ResultSummary memory);

    // returns (...)가 붙은 non-view 함수도 가능하며, 상태를 바꾸고 새 상태를 반환할 수 있음
    function syncState() external returns (VESTArTypes.ElectionState);

    // 내부 팀용 key reveal 관리자 지정 여부 조회
    function isRevealManager(address account) external view returns (bool);

    // 플랫폼 owner/admin이 내부 팀 관리자에게 key reveal 권한을 위임
    function setRevealManager(address manager, bool allowed) external;

    function cancelBeforeStart() external;

    function closeElection() external;

    function revealPrivateKey(bytes calldata privateKeyData) external;

    function finalizeResults(VESTArTypes.ResultSummary calldata resultSummary) external;
}
