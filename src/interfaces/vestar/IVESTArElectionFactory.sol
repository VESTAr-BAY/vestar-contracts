// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArTypes} from "../../libraries/vestar/VESTArTypes.sol";
import {IVESTArAdminControl} from "./IVESTArAdminControl.sol";

// 새로운 election 인스턴스를 생성하고 주소를 추적하는 팩토리 인터페이스
// factory 패턴은 "만드는 책임"을 따로 빼서 배포 로직과 개별 인스턴스 로직을 분리함
interface IVESTArElectionFactory is IVESTArAdminControl {
    // create 시점 핵심 정보를 로그로 남겨 인덱서가 쉽게 추적하도록 함
    event ElectionCreated(
        bytes32 indexed electionId,
        address indexed electionAddress,
        address indexed organizer,
        VESTArTypes.VisibilityMode visibilityMode,
        bool organizerVerifiedSnapshot,
        VESTArTypes.PaymentMode paymentMode,
        uint256 costPerBallot
    );

    // 어떤 organizer registry를 참조하는지 조회
    // organizer registry : 주최자 정보를 모아두는 온체인 명부
    function organizerRegistry() external view returns (address);

    // 어떤 karma registry를 참조하는지 조회
    // karma registry : 유저의 Karma 기반 참여 자격을 판정하는 기준점
        // Status의 Karma, KarmaTiers를 읽음
        // 어떤 주소가 몇 티어인지 계산
        // 최소 티어 이상인지 판정
    // 바로 Status 컨트랙트를 안 보는 이유 : 의존성을 한 레이어 감싸서 추상화
    function karmaRegistry() external view returns (address);

    // 플랫폼 정산 몫을 받을 treasury 주소
    function platformTreasury() external view returns (address);

    // 플랫폼 몫 비율. v1에서는 5000 = 50.00%
    function platformShareBps() external view returns (uint16);

    // organizer 몫 비율. v1에서는 5000 = 50.00%
    function organizerShareBps() external view returns (uint16);

    // minimal proxy나 implementation 패턴에서 원본 구현체 주소를 노출할 수 있음
    // 실제 election 인스턴스를 찍어낼 때 기준이 되는 원본 로직 컨트랙트 주소
    // implementation = 진짜 로직이 들어 있는 원본 계약
    // minimal proxy 또는 clone = 매우 가볍게 복제된 인스턴스
    function electionImplementation() external view returns (address);

    // 지금까지 생성된 총 election 수
    function totalElections() external view returns (uint256);

    // config struct 하나를 받아 새 election을 생성
    function createElection(VESTArTypes.ElectionConfig calldata config) external returns (address electionAddress);

    // electionId -> election address 매핑 조회
    function getElection(bytes32 electionId) external view returns (address electionAddress);
}
