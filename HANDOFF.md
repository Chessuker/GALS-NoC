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

Expect **1024** `MARK_DEBUG` nets: 924 original + 4 `stuck_seen` + 96 `max_gap`
(24 bits x 4 agents). 928 means a build from before `max_gap` was added; 924 means before
the watchdog entirely; either way Set Up Debug hasn't been re-run since (gotcha 6) and
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
5. **`DEBUG_BUILD` is no longer defined anywhere.** `loopback_node_agent` and
   `uart_noc_host` gate all their ILA taps on it, so the UART build currently has zero
   instrumentation and the old `debug.xdc` would fail against it.
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
- **Fairness is 48.3/24.2/27.5 (spread ~50%) on hardware** — likely topology, not a bug.
  `idx0`'s LOCAL port has two inputs: EAST (agent_01) and NORTH (agent_10 + agent_11), so
  round-robin at each level gives 50/25/25, which is close to what is now measured. Before
  bug #4 was fixed it read 48/28/24 with agent_11 unfairly low; fixing the wedge moved
  agent_11 back up to parity with agent_10, which is what the tree shape predicts.
  A `PATTERN=0` run (all nodes equidistant) would settle it — if the spread collapses
  there, close this item.
- (historical) **Fairness was 48/28/24 (spread 50%).** Unchanged by the bug #3 fix,
  and identical in `VC_MODE=0` and `VC_MODE=2`, so it is not a side effect of this work —
  but it is the one number the fix did not move. Simulation agrees (min share 25-26%,
  which clears Test 6's 10% bar, so the regression will not flag it). `agent_01` is
  mesh idx1 (gotcha 3) and sits one hop from node 00 while idx2/idx3 converge, so some
  of the spread is topology rather than arbitration — worth confirming before treating
  it as a bug.
- ECC (`ecc_secded_*`, `dual_port_ram_ecc`) has never been exercised — no error injection.
- Seven formal `.sby` files sit unused in `sources_1/new/old/`. `arbiter_formal.sby` claims
  to prove "channel cannot be stolen mid-packet" — plausibly catches bug #1 at source, and
  a liveness property would catch bug #2. The `FORMAL` block in `vc_port_arbiter.sv` was
  updated alongside the bug #3 fix (`assert_no_vc1_during_override` is now conditioned on
  `vc0_can_move`, plus new `assert_vc1_yields_when_stalled` and two covers), but **none of
  it has been run** — no solver is installed here.
- UART build (`arty_gals_noc_wrapper`) not rebuilt since `debug.xdc` was dropped (gotcha 5).
- `final_src/` diverges from `sources_1/new/` in 16 of 19 shared files. Stale July snapshot,
  historical reference only. Do not build from it.
