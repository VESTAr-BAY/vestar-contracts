// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArTypes} from "../../../src/libraries/vestar/VESTArTypes.sol";
import {VESTArOrganizerRegistry} from "../../../src/vestar/registry/VESTArOrganizerRegistry.sol";
import {VESTArTestBase} from "../base/VESTArTestBase.sol";

contract VESTArOrganizerRegistryHarness is VESTArOrganizerRegistry {
    constructor(address initialOwner) VESTArOrganizerRegistry(initialOwner) {}
}

// OrganizerRegistry 구현체 테스트 자리
// registry 테스트는 state transition보다 "저장/조회/권한" 검증 비중이 큼
contract VESTArOrganizerRegistryTest is VESTArTestBase {
    VESTArOrganizerRegistryHarness internal organizerRegistry;

    function setUp() public {
        organizerRegistry = new VESTArOrganizerRegistryHarness(platformAdmin);
    }

    function testOrganizerCanUpsertOwnProfile() public {
        // 실제 사례 : organizer가 자기 displayName hash와 브랜드 metadata URI를 직접 갱신
        vm.prank(organizer);
        organizerRegistry.upsertOrganizerProfile(keccak256("MAMA"), "ipfs://mama");

        VESTArTypes.OrganizerProfile memory profile = organizerRegistry.getOrganizerProfile(organizer);

        assertEq(profile.organizer, organizer);
        assertEq(profile.displayNameHash, keccak256("MAMA"));
        assertEq(profile.brandMetadataURI, "ipfs://mama");
    }

    function testVerifiedOrganizerCanCreateElectionWithZeroKarma() public {
        vm.prank(platformAdmin);
        organizerRegistry.setVerification(organizer, true, 100, 0);

        assertTrue(organizerRegistry.isVerified(organizer));
        assertEq(
            uint256(organizerRegistry.getOrganizerCreationStatus(organizer, 0)),
            uint256(VESTArTypes.OrganizerCreationStatus.VERIFIED_ELIGIBLE)
        );
        assertTrue(organizerRegistry.canCreateElection(organizer, 0));
    }

    function testUnverifiedOrganizerNeedsAtLeastOneKarmaToCreateElection() public view {
        assertEq(
            uint256(organizerRegistry.getOrganizerCreationStatus(organizer, 0)),
            uint256(VESTArTypes.OrganizerCreationStatus.UNVERIFIED_INELIGIBLE)
        );
        assertEq(
            uint256(organizerRegistry.getOrganizerCreationStatus(organizer, 1)),
            uint256(VESTArTypes.OrganizerCreationStatus.UNVERIFIED_ELIGIBLE)
        );
        assertFalse(organizerRegistry.canCreateElection(organizer, 0));
        assertTrue(organizerRegistry.canCreateElection(organizer, 1));
    }

    function testOnlyOwnerCanSetVerification() public {
        vm.prank(organizer);
        vm.expectRevert("Only owner");
        organizerRegistry.setVerification(organizer, true, 100, 0);
    }
}
