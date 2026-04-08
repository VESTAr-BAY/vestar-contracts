// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVESTArOpenVoteModule} from "../../../src/interfaces/vestar/IVESTArOpenVoteModule.sol";
import {VESTArTypes} from "../../../src/libraries/vestar/VESTArTypes.sol";
import {VESTArOpenVoteModuleImpl} from "../../../src/vestar/election/modules/VESTArOpenVoteModuleImpl.sol";
import {VESTArTestBase} from "../base/VESTArTestBase.sol";

contract VESTArOpenVoteHarness is VESTArOpenVoteModuleImpl {
    function configureOpenElection(
        VESTArTypes.BallotPolicy ballotPolicy_,
        bool allowMultipleChoice_,
        uint16 maxSelectionsPerSubmission_,
        uint64 resetInterval_,
        VESTArTypes.PaymentMode paymentMode_,
        uint256 costPerBallot_,
        address paymentToken_,
        uint8 minKarmaTier_,
        address karmaRegistryAddress
    ) external {
        _config.seriesId = bytes32("open-vote-harness");
        _config.visibilityMode = VESTArTypes.VisibilityMode.OPEN;
        _config.startAt = 0;
        _config.endAt = type(uint64).max - 1;
        _config.resultRevealAt = type(uint64).max;
        _config.ballotPolicy = ballotPolicy_;
        _config.allowMultipleChoice = allowMultipleChoice_;
        _config.maxSelectionsPerSubmission = maxSelectionsPerSubmission_;
        _config.resetInterval = resetInterval_;
        _config.paymentMode = paymentMode_;
        _config.costPerBallot = costPerBallot_;
        _config.paymentToken = paymentToken_;
        _config.minKarmaTier = minKarmaTier_;
        _karmaRegistry = karmaRegistryAddress;
    }

    function allowCandidate(string calldata candidateKey) external {
        _allowedCandidateHash[keccak256(bytes(candidateKey))] = true;
    }

    function submittedBallots(address voterAddress, uint48 periodKey) external view returns (uint32) {
        return _submittedBallotsByPeriod[voterAddress][periodKey];
    }

    function totalCollectedAmount() external view returns (uint256) {
        return _totalCollectedAmount;
    }

    function trackedRefundableAmount(address voterAddress) external view returns (uint256) {
        return _refundableAmountByVoter[voterAddress];
    }
}

// OpenVote 모듈 테스트 자리
// open vote 테스트는 후보 검증, 중복 선택 차단, ballot 단위 과금, tally 증가가 핵심
contract VESTArOpenVoteTest is VESTArTestBase {
    VESTArOpenVoteHarness internal openVoteHarness;

    function setUp() public {
        _deployCommonMocks();
        openVoteHarness = new VESTArOpenVoteHarness();
    }

    function testSubmitOpenVoteChargesOneBallotEvenForMultipleChoices() public {
        // 실제 사례 : 다중 선택 최대 3개, ballot 1개 가격 0.066 mockUSDT인 paid election
        // ["IU", "ParkHyoShin", "Naul"]을 보내도 3배가 아니라 ballot 1개 가격만 결제됨
        openVoteHarness.configureOpenElection(
            VESTArTypes.BallotPolicy.ONE_PER_INTERVAL,
            true,
            3,
            1 days,
            VESTArTypes.PaymentMode.PAID,
            FULL_PRICE_PER_BALLOT,
            address(mockUSDT),
            1,
            address(mockKarmaRegistry)
        );
        openVoteHarness.allowCandidate("IU");
        openVoteHarness.allowCandidate("ParkHyoShin");
        openVoteHarness.allowCandidate("Naul");

        mockKarmaRegistry.setTier(voter, 1);
        mockUSDT.mint(voter, FULL_PRICE_PER_BALLOT);

        string[] memory selections = new string[](3);
        selections[0] = "IU";
        selections[1] = "ParkHyoShin";
        selections[2] = "Naul";

        vm.startPrank(voter);
        mockUSDT.approve(address(openVoteHarness), FULL_PRICE_PER_BALLOT);
        openVoteHarness.submitOpenVote(selections);
        vm.stopPrank();

        assertEq(openVoteHarness.submittedBallots(voter, 0), 1);
        assertEq(openVoteHarness.totalCollectedAmount(), FULL_PRICE_PER_BALLOT);
        assertEq(openVoteHarness.trackedRefundableAmount(voter), FULL_PRICE_PER_BALLOT);
        assertEq(openVoteHarness.totalVotesForCandidate("IU"), 1);
        assertEq(openVoteHarness.totalVotesForCandidate("ParkHyoShin"), 1);
        assertEq(openVoteHarness.totalVotesForCandidate("Naul"), 1);
    }

    function testSubmitOpenVoteEmitsBackendFriendlyEventPayload() public {
        // 실제 사례 : 백엔드는 이 이벤트를 받아 "누가, 몇 후보를, 얼마를 내고 ballot 1개를 제출했는지" 즉시 인덱싱 가능
        openVoteHarness.configureOpenElection(
            VESTArTypes.BallotPolicy.ONE_PER_INTERVAL,
            true,
            3,
            1 days,
            VESTArTypes.PaymentMode.PAID,
            FULL_PRICE_PER_BALLOT,
            address(mockUSDT),
            1,
            address(mockKarmaRegistry)
        );
        openVoteHarness.allowCandidate("IU");
        openVoteHarness.allowCandidate("ParkHyoShin");
        mockKarmaRegistry.setTier(voter, 1);
        mockUSDT.mint(voter, FULL_PRICE_PER_BALLOT);

        string[] memory selections = new string[](2);
        selections[0] = "IU";
        selections[1] = "ParkHyoShin";

        bytes32 expectedBatchHash = keccak256(abi.encode(selections));

        vm.startPrank(voter);
        mockUSDT.approve(address(openVoteHarness), FULL_PRICE_PER_BALLOT);
        vm.expectEmit(true, true, false, true);
        emit IVESTArOpenVoteModule.OpenVoteSubmitted(bytes32(0), voter, 2, expectedBatchHash, 1, FULL_PRICE_PER_BALLOT);
        openVoteHarness.submitOpenVote(selections);
        vm.stopPrank();
    }

    function testSubmitOpenVoteRevertsOnDuplicateSelections() public {
        // 실제 사례 : OPEN 모드에서는 plaintext가 보이므로 ["IU", "IU"] 같은 중복은 제출 즉시 revert
        openVoteHarness.configureOpenElection(
            VESTArTypes.BallotPolicy.ONE_PER_INTERVAL,
            true,
            3,
            1 days,
            VESTArTypes.PaymentMode.FREE,
            0,
            address(0),
            0,
            address(mockKarmaRegistry)
        );
        openVoteHarness.allowCandidate("IU");

        string[] memory selections = new string[](2);
        selections[0] = "IU";
        selections[1] = "IU";

        vm.prank(voter);
        vm.expectRevert("VESTAr: duplicate selection");
        openVoteHarness.submitOpenVote(selections);
    }

    function testSubmitOpenVoteRevertsWhenSelectionCountExceedsMaximum() public {
        openVoteHarness.configureOpenElection(
            VESTArTypes.BallotPolicy.ONE_PER_INTERVAL,
            true,
            2,
            1 days,
            VESTArTypes.PaymentMode.FREE,
            0,
            address(0),
            0,
            address(mockKarmaRegistry)
        );
        openVoteHarness.allowCandidate("IU");
        openVoteHarness.allowCandidate("ParkHyoShin");
        openVoteHarness.allowCandidate("Naul");

        string[] memory selections = new string[](3);
        selections[0] = "IU";
        selections[1] = "ParkHyoShin";
        selections[2] = "Naul";

        vm.prank(voter);
        vm.expectRevert("VESTAr: too many selections");
        openVoteHarness.submitOpenVote(selections);
    }

    function testUnlimitedPaidVotingRequiresSingleSelectionPerTransaction() public {
        // 실제 사례 : resetInterval = 0인 유료 무제한 반복 투표는 ["IU"]를 여러 번 보내는 방식만 허용
        // ["IU", "ParkHyoShin"]처럼 한 트랜잭션에 여러 후보를 담는 것은 금지
        openVoteHarness.configureOpenElection(
            VESTArTypes.BallotPolicy.UNLIMITED_PAID,
            false,
            1,
            0,
            VESTArTypes.PaymentMode.PAID,
            FULL_PRICE_PER_BALLOT,
            address(mockUSDT),
            0,
            address(mockKarmaRegistry)
        );
        openVoteHarness.allowCandidate("IU");
        openVoteHarness.allowCandidate("ParkHyoShin");
        mockUSDT.mint(voter, FULL_PRICE_PER_BALLOT);

        string[] memory selections = new string[](2);
        selections[0] = "IU";
        selections[1] = "ParkHyoShin";

        vm.startPrank(voter);
        mockUSDT.approve(address(openVoteHarness), FULL_PRICE_PER_BALLOT);
        vm.expectRevert("VESTAr: single choice only");
        openVoteHarness.submitOpenVote(selections);
        vm.stopPrank();
    }

    function testUserCannotSubmitSecondBallotInSamePeriod() public {
        // 실제 사례 : 하루 1 ballot 규칙인 투표에서 사용자는 같은 날 두 번째 ballot을 보내면 막혀야 함
        openVoteHarness.configureOpenElection(
            VESTArTypes.BallotPolicy.ONE_PER_INTERVAL,
            false,
            1,
            1 days,
            VESTArTypes.PaymentMode.FREE,
            0,
            address(0),
            0,
            address(mockKarmaRegistry)
        );
        openVoteHarness.allowCandidate("IU");

        string[] memory selections = new string[](1);
        selections[0] = "IU";

        vm.prank(voter);
        openVoteHarness.submitOpenVote(selections);

        vm.prank(voter);
        vm.expectRevert("VESTAr: ballot unavailable");
        openVoteHarness.submitOpenVote(selections);
    }

    function testUserCanSubmitAgainInNextPeriod() public {
        // 실제 사례 : daily reset 투표라면 다음 날이 되면 같은 유저가 다시 ballot 1개를 보낼 수 있어야 함
        openVoteHarness.configureOpenElection(
            VESTArTypes.BallotPolicy.ONE_PER_INTERVAL,
            false,
            1,
            1 days,
            VESTArTypes.PaymentMode.FREE,
            0,
            address(0),
            0,
            address(mockKarmaRegistry)
        );
        openVoteHarness.allowCandidate("IU");

        string[] memory selections = new string[](1);
        selections[0] = "IU";

        vm.prank(voter);
        openVoteHarness.submitOpenVote(selections);

        vm.warp(block.timestamp + 1 days);

        vm.prank(voter);
        openVoteHarness.submitOpenVote(selections);

        assertEq(openVoteHarness.totalVotesForCandidate("IU"), 2);
    }

    function testFreeOpenVoteDoesNotNeedTokenApproval() public {
        // 실제 사례 : 무료 투표 이벤트에서는 유저가 approve 없이도 바로 투표 가능해야 프론트 UX가 단순해짐
        openVoteHarness.configureOpenElection(
            VESTArTypes.BallotPolicy.ONE_PER_INTERVAL,
            false,
            1,
            1 days,
            VESTArTypes.PaymentMode.FREE,
            0,
            address(0),
            0,
            address(mockKarmaRegistry)
        );
        openVoteHarness.allowCandidate("IU");

        string[] memory selections = new string[](1);
        selections[0] = "IU";

        vm.prank(voter);
        openVoteHarness.submitOpenVote(selections);

        assertEq(openVoteHarness.totalCollectedAmount(), 0);
        assertEq(openVoteHarness.totalVotesForCandidate("IU"), 1);
    }

    function testOnePerElectionBlocksSecondSubmissionEvenOnNextDay() public {
        // 실제 사례 : 선거 전체에서 계정당 1번만 허용하는 투표라면, 다음 날이 돼도 두 번째 ballot은 막혀야 함
        openVoteHarness.configureOpenElection(
            VESTArTypes.BallotPolicy.ONE_PER_ELECTION,
            false,
            1,
            0,
            VESTArTypes.PaymentMode.FREE,
            0,
            address(0),
            0,
            address(mockKarmaRegistry)
        );
        openVoteHarness.allowCandidate("IU");

        string[] memory selections = new string[](1);
        selections[0] = "IU";

        vm.prank(voter);
        openVoteHarness.submitOpenVote(selections);

        vm.warp(block.timestamp + 1 days);

        vm.prank(voter);
        vm.expectRevert("VESTAr: ballot unavailable");
        openVoteHarness.submitOpenVote(selections);
    }
}
