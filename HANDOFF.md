# GALS NoC — handoff note

Last updated: 2026-09-01. Branch `feature/1-testbenchs`, last commit `5b794ce`.

Read this first if you're picking the project up cold.

---

## 1. Where things stand

Three real RTL bugs were found. **All three are fixed, and all three are confirmed
in simulation and on the board.**

| # | bug | status |
|---|-----|--------|
| 1 | `packet_arbiter` released an output port mid-packet, corrupting packets | **fixed** |
| 2 | `packet_arbiter` round-robin mask latched; one input took 100% of a contended port | **fixed** |
| 3 | `vc_port_arbiter` cross-blocks the two VCs; throughput collapse + deadlock | **fixed** |
| 4 | `traffic_node_agent` truncates a packet at window end; the downstream `packet_arbiter` then locks that output port forever | **fixed** |

Bugs 1-3 predate this work and would have shipped. None was caught by the five original
simulation tests or by the permutation hardware stress run. Bug #4 was found by the
liveness watchdog on its very first board run — see section 3b.

---

## 2. How to run things

All from the Vivado Tcl console. Variables persist in the session — reset them explicitly.

### Simulation regression (~20-45 s)

    source .../run_sim_regression.tcl

Switches (set before sourcing):
- `set HW_CLOCKS 1` — Arty clock ratios (NoC 80 MHz, sink 100, senders 71.4/83.3/71.4)
  instead of TB defaults (NoC 250, sink 500, senders 125/333/100)
- `set HS_VC_ALT 1` — Test 6 alternates VC0/VC1 per packet, mirroring hardware `VC_MODE=2`
- `set SIM_DEBUG 1` — `vc_port_arbiter` override tracing (noisy; leave off normally)

Each run writes a self-describing log to `sim_logs/regress_<tag>_<stamp>.log`
(config header + full xsim output + summary).

Pass criteria: 6/6 tests, `Mismatched=0`, `Pending=0`.
All four switch combinations now pass; `HS_VC_ALT 1` used to fail on `Pending` (bug #3).

### Simulation without Vivado's project flow

`launch_simulation` is not required. The same regression runs straight off the sources with
`xvlog`/`xelab`/`xsim` from `C:/AMDDesignTools/2025.2/Vivado/bin`, which is much faster and
leaves no project state behind. Compile order that elaborates cleanly:

    sync_fifo dual_port_ram dual_port_ram_ecc ecc_secded_encode_8b ecc_secded_decode_8b
    gray_counter sync_2stage async_fifo async_fifo_fwft fwft_wrapper axis_perf_mon
    traffic_gen packet_arbiter vc_port_arbiter vc_input_buffer router_5port_mesh_vc
    noc_mesh_2x2_vc gals_node_wrapper gals_noc_top tb_noc_mesh_2x2_gals

Elaborate `work.tb_noc_mesh_2x2_gals` (not `xil_defaultlib.…` — that library only exists
inside the project), pass the switches as `-d HW_CLOCKS -d HS_VC_ALT -d SIM_DEBUG`, and
drive xsim with a `run all; quit` tclbatch. Verified to reproduce
`regress_hwclk_vcalt_dbg_20260819_150653.log` number-for-number before the fix went in.

### Hardware build (~5 min synth + impl)

    set PATTERN 1 ; set VC_MODE 0 ; source .../setup_stress_build.tcl

- `PATTERN` 0 = permutation (00<->11, 01<->10), 1 = hot-spot (01/10/11 -> node 00)
- `VC_MODE` 0 = VC0 only, 1 = VC1 only, 2 = alternate (the original default)

Then: Set Up Debug -> Run Implementation -> bitstream -> program -> Hardware Manager ->
**Trigger Immediately** -> export each ILA to CSV -> `python analyze_ila.py <csv-folder>`.

Expect **1064** `MARK_DEBUG` nets: 924 original + 4 `stuck_seen` + 96 `max_gap`
(24 bits x 4 agents) + 40 ECC (`ecc_sbe_node`/`ecc_dbe_node` 4 each, `ecc_sbe_cnt`/
`ecc_dbe_cnt` 16 each). 1024 means a build from before the ECC flags were wired;
928 means before `max_gap`; 924 means before the watchdog entirely; either way Set Up Debug hasn't been re-run since (gotcha 6) and
`analyze_ila.py` will say the liveness result is unprovable rather than claim a pass.
668 means the `mon_*` perf-monitor probes weren't picked up (gotcha 6). 0 means the top
module isn't `arty_stress_top`.

---

## 3. Bug #3 — fixed

### Symptom (before the fix)

| config | node 00 local port utilisation |
|---|---|
| hardware, `VC_MODE=0` (VC0 only) | **100.0%** |
| hardware, `VC_MODE=2` (alternating) | **57.5%** |
| sim, VC0 only | 94.9% (TB clocks) / 99.5% (HW clocks) |
| sim, alternating | collapses, then **deadlocks** |

Fairness is identical in both VC modes (48/28/24), so bug #2's fix is independent of this.

### Root cause (`vc_port_arbiter.sv`)

    assign vc1_is_active = |raw_grant_vc1 && !vc0_override;
    assign ready_vc0     = !vc1_is_active ? ready_out_vc0 : 1'b0;

`vc1_is_active` keyed off *"VC1's packet_arbiter holds a grant"*, **not** *"VC1 can actually
move a flit"*. The two VCs have genuinely independent downstream credits
(`ready_out_vc0` = `m_ready[out_p][0]`, `ready_out_vc1` = `m_ready[out_p][1]`), so gating
`ready_vc0` on VC1's grant re-coupled resources the VC design deliberately separated.
A VC1 packet stalled on a full downstream VC1 buffer blocked VC0 even when VC0's own
downstream buffer had room.

The anti-starvation override was the intended mitigation but had two problems:

1. It cost `STARVE_LIMIT` (64) idle cycles before firing, every episode.
2. Exit required VC0 to complete a **whole packet**:
   `if (|raw_grant_vc0 && ready_out_vc0 && |(tlast_vc0 & raw_grant_vc0))`.
   If VC0's packet then stalled, `vc0_override` latched and now **VC1** was blocked
   indefinitely. Blocking in both directions was the circular wait.

### The fix

Two changes, both in `vc_port_arbiter.sv`:

    assign vc1_can_move  = (|raw_grant_vc1) && ready_out_vc1;
    assign vc0_can_move  = (|raw_grant_vc0) && ready_out_vc0;
    assign vc1_is_active = vc1_can_move && !(vc0_override && vc0_can_move);

1. **VC1 only owns the shared output link on cycles it can actually move a flit.** The
   moment its downstream credit runs out it yields, and VC0 takes the link that same cycle
   instead of waiting 64. The two VCs share one physical link (`m_valid[out_p]` is a single
   wire), so the mutex itself is genuinely required — what was wrong was deciding it on
   grant-held rather than can-transfer.
2. **The override only blocks VC1 while VC0 is itself making progress** (`&& vc0_can_move`).
   If VC0 is also stuck, VC1 gets the link back. That is the edge that closed the circular
   wait; `vc0_override` can no longer block in both directions at once.

Plus a second override release path — `if (!(|valid_vc0))` — so an override can't outlive
the VC0 request that raised it. In practice this never fires in the regression (all 36
episodes release via normal packet completion); it's a safety net, not the fix.

Interleaving VC0 and VC1 flits on one physical link is legal by construction: the
downstream `vc_input_buffer` demuxes on `m_tid` into per-VC FIFOs. Packet continuity
*within* a VC is still held by `packet_arbiter`'s `LOCKED` state, which the fix doesn't
touch — `raw_grant_*` is unchanged, only which VC drives the link.

### Results

Regression, all four switch combinations, 6/6 tests, `Mismatched=0`, `Pending=0`:

| config | node 00 ingress, before | after | min fairness share |
|---|---|---|---|
| TB clocks, VC0 only    | 94.9% (Pending 0)  | **95.0%** | 26% |
| TB clocks, alternating | 9.5%  (Pending 13) | **77.8%** | 26% |
| HW clocks, VC0 only    | 99.5% (Pending 0)  | **99.5%** | 25% |
| HW clocks, alternating | 44.5% (Pending 11) | **97.2%** | 25% |

The VC0-only columns are unchanged to within run-to-run noise — the fix only touches
behaviour when both VCs contend. Test 2 (VC1 preemption) is byte-identical to the pre-fix
log, so VC1 keeps strict priority whenever it can actually move.

`SIM_DEBUG` override accounting, HW clocks + alternating:

| | before | after |
|---|---|---|
| triggers | 51 | 36 |
| releases | 47 | 36 |
| **latched (never released)** | **4** | **0** |
| median episode with VC1 blocked | 1.10 us | 0.39 us |
| total time VC1 blocked | 45.2 us | 19.2 us |

Logs: `sim_logs/regress_*_FIXED.log` (all five runs, headers say which switches).

Out-of-context synthesis of `router_5port_mesh_vc` (xc7a35ticsg324-1L, 80 MHz):
no latches, no combinational loops, WNS 3.207 ns -> **3.131 ns** (76 ps cost — `m_valid`
now depends on `m_ready`, one extra level), 866 -> **967 LUTs** per router, registers
unchanged at 199. About 400 extra LUTs across the 4-router mesh, ~2% of the part.

### Confirmed on hardware — 2026-09-01

`PATTERN=1 ; VC_MODE=2`, rebuilt from the fixed RTL, 924 `MARK_DEBUG` nets (this run
predates the liveness watchdog, which takes it to 928),
synthesis clean (0 errors, 0 critical warnings):

| | before | after |
|---|---|---|
| node 00 local port utilisation | 57.5% | **97.0%** |
| sequence errors, all agents | 0 | **0** |
| VC split at the sink | — | 50.0 / 50.0 |

Simulation predicted 97.2% for the same configuration; the board came in at 97.0%.
The 50/50 VC split confirms both channels flow — neither starves the other.
Log: `hw_logs/ila_vc2_pattern1_20260901_FIXED.log`.

The board's own `VC_MODE=2` figure is now essentially the `VC_MODE=0` figure, which is
what "the two VCs no longer cross-block" was supposed to mean.

## 3b. Bug #4 — a truncated packet wedges an output port permanently

Found by the liveness watchdog on its first hardware run. The watchdog reported
`agent_01, agent_11 -> FAIL` on a board showing 97.0% utilisation and zero sequence
errors, which looked like a false positive. It was not.

### What the board said

| agent | clk | tx flits | watchdog |
|---|---|---|---|
| agent_10 | 83.33 MHz | 3,904,706 | pass |
| agent_11 | 71.43 MHz | 3,904,642 | **FAIL** |

64 flits apart out of 3.9 million, opposite verdicts. The two that failed are exactly the
two 71.43 MHz nodes — the slowest clocks, hence (gotcha 4) the longest wall-clock windows.

### Root cause

`traffic_node_agent` left `S_RUN` the instant `win_cnt` saturated:

    S_RUN: begin
        win_cnt <= win_cnt + 1'b1;
        if (&win_cnt) state <= S_DRAIN;      // <-- ไม่สนขอบแพ็กเกจ
    end

`tx_tvalid` is `(state == S_RUN)`, so the agent could drop valid **mid-packet**, leaving a
half-packet in the fabric. The downstream `packet_arbiter` is then stuck:

- it is `LOCKED` on that input, waiting for a `tlast` that will never arrive
- `eop_transfer` can never fire
- the emergency unlock is gated on `!has_transferred`, which is false — that gate was
  deliberately narrowed to fix bug #1, and this is the hole it left

Measured directly at node 00's local port while the fabric was silent:

    idx0 LOCAL arb_vc0: state=1(LOCKED) locked_grant=00010(NORTH) valid=01000(EAST) has_xfer=1
    sink  : rx_tvalid=0 rx_tready=11     <- destination starving, willing to accept
    sender: tx_tvalid=1 tx_tready=10     <- agent_01 blocked on VC0, VC1 free

Locked on NORTH, which has nothing; EAST has data and is starved forever. Because the
windows are counted in **cycles**, the 100 MHz sink and the 83 MHz sender finish before the
71 MHz senders — and whichever node stops first strands a packet that kills the port for
everyone still running. That is why only the two slowest nodes tripped.

### Fix (applied to the agent)

Finish the current packet before leaving `S_RUN`:

    if (!win_full) begin
        win_cnt <= win_cnt + 1'b1;
        if (&win_cnt) win_full <= 1'b1;
    end
    if (win_full && (!TX_EN || (tx_fire && last_flit) || stuck_seen))
        state <= S_DRAIN;

A sink has no packet to finish, so it leaves immediately. The `stuck_seen` term is the
escape hatch: if the fabric really is dead, `tx_fire` never comes and the agent would
otherwise sit in `S_RUN` forever and never report anything.

Effect in simulation (`tb_noc_stress_tester`, PATTERN=1 VC_MODE=2):

| agent | worst gap before | after | tx flits before -> after |
|---|---|---|---|
| agent_01 | 37,171 | **41** | 122,210 -> 142,112 (+16%) |
| agent_11 | 37,245 | **106** | 61,154 -> 81,072 (+33%) |
| agent_10 | 136 | 136 | unchanged |

Worst gap across all agents: 37,245 -> **136 cycles**.

### The fabric fragility is NOT fixed

`packet_arbiter` still has no way to release a lock when a source vanishes mid-packet.
The agent no longer does that, so the symptom is gone — but any node that resets, loses
power, or is reprogrammed mid-packet will still wedge an output port until global reset.
A timeout on `LOCKED` would close it, **but that is exactly the machinery bug #1 was about
and it must not be applied blind.** Left open deliberately; see section 5.

### Confirmed on hardware — 2026-09-01

`PATTERN=1 ; VC_MODE=2`, 1024 `MARK_DEBUG` nets, same config as the failing run:

| agent | before | after | change | sim predicted |
|---|---|---|---|---|
| agent_01 | 33.25 MB/s | **38.70** | +16.4% | +16% |
| agent_11 | 16.62 MB/s | **22.08** | +32.9% | +32.9% |
| agent_10 | 19.39 MB/s | 19.39 | 0.0% | unchanged |
| total injected | 69.3 MB/s | **80.2** | +15.7% | — |
| liveness | FAIL (01, 11) | **PASS** | | |

Node 00's port reads 96.9%, unchanged from 97.0% — its window closes before the old stall
began, so that number never saw the bug. Zero sequence errors.

The simulation predicted each agent's delta to within a fraction of a percent, so
`tb_noc_stress_tester` can stand in for a board build when chasing this class of problem.
Log: `hw_logs/ila_bug4_watchdog_fix_vc2_pattern1_20260901.log`.

### Instrumentation

`stuck_seen` was a verdict with no evidence, so the threshold could only be guessed — and
the first guess (2^16, extrapolated from `traffic_gen`, a different module with a different
workload) sat right in the middle of the real distribution. There is now a `max_gap`
register per agent, `mark_debug`, reporting the longest silent stretch actually observed.
Set the threshold from that number, never from a guess. `STUCK_LOG` stays at 16, which is
~480x the measured worst gap of 136.

## 4. Gotchas that cost real time

1. **`mark_debug` does not prevent sweeping.** A register with no fanout is removed before
   Set Up Debug ever sees it. Use `dont_touch` too, or give it a real load.
2. **The pass LEDs used to lie — fixed, but mind the rebuild.** `traffic_node_agent`
   advances its FSM on a free-running cycle counter, so it reached `S_DONE` and asserted
   pass whether or not traffic was moving. The `VC_MODE=2` hardware run lit green on a
   deadlocked fabric.

   There is now a liveness watchdog: `stuck_cnt` resets on every transfer during `S_RUN`
   and latches `stuck_seen` after `2**STUCK_LOG` (default 16, ~0.8 ms at 80 MHz) silent
   cycles. `done` is gated on it, so `pass_group1/2` and `led[1]/led[2]` can no longer go
   green on a dead fabric. A sender proves liveness with `tx_fire`; a sink (`TX_EN=0`,
   i.e. agent_00 under `PATTERN=1`) has no TX by design and proves it with `rx_fire`
   instead — watching `tx_fire` there would false-fail every run.

   `stuck_seen` is a `mark_debug` net, and `analyze_ila.py` prints a `liveness:` verdict
   from it. **Until you re-run Set Up Debug, the probe isn't in the ILA** and the analyzer
   will say the green light is unprovable rather than pass it.

   Covered by `tb_traffic_node_agent.sv` (10 checks: healthy, dead, dies-midway,
   dies-then-revives, and heavy-backpressure-but-alive to catch a too-tight threshold).
   Reverting just the `done` gating fails 6 of the 10, so the test has real teeth.
3. **Node naming is inconsistent.** The testbench calls mesh idx1 "10" and idx2 "01";
   `gals_noc_top` calls idx1 "h01" and idx2 "h10". Map through the **index**
   (`idx = y*2 + x`, `tdest = {x[1:0], y[1:0]}`), never the label.
4. **Window durations differ per agent.** `WINDOW_LOG` counts cycles, not time, so a
   100 MHz node's window is shorter than a 71 MHz node's. Never compare raw counter totals
   across agents; `analyze_ila.py`'s conservation table handles this correctly.
   This is not only a reporting trap — nodes therefore **stop at different wall-clock
   times**, and that stagger is what exposed bug #4 (section 3b). Any reasoning about the
   tail of a run has to account for it.
5. **~~`DEBUG_BUILD` is no longer defined anywhere~~ — fixed by deleting the guard.**
   `loopback_node_agent` and `uart_noc_host` gated every ILA tap on `` `ifdef DEBUG_BUILD ``,
   which nothing defines, so the UART build had zero instrumentation. A define you have to
   remember to set had already been lost once, so the guard is gone rather than restored —
   the probes are now unconditional, matching `traffic_node_agent`.

   They also carried `mark_debug` **without** `dont_touch`. Those taps have no fanout, so
   even with the define restored they would have been swept before Set Up Debug saw them
   (gotcha 1). Both attributes are now present, and all 144 probes survive synthesis:
   296 -> **440** nets (37 x 3 loopback + 33 uart).
6. **Set Up Debug wrote its cores into `arty.xdc`** (pins + debug in one file). New
   `mark_debug` nets aren't probed until you re-run Set Up Debug. A clean pins-only
   `arty.xdc` is in `backup_20260804/constrs/`.
7. **Simulation is blind to fairness by default.** Test 4 sends one packet per node then
   stops — proves delivery, not bandwidth sharing. Test 6 (sustained contention) was added
   for exactly this and is what catches bug #2 class failures.

---

## 5. Still open, beyond bug #3

- **`packet_arbiter` cannot recover from a truncated packet** (section 3b). A source that
  dies mid-packet locks that output port until global reset. Not reachable from
  `traffic_node_agent` any more, but still true of the fabric. Any fix touches the same
  lock/unlock logic as bug #1 — run the full regression plus `tb_noc_stress_tester`
  before trusting one.
- Bug #4's fix and the liveness watchdog are both confirmed on hardware (section 3b).
- ~~Fairness spread of 50% (48/24/27) might be arbiter unfairness~~ — **closed, it is
  topology.** `tb_noc_stress_tester` now counts transfers per input port at `idx0`'s LOCAL
  arbiter and measures **EAST 49% / NORTH 51%** — round-robin is fair to within 1%.
  The agent-level split follows from the tree, not the arbiter: `agent_01` arrives alone on
  EAST, while `agent_10` and `agent_11` are already merged onto NORTH back at `idx2`, so
  fair 50/50 at this port necessarily yields 50/25/25 at the agents. Conservation confirms
  the wiring: EAST = 142,112 = agent_01's exact tx count; NORTH = 142,176 =
  61,104 + 81,072 exactly. The test asserts EAST stays within 45-55%.

  Note `PATTERN=0` is *not* the experiment for this — permutation deliberately gives every
  flow its own link with no output-port contention at all, so there is no split to measure.

  Still slightly uneven *within* NORTH (agent_10 43% / agent_11 57%), but most of that is
  gotcha 4: agent_10 runs at 83.33 MHz and agent_11 at 71.43 MHz, so agent_11's
  equal-cycle window is 17% longer in wall-clock time. Comparing their raw totals is
  exactly the trap gotcha 4 warns about.
- ~~ECC has never been exercised~~ — **done.** `tb_ecc_secded.sv` proves the SECDED (13,8)
  exhaustively: all 256 values clean, every single-bit flip (256 x 13), every double-bit
  flip (256 x C(13,2)), plus writes through a real `dual_port_ram_ecc` with bits flipped
  directly in `mem`. 23,792 cases, 0 failures. Mutating the decoder's data extraction or
  its single/double decision fails 1,904 and 23,248 cases respectively, so the test has
  teeth. The logic was correct all along.

  **The real defect was that nobody could hear it.** `ecc_single_err`/`ecc_double_err` were
  left dangling at `gals_node_wrapper` (`.ecc_double_err()`), so an uncorrectable error was
  detected and then discarded — corrupt data flowed on silently. Now wired end to end:

  - `async_fifo` qualifies the raw flags with `ecc_read_valid` (the cycle after a real
    read). Without this the decoder runs on an uninitialised RAM word and cries wolf
    before anything has been written.
  - `gals_node_wrapper` latches them sticky per clock domain (TX flags are `clk_noc`,
    RX flags are `clk_host`) and crosses the host ones over with `sync_2stage` — safe
    because a sticky flag never falls, the same argument used for the `done`/`err` flags.
  - `gals_noc_top` aggregates all four nodes into `ecc_sbe_node`/`ecc_dbe_node` and
    edge-counts them into `ecc_sbe_cnt`/`ecc_dbe_cnt`, all `mark_debug` + `dont_touch`.
  - `arty_stress_top` folds an uncorrectable error into `led[3]` **and gates the pass
    LEDs off it** — same lesson as the liveness watchdog: a green light that stays lit
    while data is corrupt is a green light that lies.

  `tb_noc_stress_tester` covers both directions: a clean run must show zero flags (catches
  false alarms), and `INJECT_ECC=1` flips two bits in live FIFO data and requires the flag
  to reach the top *and* the endpoint to see real sequence errors (247 of them).
  Note single-shot injection at a fixed address does not work — the FIFO overwrites an
  address faster than it is read, so the injector corrupts each word as it is written.

- **ECC scope limit:** SECDED guarantees correct-1 / detect-2 only. Three or more bit
  errors can be misreported as `single_err` with a bogus "correction" (the syndrome can
  point at positions 13-15, which do not exist in a 12-bit word). Not a bug, but do not
  read `ecc_single_err` as proof the data is good.
- **Formal now runs.** WSL `Ubuntu-24.04` + OSS CAD Suite in `/opt/eda`
  (Yosys 0.68, SBY 0.68, Z3 4.15.5). Yosys reads this SystemVerilog directly with
  `read_verilog -sv -formal` — no `sv2v` needed. Run with `cd formal && sby -f <file>.sby`.

  **`arbiter_formal.sby` never verified an arbiter.** It targets `hw_queue_descriptor`, a
  module from a different project (`gals_mpmc_scalable`); so does `mpmc.sby`. Both are dead.
  The earlier claim here that it guarded bug #1 was wrong. `formal/packet_arbiter.sby` is
  the first script that actually proves the arbiter, and it passes basecase **and**
  induction.

  **The whole set is now green.** Seven modules, `prove` passing on both basecase *and*
  induction, so these are unbounded proofs rather than bounded BMC:

  | module | prove | cover |
  |---|---|---|
  | `packet_arbiter` | PASS | PASS |
  | `vc_port_arbiter` | PASS | PASS |
  | `gray_counter` | PASS | PASS |
  | `sync_2stage` | PASS | PASS |
  | `async_fifo` | PASS | PASS |
  | `async_fifo_fwft` | PASS | PASS (cover needs depth 40) |
  | `dual_port_ram_ecc` | PASS | PASS |

  `vc_port_arbiter` is the one that mattered: `assert_vc1_yields_when_stalled` and
  `assert_no_vc1_during_override` were written for the bug #3 fix and had never been
  checked by anything. They hold, so the fix running on the board is formally sound, not
  just simulation-sound.

  `async_fifo_fwft`'s wrap-around cover in `gray_counter` needs depth 40, not 20: with
  `ADDR_WIDTH=4` the pointer is 5 bits, so wrapping takes ~32 increments. Depth limit, not
  a defect — confirmed by raising the depth.

  Scripts live in `formal/`, one per module, written fresh. The old ones in
  `sources_1/new/old/` were unrunnable regardless of tooling: their `[files]` sections name
  bare filenames while the sources are in `new/`. `arbiter_formal.sby` and `mpmc.sby` stay
  dead (wrong project); the rest are superseded.

  Still unproven by formal: `router_5port_mesh_vc`, `vc_input_buffer`, `noc_mesh_2x2_vc`
  and `gals_node_wrapper` have no `FORMAL` blocks at all, so there is nothing to run yet.
  Those are where a routing or crossbar bug would hide.
- **UART build**: synthesises clean again (440 `MARK_DEBUG` nets, 0 latches) and
  `setup_uart_build.tcl` now drives it, mirroring `setup_stress_build.tcl`. Adding the ECC
  ports to `gals_noc_top` did not break it. **Not yet implemented or run on hardware** —
  and note `arty.xdc` still holds the *stress* build's 64 debug-core lines, which reference
  `u_stress/agent_*` nets absent from this top. Synthesis ignores them (implementation-only
  constraints) but implementation will not, so Set Up Debug must be re-run for this top
  before Run Implementation; it overwrites the stale cores. That is gotcha 6 again, and the
  durable fix is to stop letting Set Up Debug write into the pins file at all.
- `final_src/` diverges from `sources_1/new/` in 16 of 19 shared files. Stale July snapshot,
  historical reference only. Do not build from it.
