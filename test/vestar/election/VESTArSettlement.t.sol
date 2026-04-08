// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArTypes} from "../../../src/libraries/vestar/VESTArTypes.sol";
import {VESTArSettlementModuleImpl} from "../../../src/vestar/election/modules/VESTArSettlementModuleImpl.sol";
import {VESTArTestBase} from "../base/VESTArTestBase.sol";

// Settlement 모듈 테스트 자리
// settlement 테스트는 금액 계산, 반반 분배, 중복 정산 방지 같은 money invariant가 중요
contract VESTArSettlementModuleHarness is VESTArSettlementModuleImpl {
    function configureSettlement(
        VESTArTypes.PaymentMode paymentMode_,
        uint256 costPerBallot_,
        address paymentToken_,
        address platformTreasury_,
        address organizerAddress,
        address platformAdminAddress
    ) external {
        _config.seriesId = bytes32("settlement-harness");
        _config.startAt = 0;
        _config.endAt = 1;
        _config.resultRevealAt = 1;
        _config.ballotPolicy = VESTArTypes.BallotPolicy.ONE_PER_INTERVAL;
        _config.resetInterval = 1 days;
        _config.allowMultipleChoice = false;
        _config.maxSelectionsPerSubmission = 1;
        _config.paymentMode = paymentMode_;
        _config.costPerBallot = costPerBallot_;
        _config.paymentToken = paymentToken_;
        _settlementSummary.platformTreasury = platformTreasury_;
        _organizer = organizerAddress;
        _platformAdmin = platformAdminAddress;
    }

    function setTotalCollectedAmount(uint256 newTotalCollectedAmount) external {
        _totalCollectedAmount = newTotalCollectedAmount;
    }

    function setSettlementSummary(VESTArTypes.SettlementSummary memory newSettlementSummary) external {
        _settlementSummary = newSettlementSummary;
    }

    function setRefundSummary(VESTArTypes.RefundSummary memory newRefundSummary) external {
        _refundSummary = newRefundSummary;
    }

    function setRefundableAmount(address voterAddress, uint256 newRefundableAmount) external {
        _refundableAmountByVoter[voterAddress] = newRefundableAmount;
    }

    // internal helper를 external로 감싸면 계산 규칙을 isolate해서 테스트 가능
    function previewSettlementSplit(uint256 totalRevenueAmount)
        external
        pure
        returns (uint256 platformRevenueAmount, uint256 organizerRevenueAmount)
    {
        return _previewSettlementSplit(totalRevenueAmount);
    }

    function setElectionState(VESTArTypes.ElectionState newState) external {
        _state = newState;
    }
}

contract VESTArSettlementTest is VESTArTestBase {
    VESTArSettlementModuleHarness internal settlementHarness;

    function setUp() public {
        _deployCommonMocks();
        settlementHarness = new VESTArSettlementModuleHarness();
    }

    function testPaymentModeAndCostPerBallotReturnConfiguredValues() public {
        // 실제 사례 : 유료 election에서 ballot 1개 가격을 0.025 mockUSDT로 잡아두는 경우
        settlementHarness.configureSettlement(
            VESTArTypes.PaymentMode.PAID, 25_000, address(mockUSDT), platformTreasury, organizer, platformAdmin
        );

        assertEq(uint256(settlementHarness.paymentMode()), uint256(VESTArTypes.PaymentMode.PAID));
        assertEq(settlementHarness.costPerBallot(), 25_000);
        assertEq(settlementHarness.paymentToken(), address(mockUSDT));
    }

    function testQuotePaymentMultipliesBallotCountByCostPerBallot() public {
        // 실제 사례 : ballot 1개 가격이 0.025 mockUSDT면 7개 ballot 제출 예정 금액은 0.175 mockUSDT
        settlementHarness.configureSettlement(
            VESTArTypes.PaymentMode.PAID, 25_000, address(mockUSDT), platformTreasury, organizer, platformAdmin
        );

        assertEq(settlementHarness.quotePayment(7), 175_000);
    }

    function testQuotePaymentReturnsZeroWhenElectionIsFree() public {
        // 실제 사례 : 고객 요청으로 무료 이벤트를 열면 ballot 수와 상관없이 요구 결제 금액은 0
        settlementHarness.configureSettlement(
            VESTArTypes.PaymentMode.FREE, 0, address(0), platformTreasury, organizer, platformAdmin
        );

        assertEq(settlementHarness.quotePayment(9), 0);
    }

    function testPlatformTreasuryReturnsStoredAddress() public {
        // 실제 사례 : 플랫폼 multisig 또는 treasury 주소를 정산 수취 주소로 저장
        settlementHarness.configureSettlement(
            VESTArTypes.PaymentMode.PAID, 25_000, address(mockUSDT), platformTreasury, organizer, platformAdmin
        );

        assertEq(settlementHarness.platformTreasury(), platformTreasury);
    }

    function testShareBpsAreConfiguredAsFiftyFifty() public view {
        // v1 비즈니스 규칙: 총 수익을 플랫폼 50%, organizer 50%로 나눔
        // basis points 기준으로는 5000 / 5000
        assertEq(settlementHarness.platformShareBps(), 5_000);
        assertEq(settlementHarness.organizerShareBps(), 5_000);
    }

    // 홀수 wei를 테스트하는 이유는 나눗셈 내림(floor) 때문에 1 wei 잔차 처리를 확인해야 하기 때문
    function testPreviewSettlementSplitGivesOddRemainderToOrganizer() public view {
        // 실제 사례 : 총수익 101이면 플랫폼 50, organizer 51로 나눠서 organizer가 잔차 1을 가져감
        (uint256 platformRevenueAmount, uint256 organizerRevenueAmount) = settlementHarness.previewSettlementSplit(101);

        assertEq(platformRevenueAmount, 50);
        assertEq(organizerRevenueAmount, 51);
        assertEq(platformRevenueAmount + organizerRevenueAmount, 101);
    }

    function testTotalCollectedAmountReturnsStoredValue() public {
        // 실제 사례 : 여러 유저가 ballot 결제를 해서 3.000000 mockUSDT가 누적된 상태
        settlementHarness.setTotalCollectedAmount(3_000_000);

        assertEq(settlementHarness.totalCollectedAmount(), 3_000_000);
    }

    function testGetSettlementSummaryReturnsStoredStruct() public {
        // 실제 사례 : 유료 election 종료 후 총 10.000000 mockUSDT를 정산 완료한 상태
        VESTArTypes.SettlementSummary memory expectedSummary = VESTArTypes.SettlementSummary({
            paymentToken: address(mockUSDT),
            platformTreasury: platformTreasury,
            totalRevenueAmount: 10_000_000,
            platformRevenueAmount: 5_000_000,
            organizerRevenueAmount: 5_000_000,
            settled: true
        });

        settlementHarness.setSettlementSummary(expectedSummary);

        VESTArTypes.SettlementSummary memory actualSummary = settlementHarness.getSettlementSummary();

        assertEq(actualSummary.paymentToken, expectedSummary.paymentToken);
        assertEq(actualSummary.platformTreasury, expectedSummary.platformTreasury);
        assertEq(actualSummary.totalRevenueAmount, expectedSummary.totalRevenueAmount);
        assertEq(actualSummary.platformRevenueAmount, expectedSummary.platformRevenueAmount);
        assertEq(actualSummary.organizerRevenueAmount, expectedSummary.organizerRevenueAmount);
        assertEq(actualSummary.settled, expectedSummary.settled);
    }

    function testSettleRevenueTransfersHalfToPlatformAndOddRemainderToOrganizer() public {
        settlementHarness.configureSettlement(
            VESTArTypes.PaymentMode.PAID, 25_000, address(mockUSDT), platformTreasury, organizer, platformAdmin
        );
        settlementHarness.setElectionState(VESTArTypes.ElectionState.Finalized);
        settlementHarness.setTotalCollectedAmount(101);

        // 실제 사례 : 정산 전에 election 컨트랙트가 이미 ballot 결제 토큰 101개를 보유하고 있음
        mockUSDT.mint(address(settlementHarness), 101);

        vm.prank(platformAdmin);
        settlementHarness.settleRevenue();

        assertEq(mockUSDT.balanceOf(platformTreasury), 50);
        assertEq(mockUSDT.balanceOf(organizer), 51);

        VESTArTypes.SettlementSummary memory actualSummary = settlementHarness.getSettlementSummary();
        assertEq(actualSummary.totalRevenueAmount, 101);
        assertEq(actualSummary.platformRevenueAmount, 50);
        assertEq(actualSummary.organizerRevenueAmount, 51);
        assertTrue(actualSummary.settled);
    }

    function testOrganizerCanAlsoSettleRevenueAfterFinalize() public {
        // 실제 사례 : 주최자가 운영 대시보드에서 직접 정산 버튼을 눌러도 정상적으로 분배돼야 함
        settlementHarness.configureSettlement(
            VESTArTypes.PaymentMode.PAID, 25_000, address(mockUSDT), platformTreasury, organizer, platformAdmin
        );
        settlementHarness.setElectionState(VESTArTypes.ElectionState.Finalized);
        settlementHarness.setTotalCollectedAmount(200);
        mockUSDT.mint(address(settlementHarness), 200);

        vm.prank(organizer);
        settlementHarness.settleRevenue();

        assertEq(mockUSDT.balanceOf(platformTreasury), 100);
        assertEq(mockUSDT.balanceOf(organizer), 100);
        assertTrue(settlementHarness.getSettlementSummary().settled);
    }

    function testEnableRefundsStoresSnapshotForClaimBasedRefundFlow() public {
        settlementHarness.configureSettlement(
            VESTArTypes.PaymentMode.PAID, 25_000, address(mockUSDT), platformTreasury, organizer, platformAdmin
        );
        settlementHarness.setElectionState(VESTArTypes.ElectionState.Closed);
        settlementHarness.setTotalCollectedAmount(200);

        vm.prank(organizer);
        settlementHarness.enableRefunds();

        VESTArTypes.RefundSummary memory refundSummary = settlementHarness.getRefundSummary();
        assertEq(refundSummary.paymentToken, address(mockUSDT));
        assertEq(refundSummary.totalRefundableAmount, 200);
        assertEq(refundSummary.totalRefundedAmount, 0);
        assertEq(refundSummary.refundsEnabledBy, organizer);
        assertTrue(refundSummary.refundsEnabled);
        assertTrue(settlementHarness.refundsEnabled());
    }

    function testClaimRefundLetsVoterPullOwnPaidAmount() public {
        settlementHarness.configureSettlement(
            VESTArTypes.PaymentMode.PAID, 25_000, address(mockUSDT), platformTreasury, organizer, platformAdmin
        );
        settlementHarness.setElectionState(VESTArTypes.ElectionState.Closed);
        settlementHarness.setTotalCollectedAmount(200);
        settlementHarness.setRefundableAmount(voter, 120);
        settlementHarness.setRefundableAmount(revealManager, 80);
        mockUSDT.mint(address(settlementHarness), 200);

        vm.prank(platformAdmin);
        settlementHarness.enableRefunds();

        assertEq(settlementHarness.refundableAmountOf(voter), 120);

        vm.prank(voter);
        uint256 refundedAmount = settlementHarness.claimRefund();

        assertEq(refundedAmount, 120);
        assertEq(mockUSDT.balanceOf(voter), 120);
        assertEq(settlementHarness.refundableAmountOf(voter), 0);
        assertEq(settlementHarness.refundableAmountOf(revealManager), 80);
        assertEq(settlementHarness.getRefundSummary().totalRefundedAmount, 120);
    }

    function testClaimRefundRevertsWhenRefundModeIsDisabled() public {
        settlementHarness.configureSettlement(
            VESTArTypes.PaymentMode.PAID, 25_000, address(mockUSDT), platformTreasury, organizer, platformAdmin
        );
        settlementHarness.setRefundableAmount(voter, 25_000);

        vm.prank(voter);
        vm.expectRevert("VESTAr: refunds disabled");
        settlementHarness.claimRefund();
    }

    function testEnableRefundsBlocksLaterSettlement() public {
        settlementHarness.configureSettlement(
            VESTArTypes.PaymentMode.PAID, 25_000, address(mockUSDT), platformTreasury, organizer, platformAdmin
        );
        settlementHarness.setElectionState(VESTArTypes.ElectionState.Finalized);
        settlementHarness.setTotalCollectedAmount(200);

        vm.prank(platformAdmin);
        settlementHarness.enableRefunds();

        mockUSDT.mint(address(settlementHarness), 200);

        vm.prank(platformAdmin);
        vm.expectRevert("VESTAr: refunds enabled");
        settlementHarness.settleRevenue();
    }

    function testRandomUserCannotEnableRefunds() public {
        settlementHarness.configureSettlement(
            VESTArTypes.PaymentMode.PAID, 25_000, address(mockUSDT), platformTreasury, organizer, platformAdmin
        );
        settlementHarness.setElectionState(VESTArTypes.ElectionState.Closed);
        settlementHarness.setTotalCollectedAmount(100);

        vm.prank(voter);
        vm.expectRevert("VESTAr: only admin or organizer");
        settlementHarness.enableRefunds();
    }

    function testRandomUserCannotSettleRevenue() public {
        // 실제 사례 : 유저는 결과를 구경할 수는 있어도, organizer/플랫폼 대신 정산 버튼을 누를 수는 없어야 함
        settlementHarness.configureSettlement(
            VESTArTypes.PaymentMode.PAID, 25_000, address(mockUSDT), platformTreasury, organizer, platformAdmin
        );
        settlementHarness.setElectionState(VESTArTypes.ElectionState.Finalized);
        settlementHarness.setTotalCollectedAmount(100);

        vm.prank(voter);
        vm.expectRevert("VESTAr: only admin or organizer");
        settlementHarness.settleRevenue();
    }
}
