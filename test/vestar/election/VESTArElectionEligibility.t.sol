// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArTypes} from "../../../src/libraries/vestar/VESTArTypes.sol";
import {VESTArElectionEligibilityImpl} from "../../../src/vestar/election/modules/VESTArElectionEligibilityImpl.sol";
import {VESTArTestBase} from "../base/VESTArTestBase.sol";

contract VESTArElectionEligibilityHarness is VESTArElectionEligibilityImpl {
    function configureEligibility(
        uint64 startAt_,
        uint64 endAt_,
        uint64 resultRevealAt_,
        VESTArTypes.BallotPolicy ballotPolicy_,
        uint64 resetInterval_,
        uint8 minKarmaTier_,
        address karmaRegistryAddress,
        bool unlimitedMode
    ) external {
        _config.startAt = startAt_;
        _config.endAt = endAt_;
        _config.resultRevealAt = resultRevealAt_;
        _config.ballotPolicy = ballotPolicy_;
        _config.resetInterval = resetInterval_;
        _config.minKarmaTier = minKarmaTier_;
        _config.visibilityMode = VESTArTypes.VisibilityMode.OPEN;
        _config.allowMultipleChoice = false;
        _config.maxSelectionsPerSubmission = 1;
        _config.paymentMode = unlimitedMode ? VESTArTypes.PaymentMode.PAID : VESTArTypes.PaymentMode.FREE;
        _config.costPerBallot = unlimitedMode ? 66_000 : 0;
        _config.paymentToken = unlimitedMode ? address(0x9999) : address(0);
        _karmaRegistry = karmaRegistryAddress;
    }

    function setSubmittedBallots(address voterAddress, uint48 periodKey, uint32 submittedBallots) external {
        _submittedBallotsByPeriod[voterAddress][periodKey] = submittedBallots;
    }
}

// election eligibility 모듈 테스트 자리
// eligibility 테스트는 period 계산, ballot 1회 제한, karma tier 판정의 경계값이 중요
contract VESTArElectionEligibilityTest is VESTArTestBase {
    VESTArElectionEligibilityHarness internal eligibilityHarness;

    function setUp() public {
        _deployCommonMocks();
        eligibilityHarness = new VESTArElectionEligibilityHarness();
    }

    function testCurrentPeriodKeyUsesResetIntervalFromElectionStart() public {
        // 실제 사례 : 1일마다 ballot 1개가 리셋되는 7일짜리 투표라면,
        // 시작 후 2일 1시간 시점은 세 번째 단위 기간(periodKey = 2)에 해당
        eligibilityHarness.configureEligibility(
            0, 7 days, 7 days, VESTArTypes.BallotPolicy.ONE_PER_INTERVAL, 1 days, 0, address(mockKarmaRegistry), false
        );

        assertEq(eligibilityHarness.currentPeriodKey(uint64(2 days + 1 hours)), 2);
    }

    function testRemainingBallotsIsOneBeforeFirstSubmission() public {
        eligibilityHarness.configureEligibility(
            0, 7 days, 7 days, VESTArTypes.BallotPolicy.ONE_PER_INTERVAL, 1 days, 1, address(mockKarmaRegistry), false
        );
        mockKarmaRegistry.setTier(voter, 1);

        assertEq(eligibilityHarness.remainingBallots(voter, uint64(3 hours)), 1);
    }

    function testRemainingBallotsBecomesZeroAfterOneSubmissionInSamePeriod() public {
        eligibilityHarness.configureEligibility(
            0, 7 days, 7 days, VESTArTypes.BallotPolicy.ONE_PER_INTERVAL, 1 days, 1, address(mockKarmaRegistry), false
        );
        mockKarmaRegistry.setTier(voter, 1);
        eligibilityHarness.setSubmittedBallots(voter, 0, 1);

        VESTArTypes.BallotUsage memory usage = eligibilityHarness.ballotUsageOf(voter, 0);

        assertEq(usage.submittedBallots, 1);
        assertEq(usage.remainingBallots, 0);
    }

    function testUnlimitedModeReturnsInfiniteRemainingBallots() public {
        // 실제 사례 : UNLIMITED_PAID 정책에서는 periodKey 0 하나를 쓰더라도 남은 ballot을 무한대로 취급
        eligibilityHarness.configureEligibility(
            0, 1 days, 1 days, VESTArTypes.BallotPolicy.UNLIMITED_PAID, 0, 1, address(mockKarmaRegistry), true
        );
        mockKarmaRegistry.setTier(voter, 1);

        VESTArTypes.BallotUsage memory usage = eligibilityHarness.ballotUsageOf(voter, 0);

        assertTrue(usage.isUnlimited);
        assertEq(usage.remainingBallots, type(uint32).max);
    }

    function testCanSubmitBallotReturnsFalseWhenKarmaTierTooLow() public {
        eligibilityHarness.configureEligibility(
            0, 7 days, 7 days, VESTArTypes.BallotPolicy.ONE_PER_INTERVAL, 1 days, 2, address(mockKarmaRegistry), false
        );
        mockKarmaRegistry.setTier(voter, 1);

        assertFalse(eligibilityHarness.canSubmitBallot(voter, uint64(1 hours)));
    }

    function testOnePerElectionUsesSingleGlobalPeriodKey() public {
        // 실제 사례 : "이 선거 전체에서 계정당 1번만" 정책이면 1일차든 6일차든 항상 같은 periodKey 0으로 본다
        eligibilityHarness.configureEligibility(
            0, 7 days, 7 days, VESTArTypes.BallotPolicy.ONE_PER_ELECTION, 0, 0, address(mockKarmaRegistry), false
        );

        assertEq(eligibilityHarness.currentPeriodKey(uint64(1 hours)), 0);
        assertEq(eligibilityHarness.currentPeriodKey(uint64(6 days)), 0);
    }
}
