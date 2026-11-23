// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Assessment-only tests against the UNCHANGED original implementation and fixture.
import {ExperimentTest} from "original/Experiment.t.sol";
import {ExperimentVault, ServiceHook, Compensation} from "experiment/Experiment.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

interface AssessmentVm {function expectRevert(bytes calldata reason) external;}

contract AssessmentTest is ExperimentTest {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    AssessmentVm constant avm=AssessmentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testAssessmentExactTimelineAndUnrelatedClaimant() public {
        eq(block.timestamp,1000,"initial timestamp");eq(hook.start(),1000,"activation time");
        eq(hook.end(),1300,"fixed end");eq(hook.secondsNow(),0,"no backdating");
        ok(address(escrow.token())!=address(a) && address(escrow.token())!=address(b),"separate payment token");
        ok(escrow.beneficiary()==MANAGER,"fixed recipient");
        (uint128 owned,,)=IPoolManager(address(pm)).getPositionInfo(vault.poolKey().toId(),address(vault),-120,120,0);
        (uint128 managerOwned,,)=IPoolManager(address(pm)).getPositionInfo(vault.poolKey().toId(),MANAGER,-120,120,0);
        eq(owned,1e18,"vault owns position");eq(managerOwned,0,"manager does not own position");
        uint256 principal0=a.balanceOf(address(vault));uint256 principal1=b.balanceOf(address(vault));
        warp(100);trade(router,180);
        (,int24 tick,,)=IPoolManager(address(pm)).getSlot0(vault.poolKey().toId());
        ok(tick==180 && !hook.qualified(),"actual out-of-range tick at 1100");
        eq(hook.qualifyingSeconds(),100,"old interval");eq(hook.last(),1100,"swap checkpoint time");
        warp(200);trade(router2,0);
        (uint160 returnedPrice,int24 returnedTick,,)=IPoolManager(address(pm)).getSlot0(vault.poolKey().toId());
        // Core can store tick -1 when a downward swap ends at the tick-0 word boundary.
        eq(returnedPrice,uint160(1<<96),"actual return price is the tick-0 target");
        ok(returnedTick>=-120 && returnedTick<120 && hook.qualified(),"actual in-range tick at 1200");
        emit log_named_int("assessment actual tick at 1200",returnedTick);
        eq(hook.qualifyingSeconds(),100,"outside interval earns zero");eq(hook.last(),1200,"second callback time");
        eq(pay.balanceOf(MANAGER),0,"manager received no advance payment");
        warp(300);eq(escrow.earned(),200e18,"independent expected integral 100+100");
        vm.prank(TRADER);escrow.claim();
        eq(hook.last(),1300,"claim closes accounting");eq(hook.qualifyingSeconds(),200,"persisted integral");
        eq(escrow.paid(),200e18,"paid");eq(pay.balanceOf(MANAGER),200e18,"fixed manager receives transfer");
        eq(pay.balanceOf(TRADER),0,"caller cannot redirect payment");eq(pay.balanceOf(address(escrow)),100e18,"residual remains escrowed");
        eq(a.balanceOf(address(vault)),principal0,"token0 untouched");eq(b.balanceOf(address(vault)),principal1,"token1 untouched");
        eq(vault.positionLiquidity(),owned,"core principal unchanged");eq(hook.swapCallbacks(),2,"two real callbacks");
        warp(500);vm.prank(TRADER);escrow.claim();eq(escrow.paid(),200e18,"no claim twice or after end");
        eq(pay.balanceOf(address(escrow)),100e18,"100 tokens have no automatic refund");
    }

    function testAssessmentFailedCoreRerangeRollsBack() public {
        warp(100);
        uint256 principal0=a.balanceOf(address(vault));uint256 principal1=b.balanceOf(address(vault));
        // New L is below core's per-tick limit but exceeds available token inventory.
        // The real core removes/re-adds transiently; mock-token settlement then panics.
        vm.prank(MANAGER);avm.expectRevert(abi.encodeWithSignature("Panic(uint256)",0x11));
        vault.rerange(-180,180,uint128(1e32));
        ok(vault.lower()==-120 && vault.upper()==120,"range restored");eq(uint256(vault.salt()),0,"salt restored");
        eq(vault.positionLiquidity(),1e18,"original core position restored");
        (uint128 attempted,,)=IPoolManager(address(pm)).getPositionInfo(vault.poolKey().toId(),address(vault),-180,180,bytes32(uint256(1)));
        eq(attempted,0,"failed position not left behind");
        eq(hook.qualifyingSeconds(),0,"pre-change checkpoint reverted atomically");eq(hook.last(),1000,"clock restored");
        ok(hook.qualified(),"qualification restored");eq(hook.secondsNow(),100,"live entitlement unchanged");
        eq(a.balanceOf(address(vault)),principal0,"token0 rollback");eq(b.balanceOf(address(vault)),principal1,"token1 rollback");
        vm.prank(MANAGER);vault.change(0); // Operation guard must also have rolled back.
        warp(300);escrow.claim();eq(escrow.paid(),300e18,"failed rerange loses no service history");
    }

    function testAssessmentTreasuryReadditionAfterTermination() public {
        warp(100);vm.prank(TREASURY);vault.terminate();
        change(-int256(uint256(vault.positionLiquidity())));
        warp(150);change(1e18);
        vm.prank(TREASURY);vault.rerange(-180,180,1e18);
        ok(hook.actualQualification(),"actual re-added position meets liquidity/range metric");
        ok(!hook.qualified() && hook.stopped(),"but agreement remains stopped");
        vm.prank(MANAGER);vm.expectRevert();vault.change(1);
        vm.prank(MANAGER);vm.expectRevert();vault.rerange(-120,120,1e18);
        trade(router,240);trade(router2,0);
        warp(500);escrow.claim();eq(escrow.paid(),100e18,"treasury actions cannot restart accrual");
    }

    function freshHook(ExperimentVault v) internal returns(ServiceHook h) {
        bytes32 hash=keccak256(abi.encodePacked(type(ServiceHook).creationCode,abi.encode(pm,v)));
        uint160 flags=Hooks.BEFORE_ADD_LIQUIDITY_FLAG|Hooks.AFTER_SWAP_FLAG;
        for(uint256 s;;s++) {
            address predicted=address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff),address(this),bytes32(s),hash)))));
            if((uint160(predicted)&Hooks.ALL_HOOK_MASK)==flags) return new ServiceHook{salt:bytes32(s)}(IPoolManager(address(pm)),v);
            require(s<500000,"salt search exhausted");
        }
    }

    function testAssessmentActivationAndExactMinimum() public {
        ExperimentVault v=new ExperimentVault(IPoolManager(address(pm)),TREASURY,MANAGER,a,b);
        ServiceHook h=freshHook(v);
        vm.prank(TREASURY);v.bind(h);pm.initialize(v.poolKey(),uint160(1<<96));
        vm.prank(TREASURY);vm.expectRevert();h.activate(); // Zero actual core liquidity.
        a.mint(address(v),1e26);b.mint(address(v),1e26);
        vm.prank(TREASURY);v.change(1e14);
        warp(100);vm.prank(TREASURY);vm.expectRevert();h.activate();
        ok(!h.active(),"failed activation is atomic");eq(h.secondsNow(),0,"no rejected-period credit");
        vm.prank(TREASURY);v.change(9e14);eq(v.positionLiquidity(),1e15,"exact minimum core L");
        Compensation e=new Compensation(pay,h,MANAGER);pay.mint(address(e),300e18);
        vm.prank(TREASURY);h.activate();eq(h.start(),1100,"late activation uses current timestamp");
        eq(h.end(),1400,"fixed duration from actual activation");eq(h.secondsNow(),0,"cannot backdate");
        warp(200);e.claim();eq(e.paid(),100e18,"exact-minimum qualification accrues since activation only");
        vm.prank(TREASURY);vm.expectRevert();h.activate();
    }

    function testAssessmentCapWithExcessFunds() public {
        pay.mint(address(escrow),100e18);
        warp(100);vm.prank(TRADER);escrow.claim();eq(escrow.paid(),100e18,"early earned versus paid");
        warp(500);vm.prank(TRADER);escrow.claim();eq(escrow.earned(),300e18,"earned clipped");
        eq(escrow.paid(),300e18,"excess funds cannot increase cap");eq(pay.balanceOf(MANAGER),300e18,"recipient");
        eq(pay.balanceOf(TRADER),0,"unrelated caller cannot take wages");
        escrow.claim();eq(escrow.paid(),300e18,"no double claim");
    }

    function testAssessmentPermissionlessCheckpointCannotRefresh() public {
        warp(100);vm.prank(TRADER);hook.checkpoint();
        eq(hook.qualifyingSeconds(),100,"anyone can settle existing interval");
        ok(hook.qualified(),"caller cannot supply qualification");
        vm.prank(TRADER);vm.expectRevert();hook.refresh();
        vm.prank(TRADER);vm.expectRevert();hook.terminate();
        warp(300);escrow.claim();eq(escrow.paid(),300e18,"checkpoint splitting cannot change entitlement");
    }
}
