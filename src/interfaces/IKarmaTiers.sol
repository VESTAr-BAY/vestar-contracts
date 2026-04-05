// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// KarmaTiers는 "카르마 잔액 -> 티어" 규칙을 들고 있는 컨트랙트
interface IKarmaTiers {
    struct Tier {
        // 이 티어에 들어오기 위한 최소 카르마
        uint256 minKarma;
        // 이 티어에 허용되는 최대 카르마
        uint256 maxKarma;
        // 사람이 읽기 쉬운 티어 이름
        string name;
        // Status 쪽 다른 로직에서 쓸 수 있는 부가 정보
        uint32 txPerEpoch;
    }

    // 현재 카르마 잔액을 넣으면 몇 티어인지 숫자로 돌려줌
    function getTierIdByKarmaBalance(uint256 karmaBalance) external view returns (uint8);
    // 티어 ID의 상세 범위를 보고 싶을 때 사용
    function getTierById(uint8 tierId) external view returns (Tier memory);
    // 전체 티어 개수를 조회
    function getTierCount() external view returns (uint256);
}
