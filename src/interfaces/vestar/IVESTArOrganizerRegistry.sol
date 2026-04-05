// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVESTArAdminControl} from "./IVESTArAdminControl.sol";
import {VESTArTypes} from "../../libraries/vestar/VESTArTypes.sol";

//  주최자 프로필과 verified 상태를 읽고 갱신하는 인터페이스

interface IVESTArOrganizerRegistry is IVESTArAdminControl {

    // indexed는 검색 조건으로 쓰기 좋아서, organizer나 hash처럼 자주 필터링할 값에 붙임
    event OrganizerProfileUpserted(
        address indexed organizer,
        bytes32 indexed displayNameHash,
        string brandMetadataURI
    );

    // verified 상태가 바뀌는 순간을 기록하는 이벤트
    event OrganizerVerificationUpdated(
        address indexed organizer,
        bool verified,
        uint64 effectiveTime,
        uint64 revokedTime
    );

    function upsertOrganizerProfile(bytes32 displayNameHash, string calldata brandMetadataURI) external;

    // setVerification은 owner/admin 권한이 붙는 관리 함수
    function setVerification(
        address organizer,
        bool verified,
        uint64 effectiveTime,
        uint64 revokedTime
    ) external;

    // view returns (...) : 상태 변경 없이 값을 읽어오고, OrganizerProfile struct를 통째로 반환
    function getOrganizerProfile(address organizer)
        external
        view
        returns (VESTArTypes.OrganizerProfile memory);

    function isVerified(address organizer) external view returns (bool);

    // verified면 카르마 0이어도 가능, unverified면 카르마 1 이상일 때만 가능
    function getOrganizerCreationStatus(address organizer, uint8 karmaTier)
        external
        view
        returns (VESTArTypes.OrganizerCreationStatus);

    // factory가 createElection 전에 바로 부를 수 있는 bool helper
    function canCreateElection(address organizer, uint8 karmaTier) external view returns (bool);
}
