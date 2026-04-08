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

    function testOpenElectionEndToEndWithSeriesAndSettlement() public {
        // 실제 사례 :
        // 1) verified organizer가 "MAMA 2025" series 아래 "female solo" election 생성
        // 2) 투표 시작 전 candidate allowlist를 등록
        // 3) 유저가 ["IU", "ParkHyoShin"] 다중 선택 ballot 1개를 제출
        // 4) 종료 후 organizer가 결과를 finalize하고 수익을 50:50 정산
        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            bytes32("mama-2025"),
            keccak256("female-solo"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            25_001
        );

        vm.prank(organizer);
        address electionAddress = electionFactory.createElection(config);

        VESTArElection election = VESTArElection(electionAddress);

        bytes32 iuHash = keccak256(bytes("IU"));
        bytes32 parkHash = keccak256(bytes("ParkHyoShin"));

        bytes32[] memory candidateHashes = new bytes32[](2);
        candidateHashes[0] = iuHash;
        candidateHashes[1] = parkHash;

        vm.prank(organizer);
        election.setCandidateAllowlist(candidateHashes, true);

        assertEq(election.seriesId(), bytes32("mama-2025"));
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

    function testFrontendCanReadSeriesElectionListForSingleEventScreen() public {
        // 실제 사례 :
        // 프론트는 "MAMA 2025" 같은 상위 이벤트 화면에서
        // female solo / male solo election을 한 번에 그리기 위해 shared seriesId를 기준으로 목록을 읽음
        bytes32 mamaSeriesId = bytes32("mama-2025");

        VESTArTypes.ElectionConfig memory femaleSoloConfig = _buildOpenConfig(
            mamaSeriesId,
            keccak256("female-solo"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            25_001
        );

        VESTArTypes.ElectionConfig memory maleSoloConfig = _buildOpenConfig(
            mamaSeriesId,
            keccak256("male-solo"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            25_001
        );

        bytes32 expectedFemaleElectionId = electionFactory.previewNextElectionId(
            organizer,
            femaleSoloConfig.seriesId,
            femaleSoloConfig.titleHash,
            femaleSoloConfig.startAt,
            femaleSoloConfig.endAt
        );
        bytes32 expectedMaleElectionId = electionFactory.computeElectionId(
            organizer,
            maleSoloConfig.seriesId,
            maleSoloConfig.titleHash,
            maleSoloConfig.startAt,
            maleSoloConfig.endAt,
            1
        );

        vm.startPrank(organizer);
        address femaleSoloElection = electionFactory.createElection(femaleSoloConfig);
        address maleSoloElection = electionFactory.createElection(maleSoloConfig);
        vm.stopPrank();

        bytes32[] memory electionIds = electionFactory.getSeriesElectionIds(mamaSeriesId);
        address[] memory electionAddresses = electionFactory.getSeriesElectionAddresses(mamaSeriesId);

        assertEq(electionFactory.totalElectionsInSeries(mamaSeriesId), 2);
        assertEq(electionIds.length, 2);
        assertEq(electionAddresses.length, 2);
        assertEq(electionIds[0], expectedFemaleElectionId);
        assertEq(electionIds[1], expectedMaleElectionId);
        assertEq(electionAddresses[0], femaleSoloElection);
        assertEq(electionAddresses[1], maleSoloElection);
        assertEq(VESTArElection(femaleSoloElection).seriesId(), mamaSeriesId);
        assertEq(VESTArElection(maleSoloElection).seriesId(), mamaSeriesId);
    }

    function testOrganizerCannotChangeCandidateSetupAfterElectionStarts() public {
        // 실제 사례 :
        // 주최자는 시작 전에 후보 목록을 준비할 수 있지만,
        // 투표가 열린 뒤에는 프론트/백엔드 집계 기준이 흔들리지 않게 수정이 막혀야 함
        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            bytes32("mama-2025"),
            keccak256("female-solo"),
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
            bytes32("mma-2025"),
            keccak256("winner-vote"),
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

    function testFrontendCanReadConfigAndSharedSeriesIdAfterOrganizerSetup() public {
        // 실제 사례 :
        // 1) organizer가 "MAMA 2025" series 아래 "female solo" election을 만든다
        // 2) 프론트는 getElectionConfig를 읽어서 shared seriesId와 category titleHash를 함께 가져간다
        bytes32 mamaSeriesId = bytes32("mama-2025");
        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            mamaSeriesId,
            keccak256("female-solo"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            25_001
        );

        vm.prank(organizer);
        address electionAddress = electionFactory.createElection(config);

        VESTArElection election = VESTArElection(electionAddress);

        bytes32 iuHash = keccak256(bytes("IU"));

        bytes32[] memory candidateHashes = new bytes32[](1);
        candidateHashes[0] = iuHash;

        vm.prank(organizer);
        election.setCandidateAllowlist(candidateHashes, true);

        VESTArTypes.ElectionConfig memory storedConfig = election.getElectionConfig();
        bytes32 expectedElectionId = electionFactory.computeElectionId(
            organizer, config.seriesId, config.titleHash, config.startAt, config.endAt, 0
        );

        assertEq(election.electionId(), expectedElectionId);
        assertEq(storedConfig.seriesId, mamaSeriesId);
        assertEq(storedConfig.titleHash, keccak256("female-solo"));
        assertEq(storedConfig.candidateManifestURI, "ipfs://open-candidates");
        assertTrue(election.isCandidateHashAllowed(iuHash));
    }

    function _buildOpenConfig(
        bytes32 seriesId_,
        bytes32 titleHash_,
        uint64 startAt_,
        uint64 endAt_,
        uint256 costPerBallot_
    ) internal view returns (VESTArTypes.ElectionConfig memory) {
        return VESTArTypes.ElectionConfig({
            seriesId: seriesId_,
            visibilityMode: VESTArTypes.VisibilityMode.OPEN,
            titleHash: titleHash_,
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
        bytes32 seriesId_,
        bytes32 titleHash_,
        uint64 startAt_,
        uint64 endAt_,
        uint64 resultRevealAt_,
        uint256 costPerBallot_,
        bytes32 commitmentHash
    ) internal view returns (VESTArTypes.ElectionConfig memory) {
        return VESTArTypes.ElectionConfig({
            seriesId: seriesId_,
            visibilityMode: VESTArTypes.VisibilityMode.PRIVATE,
            titleHash: titleHash_,
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

    function _resultSummary(string memory resultManifestUri) internal pure returns (VESTArTypes.ResultSummary memory) {
        return VESTArTypes.ResultSummary({
            resultManifestHash: keccak256(bytes(resultManifestUri)),
            resultManifestURI: resultManifestUri,
            totalSubmissions: 1,
            totalValidVotes: 1,
            totalInvalidVotes: 0
        });
    }
}
