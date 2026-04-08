// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArTypes} from "../../libraries/vestar/VESTArTypes.sol";
import {VESTArElectionCore} from "./VESTArElectionCore.sol";

// 실제 배포되는 election 계약
// 복잡한 proxy/clone 대신 "new -> initialize" 흐름으로 가서 초보도 읽기 쉽게 유지

// 이 파일은 사용자/주최자가 실제로 만나는 최종 계약이고,
// 아래 모듈 함수들을 "하나의 배포 주소"로 합쳐 주는 entrypoint 역할을 함
contract VESTArElection is VESTArElectionCore {
    address public factory;
    bool public initialized;

    constructor(address initialOwner) VESTArElectionCore(initialOwner) {}

    // 초기화 관련 코드 : factory가 election config / organizer / registry / treasury / 초기 후보 allowlist를 한 번에 넣어줌
    // 예시 : organizer가 createElection(config, candidateHashes)를 호출하면 factory가 새 election을 만든 뒤
    // initialize(...)에서 "이 투표는 누구 것인지, 어느 karma registry를 볼지, 어떤 토큰을 받을지"를 채움
    function initialize(
        bytes32 electionId_,
        VESTArTypes.ElectionConfig calldata config,
        bytes32[] calldata initialCandidateHashes,
        address organizerAddress,
        bool organizerVerifiedSnapshot_,
        address karmaRegistryAddress,
        address platformAdminAddress,
        address platformTreasuryAddress
    ) external {
        require(!initialized, "VESTAr: already initialized");
        require(organizerAddress != address(0), "VESTAr: organizer is zero");
        require(platformAdminAddress != address(0), "VESTAr: admin is zero");
        require(electionId_ != bytes32(0), "VESTAr: electionId is zero");
        require(initialCandidateHashes.length > 0, "VESTAr: candidates required");

        // clone 배포 관련 코드 : clone은 constructor를 다시 타지 않으므로,
        // 실제 election 인스턴스의 factory 주소와 owner를 initialize에서 직접 세팅해야 함
        if (factory == address(0)) {
            factory = msg.sender;
        }

        require(msg.sender == factory, "VESTAr: only factory");

        _electionId = electionId_;
        _config = config;
        _organizer = organizerAddress;
        _organizerVerifiedSnapshot = organizerVerifiedSnapshot_;
        _karmaRegistry = karmaRegistryAddress;
        _platformAdmin = platformAdminAddress;
        _settlementSummary.paymentToken = config.paymentToken;
        _settlementSummary.platformTreasury = platformTreasuryAddress;
        _refundSummary.paymentToken = config.paymentToken;
        _state = VESTArTypes.ElectionState.Scheduled;
        owner = platformAdminAddress;

        _validateElectionConfig();

        for (uint256 i = 0; i < initialCandidateHashes.length; ++i) {
            require(initialCandidateHashes[i] != bytes32(0), "VESTAr: candidate hash is zero");
            _allowedCandidateHash[initialCandidateHashes[i]] = true;
            emit CandidateAllowlistUpdated(_electionId, initialCandidateHashes[i], true);
        }

        initialized = true;

        emit OwnershipTransferred(address(0), platformAdminAddress);

        emit ElectionInitialized(
            config.seriesId,
            electionId_,
            organizerAddress,
            config.visibilityMode,
            organizerVerifiedSnapshot_,
            config.paymentMode,
            config.costPerBallot
        );
    }

    // 메타데이터 수정 관련 코드 : organizer/admin이 시작 전에 제목/후보 manifest 오탈자를 고칠 수 있게 함
    // 예시 : titleHash만 바뀌는 사소한 오탈자 수정이어도, 프론트/백엔드가 같은 스냅샷을 읽게
    // titleHash + candidateManifest(hash/URI)를 한 번에 갱신하고 이벤트로 남김
    function updateElectionMetadata(
        bytes32 newTitleHash,
        bytes32 newCandidateManifestHash,
        string calldata newCandidateManifestURI
    ) external {
        _requirePlatformAdminOrOrganizer();
        require(syncState() == VESTArTypes.ElectionState.Scheduled, "VESTAr: already started");
        require(newTitleHash != bytes32(0), "VESTAr: title hash is zero");
        require(newCandidateManifestHash != bytes32(0), "VESTAr: candidate manifest hash is zero");
        require(bytes(newCandidateManifestURI).length > 0, "VESTAr: candidate manifest URI empty");

        _config.titleHash = newTitleHash;
        _config.candidateManifestHash = newCandidateManifestHash;
        _config.candidateManifestURI = newCandidateManifestURI;

        emit ElectionMetadataUpdated(_electionId, newTitleHash, newCandidateManifestHash, newCandidateManifestURI);
    }

    // 후보 등록 관련 코드 : organizer/admin이 투표 시작 전에 후보 hash allowlist를 세팅
    // 예시 : "IU", "ParkHyoShin" 문자열 자체를 저장하지 않고 keccak256 hash 목록만 올려서
    // 프론트/백엔드는 manifest와 같은 hash 규칙을 써서 허용 후보인지 맞춰 볼 수 있음
    function setCandidateAllowlist(bytes32[] calldata candidateHashes, bool allowed) external {
        _requirePlatformAdminOrOrganizer();
        require(syncState() == VESTArTypes.ElectionState.Scheduled, "VESTAr: already started");

        for (uint256 i = 0; i < candidateHashes.length; ++i) {
            _allowedCandidateHash[candidateHashes[i]] = allowed;
            emit CandidateAllowlistUpdated(_electionId, candidateHashes[i], allowed);
        }
    }

    function isCandidateHashAllowed(bytes32 candidateHash) external view returns (bool) {
        return _allowedCandidateHash[candidateHash];
    }
}
