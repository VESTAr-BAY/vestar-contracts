// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArTypes} from "../../libraries/vestar/VESTArTypes.sol";
import {IVESTArAdminControl} from "./IVESTArAdminControl.sol";
import {IVESTArElectionEligibility} from "./IVESTArElectionEligibility.sol";
import {IVESTArElectionLifecycle} from "./IVESTArElectionLifecycle.sol";
import {IVESTArOpenVoteModule} from "./IVESTArOpenVoteModule.sol";
import {IVESTArPrivateVoteModule} from "./IVESTArPrivateVoteModule.sol";
import {IVESTArSettlementModule} from "./IVESTArSettlementModule.sol";

// election core가 가져야 할 공통 표면을 한 곳에 모으는 최상위 인터페이스
// interface도 여러 interface를 다중 상속할 수 있어서, 모듈별로 쪼갠 뒤 마지막에 합침
interface IVESTArElectionCore is
    IVESTArAdminControl,
    IVESTArElectionLifecycle,
    IVESTArElectionEligibility,
    IVESTArOpenVoteModule,
    IVESTArPrivateVoteModule,
    IVESTArSettlementModule
{
    // 후보 등록 관련 코드 : Open 모드 validation에 쓰는 candidate allowlist 변경 로그
    event CandidateAllowlistUpdated(
        bytes32 indexed electionId,
        bytes32 indexed candidateHash,
        bool allowed
    );

    // 그룹 기능 관련 코드 : organizer가 group 메타데이터를 등록하거나 수정할 때 남기는 로그
    event GroupDefinitionUpdated(
        bytes32 indexed electionId,
        bytes32 indexed groupKeyHash,
        bytes32 metadataHash,
        string metadataURI,
        bool enabled
    );

    // 그룹 기능 관련 코드 : 후보를 특정 group에 연결했을 때 남기는 로그
    event CandidateGroupUpdated(
        bytes32 indexed electionId,
        bytes32 indexed candidateHash,
        bytes32 indexed groupKeyHash
    );

    // Open / Private 모드 확인
    function visibilityMode() external view returns (VESTArTypes.VisibilityMode);

    // 다중 선택 허용 여부
    function allowMultipleChoice() external view returns (bool);

    // 다중 선택일 때 ballot 하나에 담을 수 있는 최대 후보 수
    function maxSelectionsPerSubmission() external view returns (uint16);

    // 후보 등록 관련 코드 : 투표 시작 전에 organizer/admin이 허용 후보 hash 목록을 세팅
    function setCandidateAllowlist(bytes32[] calldata candidateHashes, bool allowed) external;

    // 후보 등록 관련 코드 : 후보 hash가 allowlist에 등록돼 있는지 직접 조회
    function isCandidateHashAllowed(bytes32 candidateHash) external view returns (bool);

    // 그룹 기능 관련 코드 : group 메타데이터를 일괄 등록
    function setGroupDefinitions(VESTArTypes.GroupDefinition[] calldata groupDefinitions) external;

    // 그룹 기능 관련 코드 : 후보 hash를 group hash에 연결
    function setCandidateGroups(VESTArTypes.CandidateGroupBinding[] calldata bindings) external;

    // 그룹 기능 관련 코드 : group 정보를 struct 단위로 읽음
    function getGroupDefinition(bytes32 groupKeyHash)
        external
        view
        returns (VESTArTypes.GroupDefinition memory);

    // 그룹 기능 관련 코드 : 특정 후보가 속한 group hash를 조회
    function candidateGroupOf(bytes32 candidateHash) external view returns (bytes32);
}
