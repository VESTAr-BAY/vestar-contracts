// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {VESTArOwnablePausable} from "../../access/VESTArOwnablePausable.sol";
import {IVESTArElectionFactory} from "../../interfaces/vestar/IVESTArElectionFactory.sol";
import {IVESTArKarmaRegistry} from "../../interfaces/vestar/IVESTArKarmaRegistry.sol";
import {IVESTArOrganizerRegistry} from "../../interfaces/vestar/IVESTArOrganizerRegistry.sol";
import {VESTArTypes} from "../../libraries/vestar/VESTArTypes.sol";
import {VESTArElection} from "../election/VESTArElection.sol";

// election 인스턴스를 생성하고 registry/treasury/share 설정을 연결하는 팩토리 구현체 자리
// factory는 "만드는 책임"만 맡고, 만들어진 election의 런타임 로직은 election 폴더 쪽이 맡게 분리

// 주최자가 직접 VESTArElection을 new 하지 않고 factory를 거치게 하면,
// 자격 검증 / 공통 treasury / 공통 admin 연결을 한 곳에서 강제할 수 있어 운영이 단순해짐
contract VESTArElectionFactory is VESTArOwnablePausable, IVESTArElectionFactory {
    using Clones for address;

    address internal _organizerRegistry;
    address internal _karmaRegistry;
    address internal _platformTreasury;
    address internal _electionImplementation;
    uint256 internal _totalElections;

    mapping(address organizer => uint256 nonce) internal _nextElectionNonceByOrganizer;
    mapping(bytes32 electionId => address electionAddress) internal _electionById;
    mapping(bytes32 seriesId => bytes32[] electionIds) internal _electionIdsBySeriesId;

    constructor(
        address initialOwner,
        address organizerRegistryAddress,
        address karmaRegistryAddress,
        address platformTreasuryAddress,
        address electionImplementationAddress
    ) VESTArOwnablePausable(initialOwner) {
        require(electionImplementationAddress != address(0), "VESTAr: implementation is zero");

        _organizerRegistry = organizerRegistryAddress;
        _karmaRegistry = karmaRegistryAddress;
        _platformTreasury = platformTreasuryAddress;
        _electionImplementation = electionImplementationAddress;
    }

    function organizerRegistry() public view returns (address) {
        return _organizerRegistry;
    }

    function karmaRegistry() public view returns (address) {
        return _karmaRegistry;
    }

    function platformTreasury() public view returns (address) {
        return _platformTreasury;
    }

    function platformShareBps() public pure returns (uint16) {
        return 5_000;
    }

    function organizerShareBps() public pure returns (uint16) {
        return 5_000;
    }

    function electionImplementation() public view returns (address) {
        return _electionImplementation;
    }

    function totalElections() public view returns (uint256) {
        return _totalElections;
    }

    function totalElectionsInSeries(bytes32 seriesId) public view returns (uint256) {
        return _electionIdsBySeriesId[seriesId].length;
    }

    function nextElectionNonce(address organizer) public view returns (uint256) {
        return _nextElectionNonceByOrganizer[organizer];
    }

    function previewNextElectionId(address organizer, bytes32 seriesId, bytes32 titleHash, uint64 startAt, uint64 endAt)
        public
        view
        returns (bytes32 electionId)
    {
        return
            computeElectionId(organizer, seriesId, titleHash, startAt, endAt, _nextElectionNonceByOrganizer[organizer]);
    }

    function computeElectionId(
        address organizer,
        bytes32 seriesId,
        bytes32 titleHash,
        uint64 startAt,
        uint64 endAt,
        uint256 organizerNonce
    ) public view returns (bytes32 electionId) {
        return keccak256(
            abi.encode(address(this), block.chainid, organizer, seriesId, titleHash, startAt, endAt, organizerNonce)
        );
    }

    // admin 설정 관련 코드 : 운영 중 organizer registry 주소를 바꿔야 할 때 owner가 갱신
    function setOrganizerRegistry(address organizerRegistryAddress) external onlyOwner {
        _organizerRegistry = organizerRegistryAddress;
    }

    // admin 설정 관련 코드 : 운영 중 karma registry 주소를 바꿔야 할 때 owner가 갱신
    function setKarmaRegistry(address karmaRegistryAddress) external onlyOwner {
        _karmaRegistry = karmaRegistryAddress;
    }

    // admin 설정 관련 코드 : 정산 treasury를 바꿔야 할 때 owner가 갱신
    function setPlatformTreasury(address platformTreasuryAddress) external onlyOwner {
        _platformTreasury = platformTreasuryAddress;
    }

    // 생성 관련 코드 : organizer 상태와 karma tier를 확인한 뒤 새 election 계약을 배포하고 initialize까지 실행
    // 예시 : verified organizer는 karma 0이어도 통과, unverified organizer는 tier 1 이상이어야 통과
    // 통과하면 factory가 새 election 주소를 만들고 organizer snapshot / treasury / karma registry를 같이 주입함
    function createElection(VESTArTypes.ElectionConfig calldata config)
        external
        whenNotPaused
        returns (address electionAddress)
    {
        // 예시 :
        // 1) organizer가 config를 준비해서 factory에 전달
        // 2) factory가 organizer registry + karma registry를 읽어 생성 자격 확인
        // 3) 통과하면 새 election 계약을 배포하고 initialize를 호출
        // 4) 프론트/백은 ElectionCreated 이벤트를 보고 새 election 주소를 인덱싱
        require(config.seriesId != bytes32(0), "VESTAr: seriesId is zero");

        bool verifiedSnapshot = IVESTArOrganizerRegistry(_organizerRegistry).isVerified(msg.sender);
        uint8 organizerTier = 0;

        if (_karmaRegistry != address(0)) {
            organizerTier = IVESTArKarmaRegistry(_karmaRegistry).tierIdOf(msg.sender);
        }

        require(
            IVESTArOrganizerRegistry(_organizerRegistry).canCreateElection(msg.sender, organizerTier),
            "VESTAr: organizer not eligible"
        );

        uint256 organizerNonce = _nextElectionNonceByOrganizer[msg.sender];
        bytes32 generatedElectionId = computeElectionId(
            msg.sender, config.seriesId, config.titleHash, config.startAt, config.endAt, organizerNonce
        );
        require(_electionById[generatedElectionId] == address(0), "VESTAr: election exists");

        // 배포 관련 코드 : MVP는 clone 대신 new로 직접 배포해서 초기 학습 난도를 낮춤
        // 배포 관련 코드 : 구현체를 직접 다시 배포하지 않고 clone을 찍으면
        // factory 자체의 initcode/runtime이 작아져 Status RPC의 oversized data 문제를 줄이기 쉬움
        VESTArElection election = VESTArElection(_electionImplementation.clone());
        election.initialize(
            generatedElectionId, config, msg.sender, verifiedSnapshot, _karmaRegistry, owner, _platformTreasury
        );

        electionAddress = address(election);
        _nextElectionNonceByOrganizer[msg.sender] = organizerNonce + 1;
        _electionById[generatedElectionId] = electionAddress;
        _electionIdsBySeriesId[config.seriesId].push(generatedElectionId);
        _totalElections += 1;

        emit ElectionCreated(
            config.seriesId,
            generatedElectionId,
            msg.sender,
            electionAddress,
            config.visibilityMode,
            verifiedSnapshot,
            config.paymentMode,
            config.costPerBallot
        );
    }

    function getElection(bytes32 electionId) public view returns (address electionAddress) {
        return _electionById[electionId];
    }

    function getSeriesElectionIds(bytes32 seriesId) public view returns (bytes32[] memory electionIds) {
        return _electionIdsBySeriesId[seriesId];
    }

    function getSeriesElectionAddresses(bytes32 seriesId) public view returns (address[] memory electionAddresses) {
        bytes32[] storage electionIds = _electionIdsBySeriesId[seriesId];
        electionAddresses = new address[](electionIds.length);

        for (uint256 i = 0; i < electionIds.length; ++i) {
            electionAddresses[i] = _electionById[electionIds[i]];
        }
    }
}
