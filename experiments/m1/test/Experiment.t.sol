// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {ExperimentVault, ServiceHook, Compensation, MockToken, LocalRouter} from "../src/Experiment.sol";

interface Vm {
    function warp(uint256) external;
    function prank(address) external;
    function expectRevert() external;
    function snapshotState() external returns (uint256);
    function revertToState(uint256) external returns (bool);
    function cool(address) external;
}

// Test-only probes. Never deployed in the supported product surface.
contract AdmissionProbe {
    function add(IPoolManager core, PoolKey memory key) external { core.unlock(abi.encode(key)); }
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        PoolKey memory key = abi.decode(data,(PoolKey));
        IPoolManager(msg.sender).modifyLiquidity(key,IPoolManager.ModifyLiquidityParams(-120,120,1e18,0),"");
        return "";
    }
}

// Explicit baseline: final qualification is applied to the whole elapsed period.
// This is a defined endpoint-only policy, not a claim that history is reconstructible.
contract EndpointBaseline {
    ExperimentVault immutable vault;
    MockToken immutable pay;
    address immutable beneficiary;
    uint256 immutable start;
    uint256 public paid;
    constructor(ExperimentVault v, MockToken p, address m) { vault=v;pay=p;beneficiary=m;start=block.timestamp; }
    function claim() external {
        int24 tick=vault.currentTick();
        bool q = vault.positionLiquidity()>=1e15 && vault.lower()<=-60 && vault.upper()>=60
            && tick>=vault.lower() && tick<vault.upper();
        uint256 elapsed=block.timestamp-start;
        if(elapsed>300)elapsed=300;
        uint256 entitlement=q?elapsed*1e18:0;
        uint256 amount=entitlement-paid; paid+=amount;
        pay.transfer(beneficiary,amount);
    }
}

contract ExperimentTest {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    Vm constant vm=Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant TREASURY=address(0xA11CE);
    address constant MANAGER=address(0xB0B);
    address constant TRADER=address(0xCAFE);
    uint256 constant START=1000;
    uint128 constant INITIAL_L=1e18;
    PoolManager pm;
    MockToken a;
    MockToken b;
    MockToken pay;
    ExperimentVault vault;
    ServiceHook hook;
    Compensation escrow;
    LocalRouter router;
    LocalRouter router2;
    EndpointBaseline endpoint;
    uint256 coreCreationGas;
    uint256 vaultCreationGas;
    uint256 hookCreationGas;
    uint256 escrowCreationGas;
    event log_named_uint(string key,uint256 val);
    event log_named_int(string key,int256 val);

    function eq(uint256 x,uint256 y,string memory message) internal pure { require(x==y,message); }
    function ok(bool v,string memory message) internal pure { require(v,message); }
    function setUp() public {
        vm.warp(START);
        uint256 g=gasleft();pm=new PoolManager(TREASURY);coreCreationGas=g-gasleft();
        MockToken x=new MockToken(); MockToken y=new MockToken();
        (a,b)=address(x)<address(y)?(x,y):(y,x);
        pay=new MockToken();
        g=gasleft();vault=new ExperimentVault(IPoolManager(address(pm)),TREASURY,MANAGER,a,b);vaultCreationGas=g-gasleft();
        bytes memory creation=abi.encodePacked(type(ServiceHook).creationCode,abi.encode(pm,vault));
        bytes32 hash=keccak256(creation);
        uint160 flags=uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG);
        for(uint256 s;;s++) {
            address predicted=address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff),address(this),bytes32(s),hash)))));
            if((uint160(predicted)&Hooks.ALL_HOOK_MASK)==flags) {
                g=gasleft();hook=new ServiceHook{salt:bytes32(s)}(IPoolManager(address(pm)),vault);hookCreationGas=g-gasleft();
                eq(uint160(address(hook)),uint160(predicted),"CREATE2 address mismatch"); break;
            }
            require(s<500000,"mining exhausted");
        }
        vm.prank(TREASURY);vault.bind(hook);
        pm.initialize(vault.poolKey(),uint160(1<<96));
        a.mint(address(vault),1e26); b.mint(address(vault),1e26);
        vm.prank(TREASURY);vault.change(int256(uint256(INITIAL_L)));
        g=gasleft();escrow=new Compensation(pay,hook,MANAGER);escrowCreationGas=g-gasleft();
        pay.mint(address(escrow),300e18);
        vm.prank(TREASURY);hook.activate();
        router=new LocalRouter(IPoolManager(address(pm)),vault.poolKey(),TRADER);
        router2=new LocalRouter(IPoolManager(address(pm)),vault.poolKey(),TRADER);
        a.mint(address(router),1e26);b.mint(address(router),1e26);
        a.mint(address(router2),1e26);b.mint(address(router2),1e26);
        endpoint=new EndpointBaseline(vault,pay,address(0xBACE));
        pay.mint(address(endpoint),300e18);
    }
    function warp(uint256 elapsed) internal {vm.warp(START+elapsed);}
    function trade(LocalRouter r,int24 tick) internal {vm.prank(TRADER);r.tradeTo(tick);}
    function change(int256 delta) internal {vm.prank(TREASURY);vault.change(delta);}
    function independentQ() internal view returns(bool) {
        // Read actual core state, not ServiceHook.actualQualification or secondsNow.
        PoolKey memory k=vault.poolKey();
        (uint128 l,,)=IPoolManager(address(pm)).getPositionInfo(k.toId(),address(vault),vault.lower(),vault.upper(),vault.salt());
        (,int24 tick,,)=IPoolManager(address(pm)).getSlot0(k.toId());
        return l>=1e15 && vault.lower()<=-60 && vault.upper()>=60 && tick>=vault.lower() && tick<vault.upper();
    }
    function priceDiffers(int24 target) internal view returns(bool) {
        (uint160 price,,,) = IPoolManager(address(pm)).getSlot0(vault.poolKey().toId());
        return price != TickMath.getSqrtPriceAtTick(target);
    }
    function testThirdPartyTimeline() public {
        uint256 principal0=a.balanceOf(address(vault));uint256 principal1=b.balanceOf(address(vault));
        eq(vault.positionLiquidity(),INITIAL_L,"real core position");
        warp(100);trade(router,180);
        ok(!hook.qualified(),"outside must stop credit");
        eq(hook.qualifyingSeconds(),100,"first interval");
        emit log_named_int("tick after outward swap",vault.currentTick());
        warp(200);trade(router2,0);
        ok(hook.qualified(),"inside must resume credit");
        eq(hook.qualifyingSeconds(),100,"outside interval earns zero");
        warp(300);escrow.claim();
        eq(hook.qualifyingSeconds(),200,"persisted qualifying seconds");
        eq(escrow.paid(),200e18,"actual paid");eq(pay.balanceOf(MANAGER),200e18,"manager transfer");
        eq(pay.balanceOf(address(escrow)),100e18,"remaining compensation");
        eq(hook.swapCallbacks(),2,"callbacks through both routers");
        eq(a.balanceOf(address(vault)),principal0,"claim leaves idle token0 alone");
        eq(b.balanceOf(address(vault)),principal1,"claim leaves idle token1 alone");
        eq(vault.positionLiquidity(),INITIAL_L,"claim leaves core principal alone");
        emit log_named_uint("timeline qualifying seconds",hook.qualifyingSeconds());
        emit log_named_uint("timeline manager payment base units",pay.balanceOf(MANAGER));
        endpoint.claim();eq(pay.balanceOf(address(0xBACE)),300e18,"endpoint policy pays 300");
        emit log_named_uint("endpoint-only payment base units",pay.balanceOf(address(0xBACE)));
    }
    function testPeriodicComparisons() public {
        // Left-hold sampler, actual core state read at 150-second boundaries.
        bool sample=independentQ();uint256 estimate;
        warp(100);trade(router,180);
        warp(150);if(sample)estimate+=150;sample=independentQ();
        warp(200);trade(router,0);
        warp(300);if(sample)estimate+=150;
        eq(estimate,150,"150s sampler estimate");eq(hook.secondsNow(),200,"event clock exact");
        emit log_named_uint("periodic 150s qualifying seconds",estimate);
    }
    function testAlignedPeriodicCanMatch() public {
        bool sample=independentQ();uint256 estimate;
        warp(100);if(sample)estimate+=100;trade(router,180);sample=independentQ();
        warp(200);if(sample)estimate+=100;trade(router,0);sample=independentQ();
        warp(300);if(sample)estimate+=100;
        eq(estimate,200,"aligned sampler exact");
    }
    function testEndpointCorrectWhenQuiet() public {
        warp(300);endpoint.claim();escrow.claim();
        eq(pay.balanceOf(address(0xBACE)),300e18,"endpoint is correct for all-qualifying history");
        eq(escrow.paid(),300e18,"hook agrees on quiet history");
    }
    function testFullRemovalCheckpoint() public {
        warp(100);change(-int256(uint256(INITIAL_L)));
        ok(!hook.qualified(),"empty position");
        warp(300);escrow.claim();eq(escrow.paid(),100e18,"full removal must preserve old 100 seconds");
    }
    function testPartialRemovalAndReadd() public {
        warp(50);change(-int256(uint256(INITIAL_L/2)));
        ok(hook.qualified(),"partial above threshold");
        warp(100);change(-int256(uint256(vault.positionLiquidity()-uint128(1e14))));
        ok(!hook.qualified(),"below threshold");
        warp(200);change(int256(uint256(INITIAL_L)));
        warp(300);escrow.claim();eq(escrow.paid(),200e18,"threshold intervals");
    }
    function testRerangeAndRetiredIdentity() public {
        bytes32 oldSalt=vault.salt();
        warp(100);vm.prank(MANAGER);vault.rerange(0,120,INITIAL_L);
        ok(!hook.qualified(),"does not cover fixed band");
        (uint128 oldL,,)=IPoolManager(address(pm)).getPositionInfo(vault.poolKey().toId(),address(vault),-120,120,oldSalt);
        eq(oldL,0,"retired position empty");
        warp(200);vm.prank(MANAGER);vault.rerange(-180,180,INITIAL_L);
        warp(300);escrow.claim();eq(escrow.paid(),200e18,"rerange intervals");
    }
    function testBoundaries() public {
        // Move upward to lower boundary (avoids the downward tick-minus-one convention).
        trade(router,-180);trade(router,-120);
        eq(uint256(int256(vault.currentTick())+1000),880,"exact lower tick");
        ok(hook.qualified(),"lower inclusive");
        trade(router,120);ok(!hook.qualified(),"upper exclusive");
    }
    function testRepeatedClaimDelayedAndQuiet() public {
        warp(100);escrow.claim();eq(escrow.paid(),100e18,"first claim");
        escrow.claim();eq(escrow.paid(),100e18,"same timestamp no double claim");
        warp(500);escrow.claim();eq(escrow.paid(),300e18,"end clipping and cap");
        escrow.claim();eq(pay.balanceOf(MANAGER),300e18,"no second payment");
    }
    function testTerminationAndPrincipalExit() public {
        warp(100);vm.prank(TREASURY);vault.terminate();
        vm.prank(MANAGER);vm.expectRevert();vault.change(1);
        vm.prank(MANAGER);vm.expectRevert();vault.rerange(-180,180,INITIAL_L);
        change(-int256(uint256(vault.positionLiquidity())));
        vm.prank(TREASURY);vault.withdrawIdle();
        ok(a.balanceOf(TREASURY)>0 && b.balanceOf(TREASURY)>0,"principal returned before claim");
        warp(500);escrow.claim();eq(escrow.paid(),100e18,"termination freezes time");
        trade(router,180);eq(hook.secondsNow(),100,"post termination swap no credit");
    }
    function testSameTimestampActions() public {
        warp(100);change(-int256(uint256(INITIAL_L)));change(int256(uint256(INITIAL_L)));
        trade(router,180);trade(router2,0);escrow.claim();
        eq(escrow.paid(),100e18,"same timestamp no extra elapsed credit");
        warp(300);escrow.claim();eq(escrow.paid(),300e18,"no accidental gap");
    }
    function testAuthenticationAndPositionIdentity() public {
        PoolKey memory k=vault.poolKey();
        vm.expectRevert();hook.afterSwap(TRADER,k,IPoolManager.SwapParams(true,-1,1),BalanceDelta.wrap(0),"");
        vm.expectRevert();vault.unlockCallback(abi.encode(false,int256(1),int24(-120),int24(120)));
        vm.prank(address(pm));vm.expectRevert();vault.unlockCallback(abi.encode(false,int256(1),int24(-120),int24(120)));
        vm.prank(TRADER);vm.expectRevert();vault.change(1);
        AdmissionProbe probe=new AdmissionProbe();vm.expectRevert();probe.add(IPoolManager(address(pm)),k);
        vm.prank(address(pm));vm.expectRevert();
        hook.beforeAddLiquidity(address(vault),k,IPoolManager.ModifyLiquidityParams(-120,120,1e18,bytes32(uint256(7))),"");
        k.fee=500;
        vm.prank(address(pm));vm.expectRevert();hook.afterSwap(TRADER,k,IPoolManager.SwapParams(true,-1,1),BalanceDelta.wrap(0),"");
        eq(uint160(address(hook))&Hooks.ALL_HOOK_MASK,Hooks.BEFORE_ADD_LIQUIDITY_FLAG|Hooks.AFTER_SWAP_FLAG,"address permissions");
    }
    function testActivationOneShot() public {
        vm.prank(TREASURY);vm.expectRevert();hook.activate();
    }
    function testLifecycleAuthorities() public {
        vm.prank(TRADER);vm.expectRevert();vault.bind(hook);
        vm.prank(TREASURY);vm.expectRevert();vault.bind(hook);
        vm.prank(TRADER);vm.expectRevert();hook.activate();
        vm.prank(TRADER);vm.expectRevert();vault.terminate();
        vm.prank(TRADER);vm.expectRevert();vault.rerange(-180,180,INITIAL_L);
        vm.prank(TREASURY);vm.expectRevert();vault.withdrawIdle();
        vm.prank(TRADER);vm.expectRevert();hook.refresh();
        vm.prank(TRADER);vm.expectRevert();hook.terminate();
    }
    function testSamePriceSwapRejected() public {
        vm.prank(TRADER);vm.expectRevert();router.tradeTo(0);
        eq(hook.swapCallbacks(),0,"rejected swap has no callback credit");
        eq(hook.secondsNow(),0,"rejected same-time swap earns nothing");
    }
    function testFeeOnlyCollect() public {
        warp(100);trade(router,60);
        uint128 l=vault.positionLiquidity();
        warp(150);change(0);
        eq(vault.positionLiquidity(),l,"fee collect must preserve L");
        warp(300);escrow.claim();eq(escrow.paid(),300e18,"fee collect clock");
    }
    function testCallbackFailureRevertsSwap() public {
        // The hook is deliberately offered as another pool's hook. Its pool binding
        // must reject the callback, atomically reverting the real core swap.
        PoolKey memory wrong=vault.poolKey();wrong.fee=500;
        pm.initialize(wrong,uint160(1<<96));
        LocalRouter wrongRouter=new LocalRouter(IPoolManager(address(pm)),wrong,TRADER);
        a.mint(address(wrongRouter),1e26);b.mint(address(wrongRouter),1e26);
        vm.prank(TRADER);vm.expectRevert();wrongRouter.tradeTo(180);
        (,int24 tick,,)=IPoolManager(address(pm)).getSlot0(wrong.toId());
        eq(uint256(int256(tick)+1000),1000,"rejected callback rolls back pool price");
    }
    function testFuzzReference(uint256 seed) public {
        uint256 referenceSeconds;uint256 elapsed;bool terminated;
        for(uint256 i;i<32;i++) {
            seed=uint256(keccak256(abi.encode(seed,i)));
            uint256 dt=seed%21;uint256 next=elapsed+dt;
            uint256 from=elapsed<300?elapsed:300;uint256 to=next<300?next:300;
            // Independent rectangle integration using core state before the interval.
            if(!terminated && independentQ())referenceSeconds+=to-from;
            elapsed=next;warp(elapsed);
            uint256 action=(seed>>16)%10;
            if(action==0) {if(priceDiffers(180))trade(router,180);}
            else if(action==1) {if(priceDiffers(0))trade(router2,0);}
            else if(action==2) {if(vault.positionLiquidity()>0)change(-int256(uint256(vault.positionLiquidity())));}
            else if(action==3) {if(vault.positionLiquidity()==0)change(int256(uint256(INITIAL_L)));}
            else if(action==4)escrow.claim();
            else if(action==5 && !terminated) {vm.prank(TREASURY);vault.terminate();terminated=true;}
            else if(action==6) {vm.prank(TREASURY);vault.rerange(-180,180,INITIAL_L);}
            else if(action==8) {if(vault.positionLiquidity()>1)change(-int256(uint256(vault.positionLiquidity()/2)));}
            else if(action==9) {vm.prank(TREASURY);vault.rerange(0,120,INITIAL_L);}
            else hook.checkpoint();
            eq(hook.secondsNow(),referenceSeconds,"reference clock mismatch");
            ok(escrow.paid()<=referenceSeconds*1e18 && escrow.paid()<=300e18,"paid exceeds earned/funded");
            eq(pay.balanceOf(address(vault)),0,"payment never enters principal vault");
            eq(pay.balanceOf(MANAGER),escrow.paid(),"actual transfer matches paid");
            eq(pay.balanceOf(address(escrow))+escrow.paid(),300e18,"compensation conservation");
        }
        escrow.claim();eq(escrow.paid(),referenceSeconds*1e18,"final reference payment");
    }
    function testGasComparison() public {
        emit log_named_uint("PoolManager creation execution gas",coreCreationGas);
        emit log_named_uint("vault creation execution gas",vaultCreationGas);
        emit log_named_uint("hook creation execution gas excluding salt search",hookCreationGas);
        emit log_named_uint("escrow creation execution gas",escrowCreationGas);
        // Plain pool shares tokens, initial price/range/L/fee and input intent.
        ExperimentVault plain=new ExperimentVault(IPoolManager(address(pm)),TREASURY,MANAGER,a,b);
        vm.prank(TREASURY);plain.bind(ServiceHook(address(0)));
        pm.initialize(plain.poolKey(),uint160(1<<96));
        a.mint(address(plain),1e26);b.mint(address(plain),1e26);
        vm.prank(TREASURY);plain.change(int256(uint256(INITIAL_L)));
        LocalRouter plainRouter=new LocalRouter(IPoolManager(address(pm)),plain.poolKey(),TRADER);
        a.mint(address(plainRouter),1e26);b.mint(address(plainRouter),1e26);
        // Separate snapshots prevent the first measurement warming storage for the second.
        warp(100);
        uint256 snapshot=vm.snapshotState();
        vm.cool(address(pm));vm.cool(address(a));vm.cool(address(b));vm.cool(address(plainRouter));
        vm.prank(TRADER);uint256 g=gasleft();plainRouter.tradeTo(180);uint256 plainGas=g-gasleft();
        require(vm.revertToState(snapshot));
        vm.cool(address(pm));vm.cool(address(a));vm.cool(address(b));vm.cool(address(router));
        vm.cool(address(vault));vm.cool(address(hook));
        vm.prank(TRADER);g=gasleft();router.tradeTo(180);uint256 hookedGas=g-gasleft();
        emit log_named_uint("plain outward swap execution gas",plainGas);
        emit log_named_uint("hooked outward swap execution gas",hookedGas);
        emit log_named_uint("incremental outward swap execution gas",hookedGas-plainGas);
        // Match both post-swap pool states before measuring the reverse path.
        vm.prank(TRADER);plainRouter.tradeTo(180);
        warp(200);snapshot=vm.snapshotState();
        vm.cool(address(pm));vm.cool(address(a));vm.cool(address(b));vm.cool(address(plainRouter));
        vm.prank(TRADER);g=gasleft();plainRouter.tradeTo(0);plainGas=g-gasleft();
        require(vm.revertToState(snapshot));
        vm.cool(address(pm));vm.cool(address(a));vm.cool(address(b));vm.cool(address(router));
        vm.cool(address(vault));vm.cool(address(hook));
        vm.prank(TRADER);g=gasleft();router.tradeTo(0);hookedGas=g-gasleft();
        emit log_named_uint("plain return swap execution gas",plainGas);
        emit log_named_uint("hooked return swap execution gas",hookedGas);
        emit log_named_uint("incremental return swap execution gas",hookedGas-plainGas);
        vm.prank(TRADER);plainRouter.tradeTo(0);
        warp(300);g=gasleft();escrow.claim();emit log_named_uint("first claim execution gas",g-gasleft());
        vm.prank(TREASURY);vault.terminate();
        warp(400);snapshot=vm.snapshotState();
        vm.cool(address(pm));vm.cool(address(a));vm.cool(address(b));vm.cool(address(plainRouter));
        vm.prank(TRADER);g=gasleft();plainRouter.tradeTo(180);plainGas=g-gasleft();
        require(vm.revertToState(snapshot));
        vm.cool(address(pm));vm.cool(address(a));vm.cool(address(b));vm.cool(address(router));
        vm.cool(address(vault));vm.cool(address(hook));
        vm.prank(TRADER);g=gasleft();router.tradeTo(180);hookedGas=g-gasleft();
        emit log_named_uint("plain post-termination outward swap execution gas",plainGas);
        emit log_named_uint("hooked post-termination outward swap execution gas",hookedGas);
        emit log_named_uint("incremental post-termination swap execution gas",hookedGas-plainGas);
        g=gasleft();change(-int256(uint256(INITIAL_L)));emit log_named_uint("full removal execution gas",g-gasleft());
    }
}
