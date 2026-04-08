// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArTypes} from "../../libraries/vestar/VESTArTypes.sol";

// 유료 투표 단가 조회, 누적 수익 조회, 50:50 정산 실행 표면을 정의하는 인터페이스
// settlement module로 따로 빼면 "투표"와 "돈 정산" 책임을 분리해서 읽기 쉬워짐
interface IVESTArSettlementModule {
    // 정산이 끝났을 때 총액과 양쪽 몫을 로그로 남김
    event RevenueSettled(
        bytes32 indexed electionId,
        address indexed platformTreasury,
        address indexed organizer,
        uint256 totalRevenueAmount,
        uint256 platformRevenueAmount,
        uint256 organizerRevenueAmount
    );

    // organizer/admin이 "이 election은 정산 대신 각 유저가 직접 환불받게 한다"를 활성화할 때 남기는 이벤트
    event RefundsEnabled(bytes32 indexed electionId, address indexed enabledBy, uint256 totalRefundableAmount);

    // 유저가 자기 지갑으로 직접 환불을 수령했을 때 남기는 이벤트
    event RefundClaimed(bytes32 indexed electionId, address indexed voter, uint256 refundAmount);

    // FREE / PAID 모드를 enum으로 읽음
    function paymentMode() external view returns (VESTArTypes.PaymentMode);

    // 결제에 쓰는 토큰 주소. MVP에서는 mockUSDT 같은 ERC20을 가정
    function paymentToken() external view returns (address);

    // ballot 1개당 비용. 무료 투표면 0
    function costPerBallot() external view returns (uint256);

    // 플랫폼 몫을 받을 treasury 주소
    function platformTreasury() external view returns (address);

    // 플랫폼 몫 비율. v1에서는 5000 = 50.00%
    function platformShareBps() external view returns (uint16);

    // organizer 몫 비율. v1에서는 5000 = 50.00%
    function organizerShareBps() external view returns (uint16);

    // ballot 개수에 맞는 요구 결제 금액을 계산
    function quotePayment(uint256 ballotCount) external view returns (uint256);

    // 현재까지 이 election이 받은 총 토큰 수납액
    function totalCollectedAmount() external view returns (uint256);

    // 정산 요약 전체를 struct로 조회
    function getSettlementSummary() external view returns (VESTArTypes.SettlementSummary memory);

    // 환불 요약 전체를 struct로 조회
    function getRefundSummary() external view returns (VESTArTypes.RefundSummary memory);

    // 특정 유저가 현재 claim 가능한 누적 환불 금액
    function refundableAmountOf(address voter) external view returns (uint256);

    // refund mode가 이미 열렸는지 빠르게 읽는 helper
    function refundsEnabled() external view returns (bool);

    // organizer/admin이 정산 대신 유저 개별 claim 환불 모드를 연다
    function enableRefunds() external;

    // 유저가 자기 누적 환불액을 직접 수령
    function claimRefund() external returns (uint256);

    // 투표 종료 후 50:50 정산 실행
    function settleRevenue() external;
}
