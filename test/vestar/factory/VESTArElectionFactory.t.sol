// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArTypes} from "../../../src/libraries/vestar/VESTArTypes.sol";
import {VESTArElection} from "../../../src/vestar/election/VESTArElection.sol";
import {VESTArElectionFactory} from "../../../src/vestar/factory/VESTArElectionFactory.sol";
import {VESTArOrganizerRegistry} from "../../../src/vestar/registry/VESTArOrganizerRegistry.sol";
import {VESTArTestBase} from "../base/VESTArTestBase.sol";

// ElectionFactory 구현체 테스트 자리
// factory 테스트는 "생성 후 무엇이 연결됐는가"를 확인하는 wiring 검증이 핵심
contract VESTArElectionFactoryTest is VESTArTestBase {
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
    }

    function testVerifiedOrganizerCanCreateElectionWithZeroKarma() public {
        vm.prank(platformAdmin);
        organizerRegistry.setVerification(organizer, true, 100, 0);

        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            bytes32("verified-series"), keccak256("factory-open-vote"), VESTArTypes.PaymentMode.PAID, 25_000
        );

        bytes32 expectedElectionId = electionFactory.previewNextElectionId(
            organizer, config.seriesId, config.titleHash, config.startAt, config.endAt
        );

        vm.prank(organizer);
        address electionAddress = electionFactory.createElection(config);

        VESTArElection election = VESTArElection(electionAddress);

        assertEq(electionFactory.getElection(expectedElectionId), electionAddress);
        assertEq(election.electionId(), expectedElectionId);
        assertEq(election.seriesId(), config.seriesId);
        assertEq(election.organizer(), organizer);
        assertEq(election.platformAdmin(), platformAdmin);
        assertTrue(election.organizerVerifiedSnapshot());
        assertEq(uint256(election.paymentMode()), uint256(VESTArTypes.PaymentMode.PAID));
        assertEq(election.costPerBallot(), 25_000);
        assertEq(election.platformTreasury(), platformTreasury);
    }

    function testUnverifiedOrganizerWithZeroKarmaCannotCreateElection() public {
        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            bytes32("unverified-series"), keccak256("factory-open-vote"), VESTArTypes.PaymentMode.FREE, 0
        );

        vm.prank(organizer);
        vm.expectRevert("VESTAr: organizer not eligible");
        electionFactory.createElection(config);
    }

    function testUnverifiedOrganizerWithEntryKarmaCanCreateElection() public {
        // 실제 사례 : verified가 아니더라도 카르마 티어 1 이상이면 organizer 생성 허용
        mockKarmaRegistry.setTier(organizer, 1);

        VESTArTypes.ElectionConfig memory config =
            _buildOpenConfig(bytes32("karma-series"), keccak256("factory-open-vote"), VESTArTypes.PaymentMode.FREE, 0);

        vm.prank(organizer);
        address electionAddress = electionFactory.createElection(config);

        VESTArElection election = VESTArElection(electionAddress);

        assertFalse(election.organizerVerifiedSnapshot());
        assertEq(election.seriesId(), config.seriesId);
        assertEq(election.organizer(), organizer);
    }

    function testVerifiedSnapshotRemainsTrueEvenAfterRegistryRevocation() public {
        // 실제 사례 : 투표 생성 당시에는 공식 주최자였지만, 나중에 인증이 해제되더라도
        // 해당 election의 verified snapshot은 생성 시점 기록으로 유지되어야 함
        vm.prank(platformAdmin);
        organizerRegistry.setVerification(organizer, true, 100, 0);

        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            bytes32("snapshot-series"), keccak256("factory-open-vote"), VESTArTypes.PaymentMode.FREE, 0
        );

        vm.prank(organizer);
        address electionAddress = electionFactory.createElection(config);

        vm.prank(platformAdmin);
        organizerRegistry.setVerification(organizer, false, 0, 200);

        VESTArElection election = VESTArElection(electionAddress);

        assertFalse(organizerRegistry.isVerified(organizer));
        assertTrue(election.organizerVerifiedSnapshot());
    }

    function testFactoryTracksMultipleElectionsUnderSameSeries() public {
        vm.prank(platformAdmin);
        organizerRegistry.setVerification(organizer, true, 100, 0);

        bytes32 mamaSeriesId = bytes32("mama-2025");

        VESTArTypes.ElectionConfig memory femaleSoloConfig =
            _buildOpenConfig(mamaSeriesId, keccak256("female-solo"), VESTArTypes.PaymentMode.FREE, 0);

        VESTArTypes.ElectionConfig memory maleSoloConfig =
            _buildOpenConfig(mamaSeriesId, keccak256("male-solo"), VESTArTypes.PaymentMode.FREE, 0);

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
    }

    function testFactoryGeneratesUniqueElectionIdsForRepeatedConfig() public {
        vm.prank(platformAdmin);
        organizerRegistry.setVerification(organizer, true, 100, 0);

        VESTArTypes.ElectionConfig memory config =
            _buildOpenConfig(bytes32("repeat-series"), keccak256("repeat-title"), VESTArTypes.PaymentMode.FREE, 0);

        bytes32 expectedFirstElectionId = electionFactory.previewNextElectionId(
            organizer, config.seriesId, config.titleHash, config.startAt, config.endAt
        );
        bytes32 expectedSecondElectionId = electionFactory.computeElectionId(
            organizer, config.seriesId, config.titleHash, config.startAt, config.endAt, 1
        );

        vm.startPrank(organizer);
        address firstElectionAddress = electionFactory.createElection(config);
        address secondElectionAddress = electionFactory.createElection(config);
        vm.stopPrank();

        assertTrue(expectedFirstElectionId != expectedSecondElectionId);
        assertEq(electionFactory.getElection(expectedFirstElectionId), firstElectionAddress);
        assertEq(electionFactory.getElection(expectedSecondElectionId), secondElectionAddress);
        assertEq(electionFactory.nextElectionNonce(organizer), 2);
    }

    function _buildOpenConfig(
        bytes32 seriesId_,
        bytes32 titleHash_,
        VESTArTypes.PaymentMode paymentMode_,
        uint256 costPerBallot_
    ) internal view returns (VESTArTypes.ElectionConfig memory) {
        address paymentToken = paymentMode_ == VESTArTypes.PaymentMode.PAID ? address(mockUSDT) : address(0);

        return VESTArTypes.ElectionConfig({
            seriesId: seriesId_,
            visibilityMode: VESTArTypes.VisibilityMode.OPEN,
            titleHash: titleHash_,
            candidateManifestHash: keccak256("factory-candidates"),
            candidateManifestURI: "ipfs://factory-candidates",
            startAt: uint64(block.timestamp + 1 days),
            endAt: uint64(block.timestamp + 8 days),
            resultRevealAt: uint64(block.timestamp + 8 days),
            minKarmaTier: 0,
            ballotPolicy: VESTArTypes.BallotPolicy.ONE_PER_INTERVAL,
            resetInterval: 1 days,
            paymentMode: paymentMode_,
            costPerBallot: costPerBallot_,
            allowMultipleChoice: true,
            maxSelectionsPerSubmission: 3,
            timezoneWindowOffset: 0,
            paymentToken: paymentToken,
            electionPublicKey: "",
            privateKeyCommitmentHash: bytes32(0),
            keySchemeVersion: 0
        });
    }
}
