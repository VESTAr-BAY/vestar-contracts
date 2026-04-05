// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArTypes} from "../../../src/libraries/vestar/VESTArTypes.sol";
import {VESTArElection} from "../../../src/vestar/election/VESTArElection.sol";
import {VESTArTestBase} from "../base/VESTArTestBase.sol";

// election lifecycle 모듈 테스트 자리
// lifecycle 테스트는 시간 변화(warp)와 상태 전이 순서를 검증하는 패턴이 자주 나옴
contract VESTArElectionLifecycleTest is VESTArTestBase {
    VESTArElection internal election;

    function setUp() public {
        _deployCommonMocks();
        election = new VESTArElection(platformAdmin);
    }

    function testScheduledToActiveStateTransitionFollowsTime() public {
        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            bytes32("open-lifecycle"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 3 days)
        );

        election.initialize(config, organizer, false, address(mockKarmaRegistry), platformAdmin, platformTreasury);

        assertEq(uint256(election.state()), uint256(VESTArTypes.ElectionState.Scheduled));

        vm.warp(block.timestamp + 1 days);
        election.syncState();

        assertEq(uint256(election.state()), uint256(VESTArTypes.ElectionState.Active));
    }

    function testOrganizerCanCancelBeforeStart() public {
        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            bytes32("cancel-before-start"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days)
        );

        election.initialize(config, organizer, false, address(mockKarmaRegistry), platformAdmin, platformTreasury);

        vm.prank(organizer);
        election.cancelBeforeStart();

        assertEq(uint256(election.state()), uint256(VESTArTypes.ElectionState.Cancelled));
    }

    function testRevealManagerCanRevealPrivateKeyAfterRevealTime() public {
        vm.warp(10 days);

        bytes memory privateKeyData = hex"1234abcd";
        VESTArTypes.ElectionConfig memory config = _buildPrivateConfig(
            bytes32("private-lifecycle"),
            uint64(block.timestamp - 2 days),
            uint64(block.timestamp - 1 days),
            uint64(block.timestamp - 1 hours),
            keccak256(privateKeyData)
        );

        election.initialize(config, organizer, true, address(mockKarmaRegistry), platformAdmin, platformTreasury);

        vm.prank(platformAdmin);
        election.setRevealManager(revealManager, true);

        vm.prank(revealManager);
        election.revealPrivateKey(privateKeyData);

        assertEq(uint256(election.state()), uint256(VESTArTypes.ElectionState.KeyRevealed));
        assertEq(election.revealedPrivateKey(), privateKeyData);
    }

    function testRevealPrivateKeyRevertsWhenBackendSendsWrongKey() public {
        // 실제 사례 : 백엔드가 보관하던 private key와 다른 값을 실수로 보내면
        // commitment hash가 안 맞아야 하고, 잘못된 key 공개는 즉시 막혀야 함
        vm.warp(10 days);

        bytes memory committedPrivateKey = hex"1234abcd";
        bytes memory wrongPrivateKey = hex"9999eeee";
        VESTArTypes.ElectionConfig memory config = _buildPrivateConfig(
            bytes32("private-mismatch"),
            uint64(block.timestamp - 2 days),
            uint64(block.timestamp - 1 days),
            uint64(block.timestamp - 1 hours),
            keccak256(committedPrivateKey)
        );

        election.initialize(config, organizer, true, address(mockKarmaRegistry), platformAdmin, platformTreasury);

        vm.prank(platformAdmin);
        election.setRevealManager(revealManager, true);

        vm.prank(revealManager);
        vm.expectRevert("VESTAr: commitment mismatch");
        election.revealPrivateKey(wrongPrivateKey);
    }

    function testOnlyPlatformAdminCanAssignRevealManager() public {
        VESTArTypes.ElectionConfig memory config = _buildPrivateConfig(
            bytes32("private-admin"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            uint64(block.timestamp + 3 days),
            keccak256(hex"1234")
        );

        election.initialize(config, organizer, true, address(mockKarmaRegistry), platformAdmin, platformTreasury);

        vm.prank(organizer);
        vm.expectRevert("VESTAr: only platform admin");
        election.setRevealManager(revealManager, true);
    }

    function testCannotFinalizePrivateResultsBeforeKeyReveal() public {
        vm.warp(10 days);

        VESTArTypes.ElectionConfig memory config = _buildPrivateConfig(
            bytes32("private-finalize"),
            uint64(block.timestamp - 2 days),
            uint64(block.timestamp - 1 days),
            uint64(block.timestamp - 1 hours),
            keccak256(hex"1234")
        );

        election.initialize(config, organizer, true, address(mockKarmaRegistry), platformAdmin, platformTreasury);

        vm.prank(organizer);
        vm.expectRevert("VESTAr: reveal first");
        election.finalizeResults(
            VESTArTypes.ResultSummary({
                resultManifestHash: keccak256("private-results"),
                resultManifestURI: "ipfs://private-results",
                totalSubmissions: 1,
                totalValidVotes: 1,
                totalInvalidVotes: 0
            })
        );
    }

    function testOrganizerCannotEditCandidateAllowlistAfterStart() public {
        // 실제 사례 : organizer는 시작 전까지만 후보 목록을 확정하고,
        // 투표가 열린 뒤에는 프론트/백 기준점이 흔들리지 않도록 수정이 막혀야 함
        VESTArTypes.ElectionConfig memory config = _buildOpenConfig(
            bytes32("allowlist-lock"),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 3 days)
        );

        election.initialize(config, organizer, false, address(mockKarmaRegistry), platformAdmin, platformTreasury);

        vm.warp(block.timestamp + 1 days);

        bytes32[] memory candidateHashes = new bytes32[](1);
        candidateHashes[0] = keccak256(bytes("IU"));

        vm.prank(organizer);
        vm.expectRevert("VESTAr: already started");
        election.setCandidateAllowlist(candidateHashes, true);
    }

    function _buildOpenConfig(bytes32 electionId_, uint64 startAt_, uint64 endAt_)
        internal
        view
        returns (VESTArTypes.ElectionConfig memory)
    {
        return VESTArTypes.ElectionConfig({
            electionId: electionId_,
            visibilityMode: VESTArTypes.VisibilityMode.OPEN,
            titleHash: keccak256("Lifecycle Open Vote"),
            candidateManifestHash: keccak256("candidates"),
            candidateManifestURI: "ipfs://candidates",
            startAt: startAt_,
            endAt: endAt_,
            resultRevealAt: endAt_,
            minKarmaTier: 0,
            ballotPolicy: VESTArTypes.BallotPolicy.ONE_PER_INTERVAL,
            resetInterval: 1 days,
            paymentMode: VESTArTypes.PaymentMode.FREE,
            costPerBallot: 0,
            allowMultipleChoice: false,
            maxSelectionsPerSubmission: 1,
            timezoneWindowOffset: 0,
            paymentToken: address(0),
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
        bytes32 commitmentHash
    ) internal view returns (VESTArTypes.ElectionConfig memory) {
        return VESTArTypes.ElectionConfig({
            electionId: electionId_,
            visibilityMode: VESTArTypes.VisibilityMode.PRIVATE,
            titleHash: keccak256("Lifecycle Private Vote"),
            candidateManifestHash: keccak256("private-candidates"),
            candidateManifestURI: "ipfs://private-candidates",
            startAt: startAt_,
            endAt: endAt_,
            resultRevealAt: resultRevealAt_,
            minKarmaTier: 0,
            ballotPolicy: VESTArTypes.BallotPolicy.ONE_PER_INTERVAL,
            resetInterval: 1 days,
            paymentMode: VESTArTypes.PaymentMode.FREE,
            costPerBallot: 0,
            allowMultipleChoice: false,
            maxSelectionsPerSubmission: 1,
            timezoneWindowOffset: 0,
            paymentToken: address(0),
            electionPublicKey: hex"cafe",
            privateKeyCommitmentHash: commitmentHash,
            keySchemeVersion: 1
        });
    }
}
