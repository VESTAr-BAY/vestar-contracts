// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArTypes} from "../../../src/libraries/vestar/VESTArTypes.sol";
import {VESTArElection} from "../../../src/vestar/election/VESTArElection.sol";
import {VESTArElectionFactory} from "../../../src/vestar/factory/VESTArElectionFactory.sol";
import {VESTArOrganizerRegistry} from "../../../src/vestar/registry/VESTArOrganizerRegistry.sol";
import {VESTArTestBase} from "../base/VESTArTestBase.sol";

// registry -> factory -> election 전체 흐름을 붙여 보는 통합 테스트 자리
// integration test는 모듈 단위가 아니라 "사용자 시나리오 전체"가 통과하는지 보는 테스트
contract VESTArEndToEndTest is VESTArTestBase {
    VESTArOrganizerRegistry internal organizerRegistry;
    VESTArElectionFactory internal electionFactory;
    VESTArElection internal electionImplementation;

    function setUp() public {
        _deployCommonMocks();

        organizerRegistry = new VESTArOrganizerRegistry(platformAdmin);
        electionImplementation = new VESTArElection(platformAdmin);
        electionFactory = new VESTArElectionFactory(
            platformAdmin,
            address(organizerRegistry),
            address(mockKarmaRegistry),
            platformTreasury,
            address(electionImplementation)
        );

        vm.prank(platformAdmin);
        organizerRegistry.setVerification(organizer, true, 100, 0);
    }

    function testOpenElectionEndToEndWithGroupsAndSettlement() public {
        // 실제 사례 :
        // 1) verified organizer가 Open election 생성
        // 2) 투표 시작 전 candidate allowlist와 group 메타데이터를 등록
        // 3) 유저가 ["IU", "ParkHyoShin"] 다중 선택 ballot 1개를 제출
        // 4) 종료 후 organizer가 결과를 finalize하고 수익을 50:50 정산
        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            bytes32("open-e2e"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            25_001
        );

        vm.prank(organizer);
        address electionAddress = electionFactory.createElection(config);

        VESTArElection election = VESTArElection(electionAddress);

        bytes32 iuHash = keccak256(bytes("IU"));
        bytes32 parkHash = keccak256(bytes("ParkHyoShin"));
        bytes32 femaleSoloGroupHash = keccak256(bytes("female-solo"));

        bytes32[] memory candidateHashes = new bytes32[](2);
        candidateHashes[0] = iuHash;
        candidateHashes[1] = parkHash;

        VESTArTypes.GroupDefinition[] memory groups = new VESTArTypes.GroupDefinition[](1);
        groups[0] = VESTArTypes.GroupDefinition({
            groupKeyHash: femaleSoloGroupHash,
            metadataHash: keccak256("female-solo-group"),
            metadataURI: "ipfs://groups/female-solo",
            enabled: true
        });

        VESTArTypes.CandidateGroupBinding[] memory bindings = new VESTArTypes.CandidateGroupBinding[](1);
        bindings[0] = VESTArTypes.CandidateGroupBinding({
            candidateHash: iuHash,
            groupKeyHash: femaleSoloGroupHash
        });

        vm.prank(organizer);
        election.setCandidateAllowlist(candidateHashes, true);

        vm.prank(organizer);
        election.setGroupDefinitions(groups);

        vm.prank(organizer);
        election.setCandidateGroups(bindings);

        assertEq(election.candidateGroupOf(iuHash), femaleSoloGroupHash);
        assertTrue(election.isCandidateHashAllowed(iuHash));

        mockKarmaRegistry.setTier(voter, 1);
        mockUSDT.mint(voter, 25_001);

        vm.warp(block.timestamp + 1 days);

        string[] memory selections = new string[](2);
        selections[0] = "IU";
        selections[1] = "ParkHyoShin";

        vm.startPrank(voter);
        mockUSDT.approve(address(election), 25_001);
        election.submitOpenVote(selections);
        vm.stopPrank();

        assertEq(election.totalVotesForCandidate("IU"), 1);
        assertEq(election.totalVotesForCandidate("ParkHyoShin"), 1);
        assertEq(election.totalCollectedAmount(), 25_001);

        vm.warp(block.timestamp + 2 days);
        election.syncState();

        vm.prank(organizer);
        election.finalizeResults(_resultSummary("ipfs://results/open"));

        vm.prank(organizer);
        election.settleRevenue();

        assertEq(mockUSDT.balanceOf(platformTreasury), 12_500);
        assertEq(mockUSDT.balanceOf(organizer), 12_501);
        assertTrue(election.getSettlementSummary().settled);
    }

    function testFrontendCanReadGroupMetadataForCandidateFilterUi() public {
        // 실제 사례 :
        // 프론트는 투표 시작 전에 group 정의와 candidate-group 연결을 읽어서
        // "솔로", "밴드", "남성", "여성" 같은 필터 UI를 구성해야 함
        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            bytes32("group-read"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            25_001
        );

        vm.prank(organizer);
        address electionAddress = electionFactory.createElection(config);

        VESTArElection election = VESTArElection(electionAddress);

        bytes32 iuHash = keccak256(bytes("IU"));
        bytes32 femaleSoloGroupHash = keccak256(bytes("female-solo"));

        bytes32[] memory candidateHashes = new bytes32[](1);
        candidateHashes[0] = iuHash;

        VESTArTypes.GroupDefinition[] memory groups = new VESTArTypes.GroupDefinition[](1);
        groups[0] = VESTArTypes.GroupDefinition({
            groupKeyHash: femaleSoloGroupHash,
            metadataHash: keccak256("female-solo-group"),
            metadataURI: "ipfs://groups/female-solo",
            enabled: true
        });

        VESTArTypes.CandidateGroupBinding[] memory bindings = new VESTArTypes.CandidateGroupBinding[](1);
        bindings[0] = VESTArTypes.CandidateGroupBinding({
            candidateHash: iuHash,
            groupKeyHash: femaleSoloGroupHash
        });

        vm.prank(organizer);
        election.setCandidateAllowlist(candidateHashes, true);

        vm.prank(organizer);
        election.setGroupDefinitions(groups);

        vm.prank(organizer);
        election.setCandidateGroups(bindings);

        VESTArTypes.GroupDefinition memory group = election.getGroupDefinition(femaleSoloGroupHash);

        assertEq(group.groupKeyHash, femaleSoloGroupHash);
        assertEq(group.metadataURI, "ipfs://groups/female-solo");
        assertTrue(group.enabled);
        assertEq(election.candidateGroupOf(iuHash), femaleSoloGroupHash);
    }

    function testOrganizerCannotChangeCandidateSetupAfterElectionStarts() public {
        // 실제 사례 :
        // 주최자는 시작 전에 후보/그룹을 준비할 수 있지만,
        // 투표가 열린 뒤에는 프론트/백엔드 집계 기준이 흔들리지 않게 수정이 막혀야 함
        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            bytes32("lock-after-start"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            25_001
        );

        vm.prank(organizer);
        address electionAddress = electionFactory.createElection(config);

        VESTArElection election = VESTArElection(electionAddress);

        bytes32[] memory candidateHashes = new bytes32[](1);
        candidateHashes[0] = keccak256(bytes("IU"));

        vm.warp(block.timestamp + 1 days);

        vm.prank(organizer);
        vm.expectRevert("VESTAr: already started");
        election.setCandidateAllowlist(candidateHashes, true);
    }

    function testPrivateElectionEndToEndWithRevealAndSettlement() public {
        // 실제 사례 :
        // 1) verified organizer가 Private election 생성
        // 2) 유저가 공개키로 암호화한 ballot 1개를 제출
        // 3) 종료 후 reveal manager가 private key를 공개
        // 4) organizer가 결과 finalize 후 50:50 정산
        bytes memory privateKeyData = hex"0123456789";

        VESTArTypes.ElectionConfig memory config = _buildPrivateConfig(
            bytes32("private-e2e"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            uint64(block.timestamp + 3 days),
            FULL_PRICE_PER_BALLOT,
            keccak256(privateKeyData)
        );

        vm.prank(organizer);
        address electionAddress = electionFactory.createElection(config);

        VESTArElection election = VESTArElection(electionAddress);

        mockKarmaRegistry.setTier(voter, 1);
        mockUSDT.mint(voter, FULL_PRICE_PER_BALLOT);

        vm.warp(block.timestamp + 1 days);

        vm.startPrank(voter);
        mockUSDT.approve(address(election), FULL_PRICE_PER_BALLOT);
        election.submitEncryptedVote(hex"abcdef1234");
        vm.stopPrank();

        assertEq(election.totalCollectedAmount(), FULL_PRICE_PER_BALLOT);

        vm.warp(block.timestamp + 2 days + 1 days);

        vm.prank(platformAdmin);
        election.setRevealManager(revealManager, true);

        vm.prank(revealManager);
        election.revealPrivateKey(privateKeyData);

        vm.prank(organizer);
        election.finalizeResults(_resultSummary("ipfs://results/private"));

        vm.prank(organizer);
        election.settleRevenue();

        assertEq(uint256(election.state()), uint256(VESTArTypes.ElectionState.Finalized));
        assertTrue(election.getSettlementSummary().settled);
        assertEq(mockUSDT.balanceOf(platformTreasury), FULL_PRICE_PER_BALLOT / 2);
        assertEq(mockUSDT.balanceOf(organizer), FULL_PRICE_PER_BALLOT / 2);
    }

    function testFrontendCanReadConfigAndGroupMetadataAfterOrganizerSetup() public {
        // 실제 사례 :
        // 1) organizer가 투표를 만들고 후보/그룹 메타데이터를 등록
        // 2) 프론트는 getElectionConfig / getGroupDefinition / candidateGroupOf를 읽어서
        //    "어떤 화면을 그릴지"와 "후보가 어느 그룹에 속하는지"를 바로 구성함
        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            bytes32("front-read"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            25_001
        );

        vm.prank(organizer);
        address electionAddress = electionFactory.createElection(config);

        VESTArElection election = VESTArElection(electionAddress);

        bytes32 iuHash = keccak256(bytes("IU"));
        bytes32 womenGroupHash = keccak256(bytes("women-solo"));

        bytes32[] memory candidateHashes = new bytes32[](1);
        candidateHashes[0] = iuHash;

        VESTArTypes.GroupDefinition[] memory groups = new VESTArTypes.GroupDefinition[](1);
        groups[0] = VESTArTypes.GroupDefinition({
            groupKeyHash: womenGroupHash,
            metadataHash: keccak256("women-solo-group"),
            metadataURI: "ipfs://groups/women-solo",
            enabled: true
        });

        VESTArTypes.CandidateGroupBinding[] memory bindings = new VESTArTypes.CandidateGroupBinding[](1);
        bindings[0] = VESTArTypes.CandidateGroupBinding({
            candidateHash: iuHash,
            groupKeyHash: womenGroupHash
        });

        vm.prank(organizer);
        election.setCandidateAllowlist(candidateHashes, true);

        vm.prank(organizer);
        election.setGroupDefinitions(groups);

        vm.prank(organizer);
        election.setCandidateGroups(bindings);

        VESTArTypes.ElectionConfig memory storedConfig = election.getElectionConfig();
        VESTArTypes.GroupDefinition memory storedGroup = election.getGroupDefinition(womenGroupHash);

        assertEq(storedConfig.electionId, bytes32("front-read"));
        assertEq(storedConfig.candidateManifestURI, "ipfs://open-candidates");
        assertTrue(election.isCandidateHashAllowed(iuHash));
        assertEq(election.candidateGroupOf(iuHash), womenGroupHash);
        assertEq(storedGroup.groupKeyHash, womenGroupHash);
        assertEq(storedGroup.metadataURI, "ipfs://groups/women-solo");
        assertTrue(storedGroup.enabled);
    }

    function _buildOpenConfig(
        bytes32 electionId_,
        uint64 startAt_,
        uint64 endAt_,
        uint256 costPerBallot_
    ) internal view returns (VESTArTypes.ElectionConfig memory) {
        return VESTArTypes.ElectionConfig({
            electionId: electionId_,
            visibilityMode: VESTArTypes.VisibilityMode.OPEN,
            titleHash: keccak256("EndToEnd Open Vote"),
            candidateManifestHash: keccak256("open-candidates"),
            candidateManifestURI: "ipfs://open-candidates",
            startAt: startAt_,
            endAt: endAt_,
            resultRevealAt: endAt_,
            minKarmaTier: 1,
            ballotPolicy: VESTArTypes.BallotPolicy.ONE_PER_INTERVAL,
            resetInterval: 1 days,
            paymentMode: VESTArTypes.PaymentMode.PAID,
            costPerBallot: costPerBallot_,
            allowMultipleChoice: true,
            maxSelectionsPerSubmission: 3,
            timezoneWindowOffset: 0,
            paymentToken: address(mockUSDT),
            electionPublicKey: "",
            privateKeyCommitmentHash: bytes32(0),
            keySchemeVersion: 0
        });
    }

    function _buildPrivateConfig(
        bytes32 electionId_,
        uint64 startAt_,
        uint64 endAt_,
        uint64 resultRevealAt_,
        uint256 costPerBallot_,
        bytes32 commitmentHash
    ) internal view returns (VESTArTypes.ElectionConfig memory) {
        return VESTArTypes.ElectionConfig({
            electionId: electionId_,
            visibilityMode: VESTArTypes.VisibilityMode.PRIVATE,
            titleHash: keccak256("EndToEnd Private Vote"),
            candidateManifestHash: keccak256("private-candidates"),
            candidateManifestURI: "ipfs://private-candidates",
            startAt: startAt_,
            endAt: endAt_,
            resultRevealAt: resultRevealAt_,
            minKarmaTier: 1,
            ballotPolicy: VESTArTypes.BallotPolicy.ONE_PER_INTERVAL,
            resetInterval: 1 days,
            paymentMode: VESTArTypes.PaymentMode.PAID,
            costPerBallot: costPerBallot_,
            allowMultipleChoice: false,
            maxSelectionsPerSubmission: 1,
            timezoneWindowOffset: 0,
            paymentToken: address(mockUSDT),
            electionPublicKey: hex"cafe",
            privateKeyCommitmentHash: commitmentHash,
            keySchemeVersion: 1
        });
    }

    function _resultSummary(string memory resultManifestUri)
        internal
        pure
        returns (VESTArTypes.ResultSummary memory)
    {
        return VESTArTypes.ResultSummary({
            resultManifestHash: keccak256(bytes(resultManifestUri)),
            resultManifestURI: resultManifestUri,
            totalSubmissions: 1,
            totalValidVotes: 1,
            totalInvalidVotes: 0
        });
    }
}
