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

    // 초기화 관련 코드 : factory가 election config / organizer / registry / treasury 연결을 한 번에 넣어줌
    // 예시 : organizer가 createElection(config)를 호출하면 factory가 새 election을 만든 뒤
    // initialize(...)에서 "이 투표는 누구 것인지, 어느 karma registry를 볼지, 어떤 토큰을 받을지"를 채움
    function initialize(
        VESTArTypes.ElectionConfig calldata config,
        address organizerAddress,
        bool organizerVerifiedSnapshot_,
        address karmaRegistryAddress,
        address platformAdminAddress,
        address platformTreasuryAddress
    ) external {
        require(!initialized, "VESTAr: already initialized");
        require(organizerAddress != address(0), "VESTAr: organizer is zero");
        require(platformAdminAddress != address(0), "VESTAr: admin is zero");
        require(config.electionId != bytes32(0), "VESTAr: electionId is zero");

        // clone 배포 관련 코드 : clone은 constructor를 다시 타지 않으므로,
        // 실제 election 인스턴스의 factory 주소와 owner를 initialize에서 직접 세팅해야 함
        if (factory == address(0)) {
            factory = msg.sender;
        }

        require(msg.sender == factory, "VESTAr: only factory");

        _config = config;
        _organizer = organizerAddress;
        _organizerVerifiedSnapshot = organizerVerifiedSnapshot_;
        _karmaRegistry = karmaRegistryAddress;
        _platformAdmin = platformAdminAddress;
        _settlementSummary.paymentToken = config.paymentToken;
        _settlementSummary.platformTreasury = platformTreasuryAddress;
        _state = VESTArTypes.ElectionState.Scheduled;
        owner = platformAdminAddress;

        _validateElectionConfig();

        initialized = true;

        emit OwnershipTransferred(address(0), platformAdminAddress);

        emit ElectionInitialized(
            config.electionId,
            organizerAddress,
            config.visibilityMode,
            organizerVerifiedSnapshot_,
            config.paymentMode,
            config.costPerBallot
        );
    }

    // 후보 등록 관련 코드 : organizer/admin이 투표 시작 전에 후보 hash allowlist를 세팅
    // 예시 : "IU", "ParkHyoShin" 문자열 자체를 저장하지 않고 keccak256 hash 목록만 올려서
    // 프론트/백엔드는 manifest와 같은 hash 규칙을 써서 허용 후보인지 맞춰 볼 수 있음
    function setCandidateAllowlist(bytes32[] calldata candidateHashes, bool allowed) external {
        _requirePlatformAdminOrOrganizer();
        require(syncState() == VESTArTypes.ElectionState.Scheduled, "VESTAr: already started");

        for (uint256 i = 0; i < candidateHashes.length; ++i) {
            _allowedCandidateHash[candidateHashes[i]] = allowed;
            emit CandidateAllowlistUpdated(_config.electionId, candidateHashes[i], allowed);
        }
    }

    function isCandidateHashAllowed(bytes32 candidateHash) external view returns (bool) {
        return _allowedCandidateHash[candidateHash];
    }

    // 그룹 기능 관련 코드 : organizer/admin이 group 메타데이터를 투표 시작 전에 등록
    // 예시 : "female-solo", "band", "rookie" 같은 그룹 hash와 metadata URI를 등록해
    // 프론트가 필터 UI를 만들고 백엔드가 그룹별 결과 페이지를 구성할 수 있게 함
    function setGroupDefinitions(VESTArTypes.GroupDefinition[] calldata groupDefinitions) external {
        _requirePlatformAdminOrOrganizer();
        require(syncState() == VESTArTypes.ElectionState.Scheduled, "VESTAr: already started");

        for (uint256 i = 0; i < groupDefinitions.length; ++i) {
            VESTArTypes.GroupDefinition calldata groupDefinition = groupDefinitions[i];

            require(groupDefinition.groupKeyHash != bytes32(0), "VESTAr: group key is zero");

            _groupDefinitionByKeyHash[groupDefinition.groupKeyHash] = VESTArTypes.GroupDefinition({
                groupKeyHash: groupDefinition.groupKeyHash,
                metadataHash: groupDefinition.metadataHash,
                metadataURI: groupDefinition.metadataURI,
                enabled: groupDefinition.enabled
            });

            emit GroupDefinitionUpdated(
                _config.electionId,
                groupDefinition.groupKeyHash,
                groupDefinition.metadataHash,
                groupDefinition.metadataURI,
                groupDefinition.enabled
            );
        }
    }

    // 그룹 기능 관련 코드 : 후보 hash를 특정 group hash에 연결해서 프론트/백엔드가 그룹 필터를 만들 수 있게 함
    // IU 후보 hash -> female-solo 그룹 hash 로 묶어두면,
    // 프론트는 후보 카드에 그룹 배지를 붙이고 백엔드는 그룹별 집계를 추가로 만들 수 있음
    function setCandidateGroups(VESTArTypes.CandidateGroupBinding[] calldata bindings) external {
        _requirePlatformAdminOrOrganizer();
        require(syncState() == VESTArTypes.ElectionState.Scheduled, "VESTAr: already started");

        for (uint256 i = 0; i < bindings.length; ++i) {
            VESTArTypes.CandidateGroupBinding calldata binding = bindings[i];

            require(_allowedCandidateHash[binding.candidateHash], "VESTAr: candidate not allowed");
            require(
                _groupDefinitionByKeyHash[binding.groupKeyHash].enabled,
                "VESTAr: group not enabled"
            );

            _groupKeyByCandidateHash[binding.candidateHash] = binding.groupKeyHash;

            emit CandidateGroupUpdated(
                _config.electionId,
                binding.candidateHash,
                binding.groupKeyHash
            );
        }
    }

    function getGroupDefinition(bytes32 groupKeyHash)
        external
        view
        returns (VESTArTypes.GroupDefinition memory)
    {
        return _groupDefinitionByKeyHash[groupKeyHash];
    }

    function candidateGroupOf(bytes32 candidateHash) external view returns (bytes32) {
        return _groupKeyByCandidateHash[candidateHash];
    }
}
