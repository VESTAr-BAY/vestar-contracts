// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArOwnablePausable} from "../../access/VESTArOwnablePausable.sol";
import {IVESTArOrganizerRegistry} from "../../interfaces/vestar/IVESTArOrganizerRegistry.sol";
import {VESTArTypes} from "../../libraries/vestar/VESTArTypes.sol";

// 주최자 프로필과 verified 상태를 저장/갱신하는 실제 구현체
// organizer registry는 "이 주소가 투표를 만들 수 있는가"를 한 곳에서 판정해 주는 명부 역할
contract VESTArOrganizerRegistry is VESTArOwnablePausable, IVESTArOrganizerRegistry {
    mapping(address organizer => VESTArTypes.OrganizerProfile profile) internal _organizerProfiles;

    constructor(address initialOwner) VESTArOwnablePausable(initialOwner) {}

    // 주최자 프로필 관련 코드 : organizer가 자기 프로필 해시와 metadata URI를 직접 갱신
    // 예시 : 브랜드명 원문은 IPFS/백엔드 metadata에 두고, 체인에는 displayNameHash + URI만 저장
    function upsertOrganizerProfile(bytes32 displayNameHash, string calldata brandMetadataURI) public virtual {
        VESTArTypes.OrganizerProfile storage profile = _organizerProfiles[msg.sender];

        profile.organizer = msg.sender;
        profile.displayNameHash = displayNameHash;
        profile.brandMetadataURI = brandMetadataURI;

        emit OrganizerProfileUpserted(msg.sender, displayNameHash, brandMetadataURI);
    }

    // verified 관련 코드 : platform owner가 verified on/off와 효력 시각을 관리
    // 예시 : verified=true면 karma 0이어도 즉시 투표 생성 가능, false면 최소 karma 1이 필요
    function setVerification(
        address organizerAddress,
        bool verified,
        uint64 effectiveTime,
        uint64 revokedTime
    ) public virtual onlyOwner {
        VESTArTypes.OrganizerProfile storage profile = _organizerProfiles[organizerAddress];

        profile.organizer = organizerAddress;
        profile.verified = verified;
        profile.verificationEffectiveTime = effectiveTime;
        profile.verificationRevokedTime = revokedTime;

        emit OrganizerVerificationUpdated(organizerAddress, verified, effectiveTime, revokedTime);
    }

    function getOrganizerProfile(address organizerAddress)
        public
        view
        virtual
        returns (VESTArTypes.OrganizerProfile memory)
    {
        VESTArTypes.OrganizerProfile memory profile = _organizerProfiles[organizerAddress];

        if (profile.organizer == address(0)) {
            profile.organizer = organizerAddress;
        }

        return profile;
    }

    function isVerified(address organizerAddress) public view virtual returns (bool) {
        return _organizerProfiles[organizerAddress].verified;
    }

    // 주최 가능 상태 관련 코드 : verified면 karma 0도 허용, 아니면 karma 1 이상일 때만 허용
    function getOrganizerCreationStatus(address organizerAddress, uint8 karmaTier)
        public
        view
        virtual
        returns (VESTArTypes.OrganizerCreationStatus)
    {
        if (isVerified(organizerAddress)) {
            return VESTArTypes.OrganizerCreationStatus.VERIFIED_ELIGIBLE;
        }

        if (karmaTier >= 1) {
            return VESTArTypes.OrganizerCreationStatus.UNVERIFIED_ELIGIBLE;
        }

        return VESTArTypes.OrganizerCreationStatus.UNVERIFIED_INELIGIBLE;
    }

    function canCreateElection(address organizerAddress, uint8 karmaTier) public view virtual returns (bool) {
        return getOrganizerCreationStatus(organizerAddress, karmaTier)
            != VESTArTypes.OrganizerCreationStatus.UNVERIFIED_INELIGIBLE;
    }
}
