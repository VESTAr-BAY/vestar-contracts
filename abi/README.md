# VESTAr ABI Handoff

이 폴더는 프론트/백엔드에 바로 넘길 수 있게 **ABI만 따로 추린 폴더**입니다.

이 폴더의 ABI와 `status-testnet.addresses.json`는 최신 배포 후
`./script/SyncStatusArtifacts.sh`로 다시 생성할 수 있습니다.

포함 파일:

- `VESTArElection.json`
- `VESTArElectionFactory.json`
- `VESTArOrganizerRegistry.json`
- `VESTArKarmaRegistry.json`
- `MockUSDT.json`
- `status-testnet.addresses.json`

프론트/백에서 이렇게 쓰면 됩니다!

```ts
import electionAbi from './abis/VESTArElection.json'
import addresses from './abis/status-testnet.addresses.json'

const electionFactoryAddress = addresses.VESTArElectionFactory
```
