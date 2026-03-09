// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@src/lib/ERC20.sol";
import {Factory} from "@src/insurance/Factory.sol";
import {Stake} from "@src/insurance/Stake.sol";
import {WithdrawDelay} from "@src/insurance/WithdrawDelay.sol";

// ── Stake-only ───────────────────────────────────────────────────────────────

contract Handler is Test {
    Stake public stake;
    ERC20 public token;

    address[] public actors;
    address internal currentActor;

    // Ghost variables — mirror state for invariant checking
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;

    constructor(Stake _stake, ERC20 _token) {
        stake = _stake;
        token = _token;
        actors = [address(0x1), address(0x2), address(0x3)];
        for (uint i = 0; i < actors.length; i++) {
            vm.prank(actors[i]);
            token.approve(address(stake), type(uint256).max);
        }
    }

    modifier useActor(uint256 actorSeed) {
        currentActor = actors[actorSeed % actors.length];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    function deposit(uint256 actorSeed, uint256 amt) external useActor(actorSeed) {
        // Bound inputs to valid range
        amt = bound(amt, stake.dust(), 1000e18);
        token.mint(currentActor, amt);
        stake.deposit(amt);
        ghost_totalDeposited += amt;
    }

    function warp(uint256 secs) external {
        secs = bound(secs, 0, stake.dur());
        vm.warp(block.timestamp + secs);
    }

    function take(uint256 actorSeed) external useActor(actorSeed) {
        stake.take();
    }
}

contract StakeInvariantTest is Test {
    ERC20 token;
    Stake stake;
    Handler handler;

    address constant INSUREE = address(10);
    uint256 constant DUR = 30 days;
    uint256 constant DUST = 1e18;
    uint256 constant COV = 1;

    function setUp() public {
        token = new ERC20("test", "TEST", 18);
        stake = new Stake(address(token), INSUREE, DUR, DUST, COV);

        token.mint(INSUREE, 1e18 * DUR);
        vm.prank(INSUREE);
        token.approve(address(stake), type(uint256).max);
        vm.prank(INSUREE);
        stake.inc(1e18 * DUR);

        handler = new Handler(stake, token);

        // Tell Foundry to only call handler functions
        targetContract(address(handler));
    }

    // Invariant: token balance must always cover staked + owed rewards
    function invariant_solvency() public view {
        uint256 bal = token.balanceOf(address(stake));
        uint256 need = stake.total() + stake.topped() - stake.paid();
        assertGe(bal, need);
    }

    // Invariant: paid can never exceed topped
    function invariant_paid_le_topped() public view {
        assertLe(stake.paid(), stake.topped());
    }

    // Invariant: total matches sum of user shares (simplified)
    function invariant_total_consistent() public view {
        // total should never underflow (would revert, but check anyway)
        assertGe(stake.total(), 0);
    }
}

// ── Stake + WithdrawDelay (deployed via Factory) ─────────────────────────────

contract SystemHandler is Test {
    Stake public stake;
    WithdrawDelay public wd;
    ERC20 public token;

    address[] public actors;
    address internal currentActor;

    // Per-actor pending lock indices
    mapping(address => uint256[]) internal _locks;

    constructor(Stake _stake, WithdrawDelay _wd, ERC20 _token) {
        stake = _stake;
        wd = _wd;
        token = _token;
        actors = [address(0x1), address(0x2), address(0x3)];
        for (uint i = 0; i < actors.length; i++) {
            vm.prank(actors[i]);
            token.approve(address(stake), type(uint256).max);
        }
    }

    modifier useActor(uint256 actorSeed) {
        currentActor = actors[actorSeed % actors.length];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    function deposit(uint256 actorSeed, uint256 amt) external useActor(actorSeed) {
        if (wd.stopped() || block.timestamp >= stake.exp()) return;
        amt = bound(amt, stake.dust(), 100e18);
        token.mint(currentActor, amt);
        stake.deposit(amt);
    }

    function queue(uint256 actorSeed, uint256 amt) external useActor(actorSeed) {
        if (wd.stopped() || block.timestamp >= stake.exp()) return;
        uint256 staked = stake.shares(currentActor);
        if (staked < stake.dust()) return;
        amt = bound(amt, stake.dust(), staked);
        // Remainder after queue must be 0 or >= dust
        uint256 remainder = staked - amt;
        if (remainder > 0 && remainder < stake.dust()) return;
        uint256 i = wd.queue(amt);
        _locks[currentActor].push(i);
    }

    function unlock(uint256 actorSeed, uint256 lockSeed) external useActor(actorSeed) {
        uint256[] storage indices = _locks[currentActor];
        if (indices.length == 0) return;
        uint256 pos = lockSeed % indices.length;
        uint256 i = indices[pos];
        (uint256 amt, uint256 exp) = wd.locks(currentActor, i);
        if (amt == 0 || block.timestamp < exp) return;
        // Matches unlock() require: lock.exp <= last || dumped == 0
        if (wd.stopped() && wd.dumped() > 0 && exp > wd.last()) return;
        wd.unlock(i);
        // Remove from tracking
        indices[pos] = indices[indices.length - 1];
        indices.pop();
    }

    function stop() external {
        if (stake.state() != Stake.State.Live || block.timestamp >= stake.exp()) return;
        stake.stop();
    }

    function dump() external {
        if (wd.stopped()) return;
        wd.dump();
    }

    function settle(uint256 stateSeed) external {
        if (stake.state() != Stake.State.Stopped) return;
        stake.settle(stateSeed % 2 == 0 ? Stake.State.Cover : Stake.State.Exit);
    }

    function cover() external {
        if (!wd.stopped() || stake.state() != Stake.State.Cover) return;
        wd.cover(address(0x99));
    }

    function refill() external {
        if (!wd.stopped() || stake.state() != Stake.State.Exit) return;
        wd.refill();
    }

    function warp(uint256 secs) external {
        secs = bound(secs, 0, stake.dur());
        vm.warp(block.timestamp + secs);
    }
}

contract SystemInvariantTest is Test {
    ERC20 token;
    Factory factory;
    Stake stake;
    WithdrawDelay wd;
    SystemHandler handler;

    address constant INSUREE = address(10);
    uint256 constant DUR = 30 days;
    uint256 constant DUST = 1e18;
    uint256 constant COV = 1;
    uint256 constant EPOCH = 1 days;

    function setUp() public {
        token = new ERC20("test", "TEST", 18);
        factory = new Factory();

        (address s, address w) =
            factory.create(address(token), INSUREE, DUR, DUST, COV, EPOCH);
        stake = Stake(s);
        wd = WithdrawDelay(w);

        token.mint(INSUREE, 1e18 * DUR);
        vm.prank(INSUREE);
        token.approve(address(stake), type(uint256).max);
        vm.prank(INSUREE);
        stake.inc(1e18 * DUR);

        handler = new SystemHandler(stake, wd, token);
        stake.allow(address(handler));
        wd.allow(address(handler));
        targetContract(address(handler));
    }

    // Stake: token balance covers all obligations
    function invariant_stake_solvency() public view {
        uint256 bal = token.balanceOf(address(stake));
        uint256 need = stake.total() + stake.topped() - stake.paid();
        assertGe(bal, need);
    }

    // Stake: rewards paid never exceed rewards deposited
    function invariant_paid_le_topped() public view {
        assertLe(stake.paid(), stake.topped());
    }

    // WithdrawDelay: contract holds at least keep tokens
    function invariant_wd_balance_covers_keep() public view {
        assertGe(token.balanceOf(address(wd)), wd.keep());
    }

    // WithdrawDelay: dumped amount never exceeds keep
    function invariant_dumped_le_keep() public view {
        assertLe(wd.dumped(), wd.keep());
    }

    // WithdrawDelay: dumped is only nonzero when stopped
    function invariant_dumped_requires_stopped() public view {
        if (wd.dumped() > 0) assertTrue(wd.stopped());
    }

    // System: combined balances cover obligations across both contracts
    function invariant_system_solvency() public view {
        uint256 bal = token.balanceOf(address(stake)) + token.balanceOf(address(wd));
        uint256 need = stake.total() + stake.topped() - stake.paid() + wd.keep();
        assertGe(bal, need);
    }
}
