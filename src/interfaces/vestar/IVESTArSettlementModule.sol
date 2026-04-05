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

    // 투표 종료 후 50:50 정산 실행
    function settleRevenue() external;
}
