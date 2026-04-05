// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVESTArSettlementModule} from "../../../interfaces/vestar/IVESTArSettlementModule.sol";
import {VESTArTypes} from "../../../libraries/vestar/VESTArTypes.sol";
import {VESTArElectionStorage} from "../base/VESTArElectionStorage.sol";

// 투표 단가 계산, 수납액 집계, 50:50 정산 실행 구현 자리
// 돈 흐름은 실수 위험이 커서 vote 로직과 분리해 별도 모듈로 두는 편이 검토와 테스트에 유리
abstract contract VESTArSettlementModuleImpl is VESTArElectionStorage, IVESTArSettlementModule {
    using SafeERC20 for IERC20;

    // 결제 모드 관련 코드 : FREE / PAID를 외부에서 바로 읽을 수 있게 노출
    function paymentMode() public view virtual returns (VESTArTypes.PaymentMode) {
        return _config.paymentMode;
    }

    // 결제 모드 관련 코드 : 어떤 ERC20으로 결제받는지 조회
    function paymentToken() public view virtual returns (address) {
        return _config.paymentToken;
    }

    // 결제 모드 관련 코드 : ballot 1개당 비용
    function costPerBallot() public view virtual returns (uint256) {
        return _config.costPerBallot;
    }

    // 정산 수취처 관련 코드 : 플랫폼 수익이 실제로 어디로 가는지 프론트/백엔드가 조회
    function platformTreasury() public view virtual returns (address) {
        return _settlementSummary.platformTreasury;
    }

    function platformShareBps() public pure virtual returns (uint16) {
        return PLATFORM_SHARE_BPS;
    }

    function organizerShareBps() public pure virtual returns (uint16) {
        return ORGANIZER_SHARE_BPS;
    }

    // 결제 모드 관련 코드 : 다중 선택이어도 ballot 단위로만 과금하므로 ballotCount x costPerBallot
    function quotePayment(uint256 ballotCount) public view virtual returns (uint256) {
        return _quotePaymentForBallots(ballotCount);
    }

    // 누적 수납액은 나중에 settleRevenue에서 분배 기준이 됨
    function totalCollectedAmount() public view virtual returns (uint256) {
        return _totalCollectedAmount;
    }

    // struct 전체를 memory로 반환하면 프론트나 테스트가 관련 필드를 한 번에 읽기 편함
    // 예시 : organizer dashboard가 "총수익 / 플랫폼 몫 / organizer 몫 / 정산 완료 여부"를 카드 4개로 보여줄 때 유용
    function getSettlementSummary() public view virtual returns (VESTArTypes.SettlementSummary memory) {
        return _settlementSummary;
    }

    // 정산 관련 코드 : Finalized 이후 한 번만 실행하고, organizer가 홀수 잔차를 가져가도록 실제 송금까지 처리
    function settleRevenue() public virtual {
        _validateElectionConfig();
        _syncStateFromClock();
        _requirePlatformAdminOrOrganizer();

        require(_state == VESTArTypes.ElectionState.Finalized, "VESTAr: not finalized");
        require(!_settlementSummary.settled, "VESTAr: already settled");

        (uint256 platformRevenueAmount, uint256 organizerRevenueAmount) =
            _previewSettlementSplit(_totalCollectedAmount);

        _settlementSummary.paymentToken = _config.paymentToken;
        _settlementSummary.totalRevenueAmount = _totalCollectedAmount;
        _settlementSummary.platformRevenueAmount = platformRevenueAmount;
        _settlementSummary.organizerRevenueAmount = organizerRevenueAmount;
        _settlementSummary.settled = true;

        if (_config.paymentMode == VESTArTypes.PaymentMode.PAID && _totalCollectedAmount > 0) {
            require(_settlementSummary.platformTreasury != address(0), "VESTAr: treasury missing");

            IERC20 token = IERC20(_config.paymentToken);

            if (platformRevenueAmount > 0) {
                token.safeTransfer(_settlementSummary.platformTreasury, platformRevenueAmount);
            }

            if (organizerRevenueAmount > 0) {
                token.safeTransfer(_organizer, organizerRevenueAmount);
            }
        }

        emit RevenueSettled(
            _config.electionId,
            _settlementSummary.platformTreasury,
            _organizer,
            _settlementSummary.totalRevenueAmount,
            _settlementSummary.platformRevenueAmount,
            _settlementSummary.organizerRevenueAmount
        );
    }
}
