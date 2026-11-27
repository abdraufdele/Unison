# C1 compiled selectors

Baseline creation-bytecode digests use SHA-256, including compiler metadata. Getter entries are included. Each read row uses `make -s read TARGET=<contract> FUNCTION=<name>` with positional JSON `ARGS` when needed. Use targets `vault`, `hook`, `escrow`, `quote`, `token0` or `token1`, and `adapter` for the corresponding sections. Settlement context is a vault getter. Each lifecycle row uses the function name as `ACTION` with `make simulate` or `make act-local`. Fixed funding approvals use `approveA` and `approveB`. The fixture factory is used only by the deployment driver. See the [actor, bounds and manifest inputs](OPERATIONS.md).

## AgreementVault

Baseline creation SHA-256 `e613816b5c958faadf3e8afff7eba152e587e3ebe733330d4f9d6c8783d63c6d`.

| Selector | Signature | Route |
|---|---|---|
| `0x7e199b87` | `RULES_VERSION()` | read |
| `0x51f6f8ec` | `TERMS_SCHEMA()` | read |
| `0xe4725ba1` | `accept(bytes32)` | lifecycle action |
| `0x59db6e85` | `activate(bytes32)` | lifecycle action |
| `0x96856f38` | `activationCutoff()` | read |
| `0xddc53375` | `add(bytes32,int24,int24,uint128,(bytes32,uint256,uint256,int24,int24,uint256,uint256,uint256,uint256))` | lifecycle action |
| `0xe2739491` | `agreementId()` | read |
| `0xe9323c71` | `bandLower()` | read |
| `0x518b2c21` | `bandUpper()` | read |
| `0xea8a1af0` | `cancel()` | lifecycle action |
| `0x9a82a09a` | `cancelled()` | read |
| `0xcf09e0d0` | `createdAt()` | read |
| `0xc95566c7` | `creationChainId()` | read |
| `0xdb692109` | `currentTerms()` | read |
| `0x9340128c` | `effectiveStop()` | read |
| `0xdf342388` | `exitLiquidity()` | lifecycle action |
| `0x3938640f` | `finalizeExpiry()` | lifecycle action |
| `0xbf14c119` | `fund(bytes32)` | lifecycle action |
| `0xb44fc799` | `fundedPrincipal0()` | read |
| `0x844a5e92` | `fundedPrincipal1()` | read |
| `0xa1633bc7` | `lastAdjustment()` | read |
| `0x481c6a75` | `manager()` | read |
| `0xbf904bc8` | `managerAcceptedRevision()` | read |
| `0x19f261ba` | `openingObservation()` | read |
| `0x71640de3` | `positionId()` | read |
| `0x7211dc36` | `positionLiquidity()` | read |
| `0xac4b391d` | `positionLower()` | read |
| `0x6765fd1d` | `positionPoolId()` | read |
| `0xfc6519dc` | `positionSalt()` | read |
| `0x17813de2` | `positionUpper()` | read |
| `0x9d98eef8` | `preflightActivation(bytes32)` | read |
| `0xee6ff999` | `previewOpeningReference()` | read |
| `0x7be3261d` | `recordedStop()` | read |
| `0x0fac1c95` | `remove(bytes32,uint128,(bytes32,uint256,uint256,int24,int24,uint256,uint256,uint256,uint256))` | lifecycle action |
| `0x9ba0383b` | `rerange(bytes32,int24,int24,uint128,(bytes32,uint256,uint256,int24,int24,uint256,uint256,uint256,uint256))` | lifecycle action |
| `0x51a97ffd` | `revise((address,address,address,address,address,address,address))` | lifecycle action |
| `0x7cc96380` | `revision()` | read |
| `0x68c36543` | `scheduledEnd()` | read |
| `0xe1d36f28` | `settlementContext()` | read |
| `0xbe9a6555` | `start()` | read |
| `0xc19d93fb` | `state()` | read |
| `0x0c08bf88` | `terminate()` | lifecycle action |
| `0xb311d9fd` | `termsHash()` | read |
| `0x61d027b3` | `treasury()` | read |
| `0x284a202c` | `treasuryAcceptedRevision()` | read |
| `0x91dd7346` | `unlockCallback(bytes)` | core callback |
| `0xafc14791` | `withdrawIdle()` | lifecycle action |

## ServiceHook

Baseline creation SHA-256 `23b5118bb8bdcf3d1723e29016bbafbd5a01da6b0dd294f362005323a5c18103`.

| Selector | Signature | Route |
|---|---|---|
| `0xd724dea6` | `BAND_NOT_COVERED()` | read |
| `0x58d8e874` | `BELOW_MINIMUM()` | read |
| `0x56ed9b76` | `NOT_ACTIVATED()` | read |
| `0xa8139183` | `NO_MATCHING_POSITION()` | read |
| `0x9ff193c4` | `PERIOD_ENDED()` | read |
| `0xc3c34930` | `RANGE_NOT_PERMITTED()` | read |
| `0x1770a51c` | `STOPPED()` | read |
| `0x0cc82481` | `TICK_OUTSIDE()` | read |
| `0xb47b2fb1` | `afterSwap(address,(address,address,uint24,int24,address),(bool,int256,uint160),int256,bytes)` | core callback |
| `0x2a780d55` | `armAdd(uint8,(int24,int24,int256,bytes32))` | vault only |
| `0xe9323c71` | `bandLower()` | read |
| `0x518b2c21` | `bandUpper()` | read |
| `0x259982e5` | `beforeAddLiquidity(address,(address,address,uint24,int24,address),(int24,int24,int256,bytes32),bytes)` | core callback |
| `0x0dd6feed` | `beforeAdjustment()` | vault only |
| `0xc2c4c5c1` | `checkpoint()` | lifecycle action |
| `0xedfae8d0` | `initializeClock(int24,int24,bytes32,uint128,uint256)` | vault only |
| `0xfff8f311` | `installPosition(int24,int24,bytes32,uint128)` | vault only |
| `0xd32e81a5` | `lastCheckpoint()` | read |
| `0xcbcb71e0` | `observedLiquidity()` | read |
| `0xc5d06077` | `observedTick()` | read |
| `0x38e228a2` | `pendingAdd()` | read |
| `0x3e0dc34e` | `poolId()` | read |
| `0xdc4c90d3` | `poolManager()` | read |
| `0x71640de3` | `positionId()` | read |
| `0xac4b391d` | `positionLower()` | read |
| `0xfc6519dc` | `positionSalt()` | read |
| `0x17813de2` | `positionUpper()` | read |
| `0x3c651671` | `projectedSeconds()` | read |
| `0x3b2c22b0` | `qualification()` | read |
| `0x4222032d` | `qualifyingSeconds()` | read |
| `0x68c36543` | `scheduledEnd()` | read |
| `0xbe9a6555` | `start()` | read |
| `0xe55071c3` | `stopClock()` | vault only |
| `0x75f12b21` | `stopped()` | read |
| `0xa48c05fa` | `storedQualified()` | read |
| `0xfbfa77cf` | `vault()` | read |

## CompensationEscrow

Baseline creation SHA-256 `fe125e14d303cb5c07b0f656d5f916e75f1e533f503a1b322ee1dc9dcd9e8796`.

| Selector | Signature | Route |
|---|---|---|
| `0x19f8dcf1` | `accounted()` | read |
| `0x4e71d92d` | `claim()` | lifecycle action |
| `0xaf38d757` | `claimable()` | read |
| `0xe834a834` | `claimed()` | read |
| `0x78da744b` | `credit(uint256)` | vault only |
| `0xd6f19262` | `earned()` | read |
| `0xf1ca8988` | `fundedBudget()` | read |
| `0xd3e62502` | `managerRecipient()` | read |
| `0x3013ce29` | `paymentToken()` | read |
| `0x590e1ae3` | `refund()` | lifecycle action |
| `0xbf89662d` | `refundable()` | read |
| `0x12f53950` | `refunded()` | read |
| `0xfe60d12c` | `reserved()` | read |
| `0xeb4eebc7` | `treasuryRecipient()` | read |
| `0xfbfa77cf` | `vault()` | read |

## OpeningQuote

Baseline creation SHA-256 `23a569bb85c9c137de6fa0417d5d1b66953403feaf11a623fea23ae4ef54a883`.

| Selector | Signature | Route |
|---|---|---|
| `0x28232183` | `band(uint256,int24,uint16,int24)` | read |
| `0xbc79bd44` | `seed(address,(address,address,uint24,int24,address),int24,int24,uint128)` | read |

## IC1Token

| Selector | Signature | Route |
|---|---|---|
| `0x70a08231` | `balanceOf(address)` | read |
| `0x313ce567` | `decimals()` | read |
| `0xa9059cbb` | `transfer(address,uint256)` | custody implementation only |
| `0x23b872dd` | `transferFrom(address,address,uint256)` | custody implementation only |

## IOpeningReferenceAdapter

| Selector | Signature | Route |
|---|---|---|
| `0x09be76c9` | `observation()` | read |

## ISettlementVault

| Selector | Signature | Route |
|---|---|---|
| `0xe1d36f28` | `settlementContext()` | read on vault |
