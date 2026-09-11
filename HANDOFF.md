# GALS NoC — handoff note

Last updated: 2026-09-11. Merged to `main` as PR #2 (`9f20a94`); branch
`feature/2-ecc-injection-and-tid-guard` carries the ECC injection register, the `tid` guard,
and the bug #7 fix on top, not yet merged.

Read this first if you're picking the project up cold.

---

## 1. Where things stand

Seven real RTL bugs found. **All seven fixed.** Five confirmed on the board; bug #5's
trigger can no longer occur, so it is proved and simulated rather than observed failing;
bug #7's fix is proved and simulated but **not yet built or run on the board** (no board
on hand when it landed — section 3c says what to check when there is one).

| # | bug | found by | status |
|---|-----|----------|--------|
| 1 | `packet_arbiter` released an output port mid-packet, corrupting packets | sim | **fixed**, board-confirmed |
| 2 | `packet_arbiter` round-robin mask latched; one input took 100% of a contended port | sim | **fixed**, board-confirmed |
| 3 | `vc_port_arbiter` cross-blocks the two VCs; throughput collapse + deadlock | sim | **fixed**, board-confirmed |
| 4 | `traffic_node_agent` truncates a packet at window end; the downstream `packet_arbiter` then locks that output port forever | liveness watchdog, first board run | **fixed**, board-confirmed |
| 5 | `packet_arbiter` force-release could fire mid-packet when a source returned on the saturation cycle | formal | **fixed**, proved + simulated |
| 6 | out-of-range `tdest` routes off the mesh edge and stalls there forever, head-of-line-blocking the fabric | formal (mesh) | **fixed**, board-confirmed clean |
| 7 | the bug #6 / non-one-hot-`tid` ingress filters silently drop a rejected flit without closing its packet; a still-open VC packet then absorbs the next accepted flit and delivers it to the wrong node, and holds the destination router's grant meanwhile | formal (mesh) | **fixed**, proved + simulated, not yet on board |

Bugs 1-3 predate this work and would have shipped. None was caught by the five original
simulation tests or by the permutation hardware stress run.

### Verification status — all re-run against `1736d1b`

**Formal: 11 modules, 22/22 tasks pass, 0 failures.** Eight prove unbounded (basecase +
induction); three are bounded `bmc` because they tie state outside a FIFO to the FIFO's
contents, which induction can violate from an unreachable start state.

| unbounded (`prove`) | bounded (`bmc`) |
|---|---|
| `packet_arbiter`, `vc_port_arbiter`, `gray_counter`, `sync_2stage`, `async_fifo`, `async_fifo_fwft`, `dual_port_ram_ecc`, `gals_node_wrapper` | `vc_input_buffer`, `router_5port_mesh_vc`, `noc_mesh_2x2_vc` |

Every RTL module carrying datapath logic now has a `FORMAL` block. What has none is the
test infrastructure and the board tops (`traffic_node_agent`, `noc_stress_tester`,
`loopback_node_agent`, `uart_noc_host`, `uart_transceiver`, `gals_noc_top`,
`arty_stress_top`, `arty_gals_noc_wrapper`) — those are covered by simulation and the board.

**Simulation: 3/3 testbenches pass.**

| testbench | result |
|---|---|
| `tb_ecc_secded` | PASS — 23,792 exhaustive cases |
| `tb_traffic_node_agent` | PASS — 10/10 liveness checks |
| `tb_noc_stress_tester` | PASS — gap 136, 0 sequence errors, 203,504 flits, EAST 49% / NORTH 51%, ECC silent, no out-of-range dest |

**Hardware: both builds run clean on the Arty A7-100T.**

| build | result |
|---|---|
| stress (`PATTERN=1 VC_MODE=2`) | 0 sequence errors, liveness PASS on all 4 nodes, ECC 0/0, `dest_err_cnt` 0, node 00 at 97.0% utilisation, 80.2 MB/s, VC split 50/50 |
| UART (`arty_gals_noc_wrapper`) | 149-byte packet round-trips byte-identical; both VCs and both destinations echo; ECC and `dest_err` counters 0 across 1024 samples |

Logs in `hw_logs/`. The stress run is the silicon regression for bugs #4, #5 and #6 in one
shot — the previous hardware run of that exact config reported `liveness FAIL` on agent_01
and agent_11.

### Known gaps, stated plainly

- **The ECC alarm path is now proved in simulation, not yet on silicon.**
  `dual_port_ram_ecc.sv` gained a build-time fault injector: define `ECC_INJECT_SBE` to flip
  one bit of every codeword on its way into the RAM, or `ECC_INJECT_DBE` to flip two. With
  neither defined the write path is `encoded_wdata` unchanged, so the normal bitstream does
  not change at all. It is a `` `define ``, not a parameter, on purpose — a parameter would
  have to be threaded through `async_fifo` -> `async_fifo_fwft` -> `gals_node_wrapper` ->
  `gals_noc_top` -> top, touching four already-proved modules for no gain.

  | build | `ecc_sbe_cnt` | `ecc_dbe_cnt` |
  |---|---|---|
  | normal | 0 | 0 |
  | `ECC_INJECT_SBE` | **3** | 0 |
  | `ECC_INJECT_DBE` | 0 | **3** |

  Single-bit raises `single_err` alone and double-bit raises `double_err` alone, through
  encoder, RAM, decoder, sticky latch, CDC and counter. A disconnected flag cannot produce
  that.

  **Confirmed on silicon (2026-09-10).** Two bitstreams built back to back at
  `PATTERN=1 VC_MODE=2`, programmed to the Arty A7-100T:

  | build | `ecc_sbe_cnt` | `node_sbe` | `ecc_dbe_cnt` | traffic |
  |---|---|---|---|---|
  | normal | 0 | `0000` | 0 | 0 sequence errors, liveness PASS |
  | `ECC_INJECT_SBE` | **3** | **`1111`** | 0 | 0 sequence errors, liveness PASS |

  All four nodes flag, the double-bit counter stays 0, and traffic remains correct because
  SECDED repairs every word — which is exactly the behaviour a working single-bit path
  should show. The gap is closed: the counters reading 0 on a normal build now means the
  path is silent, not disconnected. Logs:
  `hw_logs/ila_stress_vc2_pattern1_20260910_clean.log` and `..._eccinject_sbe.log`.
  Remember to clear the define afterwards — `set_property verilog_define {} [current_fileset]`.
- **`dest_err_node[3:0]` is absent from the stress build's ILA** (its clock did not resolve),
  so per-node attribution is unavailable there. `dest_err_cnt` survives and answers whether
  it happened. `analyze_ila.py` says so rather than staying silent.
- **Bug #5 has no silicon failure to regress against** — the fix removes the trigger.
- **~~One-hot `tid` lives only in `assume`s~~ — now guarded, in the right place.**
  `gals_node_wrapper` checks `host_tid_ok` on its host ingress and ands it into the TX write
  enable, so a malformed `tid` never reaches a queue. A sticky flag crosses to `clk_noc`
  beside the ECC flags as `host_tid_err`; `gals_noc_top` ORs it with the mesh's own flag into
  `tid_err_node` / `tid_err_cnt` (both `mark_debug` + `dont_touch`).

  **The first attempt put this at the mesh boundary and that was the wrong layer.** The guard
  never fired, because `gals_node_wrapper` computes
  `w_en = s_host_valid && s_host_tid[v] && !tx_full[v]` and swallows the bad flit itself; the
  mesh only ever sees `noc_tx_tid`, which the wrapper's MUX builds one-hot by construction.
  Measured with a directed test (`BAD_TID` in `tb_noc_stress_tester`, forcing node 11's tid):

  | forced `tid` | before the guard | after |
  |---|---|---|
  | `00` | `tid_err_cnt` 0, node stalls 8,388,609 cycles, silent | `tid_err_cnt` 1, `node=1000`, stall attributed |
  | `11` | `tid_err_cnt` 0, **24 sequence errors** from the flit landing in both VCs | `tid_err_cnt` 1, `node=1000`, sequence errors **24 -> 1** |

  On hardware the clean build reports `tid_err` 0 with `node=0000` and its node probe
  present, so the guard costs nothing and reads correctly on silicon (2026-09-10 log above).

  The remaining error under `tid=11` is the packet in flight when the force was applied,
  which no ingress guard can help. Under `tid=00` the sender still stalls, correctly — it is
  sending garbage. What changed is that the stall is flagged and attributed instead of
  silent. The mesh-boundary guard is kept as a second line because it enforces the mesh's own
  contract, but it is not the one that catches this.

  **Formal now covers both guards without the one-hot `assume`.** Dropping it used to make
  `assert_eject_dest` fail at step 4 (node 0 emits `tdest=0100`); that was bug #7 (section
  3c), a dropped flit eating its packet's `tlast`. With the fix in, both `assume`s are gone:
  `noc_mesh_2x2_vc` passes bmc depth 10 with the solver free to send any `tid`, and
  `gals_node_wrapper` passes prove (basecase + induction) the same way, each with a cover
  showing the force-close path is actually exercised. The directed simulation above stays,
  because it measures the harm formal does not: the head-of-line stall other agents see.

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

## 3c. Bug #7 — a rejected flit drops silently instead of closing its packet

Found while investigating an unexplained counterexample noted in the bug #6 formal writeup
(`noc_mesh_2x2_vc.sby`, the one-hot `assume` on `s_tid` that could not be removed). Removing
that `assume` made `assert_eject_dest` fail at step 4: node 0 ejects a flit with
`tdest=0100`, which is not the destination of anything the host actually sent that looked
malformed. The original write-up guessed this was an AND-OR mux artefact from a non-one-hot
grant reaching the crossbar. **That guess was wrong.** The flit is real; it was just
delivered on the wrong packet.

### Root cause

Both ingress filters added for bug #6 — `dest_ok` (out-of-range `tdest`) and `tid_ok`
(non-one-hot `tid`), `noc_mesh_2x2_vc.sv` section 0/0b, mirrored at the host ingress in
`gals_node_wrapper.sv:111` — reject a bad flit by simply not asserting `r_valid`/`w_en` for
it. The flit vanishes. But `packet_arbiter` tracks packet boundaries purely by watching
`tlast` flow through; it has no idea a flit existed if the ingress filter never presented
it. If the rejected flit was meant to be the last flit of a packet, the filter has now
eaten the only `tlast` for that packet, and the arbiter/FIFO consider it still open.

Confirmed by decoding the BMC counterexample stimulus at node 0 (`s_tid`/`s_tdest` per
step):

| step | tid | tdest | tlast | filter | effect |
|---|---|---|---|---|---|
| 1 | `10` (VC1) | `0000` | 0 | pass | opens a VC1 packet addressed to node 0 |
| 2 | `11` (bad) | `0000` | **1** | **dropped** | the only `tlast` for that packet is lost; VC1 stays "open" downstream |
| 3 | `10` (VC1) | `0100` | 0 | pass | rides the still-open grant; ejected at node 0 anyway |

Step 4's `tdest=0100` is exactly step 3's flit — a real, correctly filtered flit that got
misdelivered because the packet it landed in was never supposed to still be open.

**Isolation:** re-adding an `assume` that forbids a rejected flit from carrying `tlast`
(`assume(!(s_tlast[i] && !tid_ok[i]))`) makes BMC pass clean through 12 steps with the
one-hot `assume` still removed (2h14m runtime, `abc bmc3`, no counterexample — see
`formal/noc_mesh_2x2_vc.sby`'s task list for how to reproduce; this experiment itself was
not checked in as a task). That isolates the mechanism precisely: the bug is not tid
reaching the router non-one-hot, it is **a dropped flit silently eating a `tlast`.**

### Why the exposure is worse than the formal model captures

The `.sby` header argues the ingress filters are safe because `tdest` is assumed constant
across a packet — true only if the host frames packets correctly, which is exactly the
property a corrupted `tid` or `tdest` calls into question. A host garbling `tid` is not a
host that can be trusted to still be sending a clean `tlast` stream. And the same shape
exists twice:

- `noc_mesh_2x2_vc.sv` — `dest_ok`/`tid_ok` filter, mesh-level ingress from all 4 nodes
- `gals_node_wrapper.sv:111` — `host_tid_ok` filter, per-node host ingress (`w_en =
  s_host_valid && s_host_tid[v] && !tx_full[v] && host_tid_ok`)

Both raise their sticky error flag (`dest_err`/`tid_err`) correctly — this is not an
unflagged failure. But the flag says "a bad flit arrived," not "a packet got merged with
the next one and delivered to the wrong node," which is the actual consequence once a VC
is left open.

### Fix — force-close on reject (design A), implemented

Two designs were on the table. **A, force-close on reject:** on any rejected flit, close
every VC at that ingress that has a packet open. **B, best-effort attribution:** close only
the VC the bad flit appears to target. A was chosen — B is materially more logic and more
corner cases (`tid=00` targets nothing, `tid=11` targets both) for a benefit that only
shows up when the host is already sending garbage, where "a neighbouring packet also got
truncated" is not disproportionate harm and "nothing gets silently misdelivered" is the
property that matters.

Same shape at both ingress sites:

- `noc_mesh_2x2_vc.sv` section 2.2 — per node, per VC: `pkt_open` (a head has been
  accepted, no `tlast` yet) and `pkt_dest` (that head's `tdest`, already through
  `dest_ok`). A rejected flit sets `close_pend` for every open VC. While any close is
  pending the node presents a synthetic flit to the router's LOCAL port — `tlast=1`,
  `tid` = that VC, `tdest` = the recorded head dest, data 0 — and holds `s_ready` at 0 so
  the host cannot interleave. LOCAL takes one flit per cycle, so two open VCs close over
  two cycles.
- `gals_node_wrapper.sv` — same tracker on the host side (`tx_pkt_open`/`tx_pkt_dest`/
  `tx_close_pend`), but each VC has its own FIFO write port, so both close in one cycle.
  `s_host_ready` is held low while closing.

The truncated packet arrives short at the **correct** node, with `dest_err`/`tid_err`
raised as before; the next packet starts as a clean head.

### Evidence

Formal, both with the one-hot `assume` **removed** so the solver sends any `tid`:

| script | mode | result | new covers |
|---|---|---|---|
| `noc_mesh_2x2_vc.sby` | bmc depth 10 (`abc bmc3`) | **PASS**, 7m42s — `assert_eject_dest` holds by itself now | `cover_force_close` step 4, `cover_deliver_after_close` step 5, `cover_tid_err_raised` |
| `noc_mesh_2x2_vc.sby` | cover depth 12 | PASS, all 13 reached | |
| `gals_node_wrapper.sby` | prove (basecase + induction) | **PASS** | |
| `gals_node_wrapper.sby` | cover | PASS | `cover_tx_force_close` step 7, `cover_tx_force_close_both` step 9 |

New assertions: `assert_local_in_range` / `assert_local_tid_onehot` (everything entering a
router via LOCAL, synthetic flits included, is in-range and one-hot),
`assert_close_pend_only_open` (never synthesise a `tlast` into a VC with nothing open — that
would be a one-flit phantom packet), `assert_host_held_while_closing` /
`assert_no_host_write_while_closing`. `assert_bad_dest_blocked` and
`assert_good_flit_passes` were widened to allow the synthetic flit through.
`assert_close_pend_only_open` in the wrapper is deliberately not gated on `f_past_valid`:
gated, induction starts from an unreachable bad state while the assert is off, the state
sits there because `clk_noc` need not tick, and it "fails" the moment the gate opens.

Simulation, `tb_noc_mesh_2x2_gals` 6/6 in both `TB default` and `HW_CLOCKS+HS_VC_ALT`,
totals identical to the checked-in `_FIXED` baselines (34 / 136 and 34 / 140 matched,
0 mismatched, 0 pending). `tb_noc_stress_tester` clean run identical to before
(142112 / 61104 / 81072 flits, 0 errors).

`tb_noc_stress_tester` with `BAD_TID` shows the harm the formal model does not measure.
`tid` of node 11 is forced bad for 2000 NoC cycles; the columns are `max_gap` of the
*other* three agents (normal 65 / 41 / 136):

| forced `tid` | before fix: gap 00 / 01 / 10 | after fix | why |
|---|---|---|---|
| `11` | **1209 / 886 / 1104** | 65 / 41 / 150 | the truncated packet held node 00's LOCAL grant for the whole 2000 cycles; agents 01 and 10 lost throughput (141632 -> 142128, 61040 -> 61488) |
| `00` | **1209 / 886 / 1104** | 65 / 41 / 136 | same; node 11 itself still stalls (8.4M-cycle gap), correctly — it is sending garbage |

So before the fix a single bad flit from one host was a ~1100-cycle stall for every other
node in the fabric, on top of the misdelivery. Sequence errors under `tid=11` went 1 -> 2;
the checker is per-flit and 6-bit-modulo (`traffic_node_agent` compares
`rx_seq` to `exp_seq[src][vc]`), so the count is "how many VC lanes saw a jump that was not
a multiple of 64," which shifts with a one-cycle timing change and is not a regression
signal. The `BAD_TID` runs report `FAIL` on that line by design — they are measurement
modes, not pass/fail regressions.

Hot-spot and permutation patterns cannot show the misdelivery itself in simulation:
every agent has a fixed `DEST_ID`, so a merged packet still goes where the next one would
have. That property rests on the formal proof.

### Not yet done

- **Not built or run on the board.** When one is available: `PATTERN=1 VC_MODE=2` stress
  build, confirm the clean run still reads `tid_err` 0 / `dest_err` 0 with all four
  `node` probes present and 0 sequence errors; the added state is two `pkt_open` bits, two
  4-bit `pkt_dest` and two `close_pend` bits per ingress, so timing should be unaffected
  but check the `clk_host` domain paths in `gals_node_wrapper`.
- `formal/run_wsl.sh` is a small helper that puts the OSS CAD Suite on `PATH` and runs
  `sby` from Git Bash on Windows (`MSYS_NO_PATHCONV=1 wsl -d Ubuntu-24.04 -- bash
  /mnt/d/.../formal/run_wsl.sh <file>.sby [task]`) — the `bash -c '... $PATH ...'` form
  breaks because Git Bash expands `$PATH` locally into a string with parentheses.

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
6. **~~Set Up Debug wrote its cores into `arty.xdc`~~ — fixed at the root.** The cause was
   one project property: `TargetConstrsFile` pointed at `arty.xdc`, the pins file, and the
   wizard always writes to whatever that names. It now points at `constrs_1/new/debug_auto.xdc`,
   and `arty.xdc` is back to pins-only (23 lines, verified identical to
   `backup_20260804/constrs/arty.xdc`).

   Better still, **the GUI step is gone**. `setup_debug.tcl` builds the ILA cores straight
   from the `MARK_DEBUG` nets, so the whole flow is scriptable and reviewable in git:

       open_run synth_1
       source .../setup_debug.tcl
       launch_runs impl_1 -to_step write_bitstream -jobs 8

   It groups nets into one core per clock domain and merges `foo[n]` bits into one wide
   probe, and it refuses to run if the target ever points back at `arty.xdc`.

   Three traps it works around, all found the hard way:

   - **`save_constraints` orders the file wrongly.** It writes every core's `probe0` block
     *before* all the `create_debug_core` lines, so re-reading the XDC at implementation
     gives `Debug core 'u_ila_0' was not found` and the run dies. The script therefore
     composes the XDC text itself, in the wizard's order.
   - **`save_constraints` also reformats every other file in `constrs_1`.** It collapsed the
     line continuations in `timing.xdc`'s commented-out reference constraints. The active
     `set_clock_groups` was unaffected, but writing the file directly avoids touching
     anything else.
   - **Clock lookup silently narrows probes.** `get_clocks -of_objects <net>` returns nothing
     for these nets, so the clock has to be found by walking to the driving cell — `-leaf`,
     since nets at a hierarchy boundary are driven by a module pin with no clock pin, then
     back through combinational logic for things like `ecc_single_err = |ecc_sbe`. That walk
     resolved `dest_err_node[0]` but not `[1..3]`, which would have made a 4-bit probe 1 bit
     wide: a working-looking ILA with missing data and no warning. Bits now inherit the
     clock of other bits in the same bus, and the script warns if probe bits ever fail to
     equal net count.
7. **Simulation is blind to fairness by default.** Test 4 sends one packet per node then
   stops — proves delivery, not bandwidth sharing. Test 6 (sustained contention) was added
   for exactly this and is what catches bug #2 class failures.
8. **`xelab.bat -generic_top "BAD_TID=2"` does not work from a shell on Windows.** The
   `.bat` wrapper re-tokenises its arguments and `=` is a `cmd` delimiter, so the generic
   arrives as `BAD_TID 2` (or `BAD_TID` alone) and elaboration fails with "not found in
   design"; calling `unwrapped/win64.o/xelab.exe` directly fails on `boost_regex.dll`.
   Vivado's own Tcl console is fine. From a shell, wrap the testbench instead — a
   one-line `module tb_wrap; tb_noc_stress_tester #(.BAD_TID(2)) u(); endmodule` compiled
   alongside it and elaborated as the top does the job.

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

  **The whole set is green, and every RTL module in the datapath now has one.** Eleven
  modules. Eight pass `prove` on both basecase *and* induction, so those are unbounded
  proofs; three are bounded (`bmc`), for the reason given below the table:

  | module | mode | result | cover |
  |---|---|---|---|
  | `packet_arbiter` | prove | PASS | PASS |
  | `vc_port_arbiter` | prove | PASS | PASS |
  | `gray_counter` | prove | PASS | PASS |
  | `sync_2stage` | prove | PASS | PASS |
  | `async_fifo` | prove | PASS | PASS |
  | `async_fifo_fwft` | prove | PASS | PASS (cover needs depth 40) |
  | `dual_port_ram_ecc` | prove | PASS | PASS |
  | `gals_node_wrapper` | prove, multiclock | PASS | PASS |
  | `vc_input_buffer` | bmc, depth 16 | PASS | PASS |
  | `router_5port_mesh_vc` | bmc, depth 16 | PASS | PASS |
  | `noc_mesh_2x2_vc` | bmc, depth 10 | PASS | PASS |

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

  **`vc_input_buffer` and `router_5port_mesh_vc` now have `FORMAL` blocks too.**
  `vc_input_buffer` is checked with a black-box shadow FIFO: the block keeps its own copy
  of what should be queued, using its own counters, and never touches inside `sync_fifo`.
  That one comparison covers the VC demux, the `{tlast,tdest,tdata}` pack/unpack slicing
  and FIFO ordering at once — head-of-queue must be exactly the flit written at that
  position, nothing lost, nothing duplicated, nothing crossing lanes.
  `router_5port_mesh_vc` checks the two pieces the arbiter proofs never reached: the XY
  decoder (one output port per valid flit, eject to LOCAL iff the flit is home) and the
  crossbar (grant one-hot across inputs *and* across VCs, output data equal to the granted
  input's, `m_tid` matching the granting VC, and no input granted by two output ports at
  once).

  **Both are `bmc`, not `prove`, and that is a limit of induction, not of the properties.**
  Both tie state that lives in a FIFO to state that lives outside it, and induction starts
  from a queue holding arbitrary contents. It can therefore invent "arbiter locked to an
  input whose head has already changed route", or "shadow queue disagrees with real queue",
  with no input history that reaches those states. The bounded runs go deep enough to fill
  and drain the queues several times over.

  **Finding: nothing enforces one destination per packet, and the router misroutes if that
  is broken.** The first router run produced a real counterexample on
  `assert_grant_matches_route_vc0` (out=NORTH, in=WEST): `packet_arbiter` holds an output
  port locked for the length of a packet, so if the head flit's `tdest` changes mid-packet
  the lock stays on the old output while the routing decoder points at the new one — and
  the crossbar still emits that flit out the locked port. It is a silent misroute; no flag
  is raised, and the arbiter only lets go after `STALL_MAX` (the bug #5 release path). The
  agents in this project do hold `tdest` constant per packet, so the board is not affected,
  but the RTL never checks it, and a new master that varied `tdest` mid-packet would break
  routing with no diagnostic. The assumption is now written explicitly in the `f_wf`
  generate block in `router_5port_mesh_vc.sv`, so the contract is at least recorded.

  **Two tooling notes for these two scripts.** Yosys's own SystemVerilog frontend cannot
  parse unpacked array ports (`output logic m_valid [NUM_VCS]` in `vc_input_buffer`), so
  both scripts use `plugin -i slang; read_slang` instead of `read_verilog -sv`. Slang has
  no `$onehot`/`$onehot0`, hence the local `f_onehot`/`f_onehot0` helpers, and it names
  assert cells straight from the label, so duplicate labels inside a plain `for` loop crash
  yosys in `rtlil.cc` (`count_id`) — that is why the router's properties sit in `generate`
  blocks with genvars, which give each label a unique hierarchical prefix.

  **`memory_map` is what makes these runs finish.** With the arrays left as memories, z3
  needed over 28 minutes to get 10 steps into `vc_input_buffer`; with `memory_map` the full
  depth-16 run takes 67 seconds. The router additionally needs `abc bmc3` rather than z3
  (z3 reached step 8 in 40 minutes and stalled; abc does all 16 steps in 99 seconds) —
  cover still runs on z3 because abc has no cover mode.

  `packet_arbiter` and `vc_port_arbiter` gained `` `ifndef FORMAL_TOP_INTEGRATION `` guards
  so the router run does not have to discharge their assertions again; the convention
  matches `gray_counter` and `sync_2stage`. Both still pass `prove` and `cover` on their
  own scripts, checked after the change.

  **`noc_mesh_2x2_vc` and `gals_node_wrapper` now have `FORMAL` blocks too, so no RTL
  module in the datapath is unproven any more.**

  The mesh layer is almost pure wiring: 36 hand-written `assign`s plus the edge tie-offs.
  That is exactly the shape a swapped-index bug hides in, and it is the kind a top-level
  testbench struggles to catch, because packets still move — they just arrive at the wrong
  node. Its two headline properties are `assert_eject_dest` (a flit ejected to node *i*'s
  LOCAL port really is addressed to node *i*, which is mesh-level delivery correctness and
  fails immediately if the `idx = y*2 + x` wiring is crossed) and `assert_edge_*` (no
  router ever drives a valid off the edge of the board).

  `gals_node_wrapper` is the GALS boundary itself. The FIFOs inside were already proved;
  what had never been checked is the glue around them — the strict-priority VC mux in each
  direction, the `{tlast,tdest,tdata}` pack/unpack, the `r_en` assembled from the far
  side's valid/tid/ready, and the ready↔full mapping. The heaviest property there is
  `assert_tx_no_pop_empty` / `assert_rx_no_pop_empty`: `r_en` is built from three separate
  signals, and if any term slipped it would pop an empty FIFO and hand garbage onward as a
  flit with no flag raised. It runs `multiclock on` — unlike `async_fifo.sby` and
  `async_fifo_fwft.sby`, which leave it off and therefore let yosys treat the two clocks as
  one, an easier problem than the real one. It passes `prove`, so this one *is* unbounded.

  **Two things had to be got right for the mesh run to mean anything.** The routers are
  read with `-D FORMAL_NO_ROUTER`, which switches off the router's own `FORMAL` block — not
  for speed, but because that block `assume`s well-formed traffic on its `s_*` inputs, and
  inside the mesh those are internal wires with drivers. Assumptions on driven wires can
  contradict each other and make every assertion pass vacuously: green while proving
  nothing. The router is proved separately, where its `s_*` really are free inputs. Second,
  the mesh *used to* assume `tdest` stays on the board. That assumption has since been
  replaced by a real range check in the RTL, described in its own entry below, so the
  formal environment now lets `s_tdest` take any of its 16 values and proves that nothing
  escapes off the edge.

  **One assertion I wrote was wrong, and the run caught it.** `assert_idle_tid` ("no tid
  while valid is low") failed at step 3. The router's crossbar computes `m_tid` from grants
  alone, `(2'b10 & {2{|grant_vc1}}) | (2'b01 & {2{|grant_vc0}})`, while `m_valid` also
  needs `buf_valid` — so when an arbiter holds a grant after its source vanished mid-packet
  (the bug #5 path), tid lingers with no valid. That is **not** a defect: AXI4-Stream
  leaves sideband signals don't-care while `tvalid` is low, and every consumer here gates
  tid with valid (`fifo_we = s_valid && s_tid[v]` in `vc_input_buffer`, `w_en =
  s_noc_valid && s_noc_tid[v]` in `gals_node_wrapper`). The assertion was stricter than the
  spec; it is now `assert_eject_tid_onehot0`, which checks the case that would actually
  hurt — a multi-hot tid would write one flit into both VCs downstream.

  **Also dropped: the ECC sticky-latch assertions.** They restated the RTL (`if (err) q <=
  1'b1;` with no clearing branch, so stickiness is structural) and were vacuous anyway,
  since `async_fifo` ties its ECC flags to 0 whenever `FORMAL` is defined. They also broke
  induction with an artefact — a start state where the manual past register is 1 while the
  latch is 0, which no transition reaches. The real ECC logic is covered by `tb_ecc_secded`
  (exhaustive) and the board counters, not here. `assert_ecc_sbe_out` / `assert_ecc_dbe_out`
  stay, because they check something real: both clock domains are ORed into the output.

  **Duplicated tie-off block in `noc_mesh_2x2_vc.sv`, found by this work and now removed.**
  Section 3 (the edge tie-offs) appeared twice. The first copy tied only `r_valid` and
  `m_rdy_wire`; the second tied `r_last`, `r_dst`, `r_dat` and `r_tid` as well. Every edge
  `r_valid` and `m_rdy_wire` therefore had two continuous assignments driving it, which
  SystemVerilog does not allow for a `logic` variable. Vivado and slang both accepted it
  (both copies drove the same constants, so behaviour was unaffected) but it was a latent
  portability problem, and the first copy was a strict subset of the second. Deleted in its
  own commit, separate from the formal work: 20 lines, no behavioural change. Verified by
  Vivado re-parsing all 17 files clean, every edge signal now having exactly one driver, and
  `noc_mesh_2x2_vc.sby`, `router_5port_mesh_vc.sby` and `vc_input_buffer.sby` all still
  passing.

  **Duplicate assert labels are a hazard in both frontends.** Slang names assert cells
  straight from the label, and classic `read_verilog` does too inside a genvar loop
  (`gals_node_wrapper` hit "a cell with the same name was already created" from a two-VC
  generate loop). Either put the properties in `generate` blocks with genvars, which give
  each label a unique hierarchical prefix, or unroll and give every label its own name.

  Every module in `sources_1/new/` that carries datapath logic now has a `FORMAL` block.
  What remains unproven is the test infrastructure and the board tops — `traffic_node_agent`,
  `noc_stress_tester`, `loopback_node_agent`, `uart_noc_host`, `uart_transceiver`,
  `gals_noc_top`, `arty_stress_top`, `arty_gals_noc_wrapper` — which are covered by
  simulation and by the board instead.
- **Out-of-range `tdest` is now rejected at the mesh boundary, and the fabric survives it.**
  `s_tdest` is 4 bits (x = `[3:2]`, y = `[1:0]`) and accepts up to 3 per axis, but the mesh
  is 2x2. Feeding in x=2/3 or y=2/3 made the XY decoder see `dx > MY_X` in every column and
  send the flit toward the edge, where `m_rdy_wire` is tied to 0 — the flit stalled there
  permanently and head-of-line-blocked everything behind it. No flag, no timeout: a single
  host with a wrong destination could hang the entire fabric.

  Section 0 of `noc_mesh_2x2_vc.sv` now computes `dest_ok[i]` per node and gates
  `r_valid[i][LOCAL]` with it, so a bad flit never enters the mesh. The alternatives were
  both worse: dropping `s_ready` only moves the stall to the sender, and clamping the
  address into range delivers the packet to a node nobody intended, silently. What it does
  instead is consume the flit normally and discard it, then raise a sticky flag. The sender
  never stalls, the mesh never clogs, and the malformed packet disappears whole — `tdest` is
  constant per packet, a contract the router already depends on.

  Reporting follows the ECC path exactly, because that path already works: a sticky flag per
  node out of the mesh, aggregated in `gals_noc_top` into `dest_err_node` and `dest_err_cnt`
  (both `mark_debug` + `dont_touch`, per gotcha 1), one `dest_err` output, and on
  `arty_stress_top` it joins `ecc_dbe_s` in both directions — `led[3]` lights and
  `led[1]`/`led[2]` go dark. A dropped packet can never reach its destination, so a pass
  light left on would be the same kind of lie the liveness watchdog was added to stop.

  The counter counts *nodes that have ever offended*, not flits dropped, because the flag is
  a level that latches — read it with `dest_err_node` to find the culprit. The flag is
  raised when a bad flit is *offered*, not when it is accepted: the fault is aiming off the
  board, not the handshake timing.

  Verification turned an assumption into a proof. The mesh's range `assume` is gone,
  `s_tdest` roams all 16 values, and `assert_edge_*` still holds, with
  `assert_bad_dest_blocked` and `assert_good_dest_passes` added so the filter is checked
  both for stopping bad flits *and* for leaving good ones alone. `cover_dest_err_raised` and
  `cover_mesh_alive_after_bad_dest` are both reached, so the filter is reachable and the
  mesh keeps delivering after it fires — containment demonstrated, not merely asserted. bmc
  now takes 391 s at depth 10, up from ~100 s, because unconstraining `tdest` widens the
  input space; all 9 covers pass. `tb_noc_stress_tester` gained a matching check and reports
  `DEST: err_cnt=0` on a clean run, with 203,504 flits delivered, max gap 136 and a 49/51
  arbiter split — identical to before the change, which is the point: legal traffic is
  untouched.

  One incidental fix came with it. `arty_stress_top.sv` declared `ecc_sbe_noc`/`ecc_dbe_noc`
  *after* the `gals_noc_top` instance driving them, so they were implicitly declared at the
  port connection first and `xvlog` rejected the file with "already implicitly declared".
  That was pre-existing — the committed version fails identically — and it stayed hidden
  because Vivado's synthesis front end tolerates it while the simulator's does not. The
  declarations moved above the instance, so `arty_stress_top` can be compiled by `xvlog` at
  all now. All 25 RTL and TB files parse clean.
- **UART build: built, bitstream and probes on disk.** `setup_uart_build.tcl` drives it
  (top = `arty_gals_noc_wrapper`). Synthesis gives **463** `MARK_DEBUG` nets = 440 + 20
  (`dest_err_node` 4 + `dest_err_cnt` 16) + 3 new taps. Implementation is clean:

  | | |
  |---|---|
  | bitstream | `impl_1/arty_gals_noc_wrapper.bit` (3.8 MB) |
  | probes | `impl_1/arty_gals_noc_wrapper.ltx` |
  | timing | WNS **+1.120 ns**, WHS **+0.021 ns**, TNS/THS 0 |
  | errors | 0 |
  | ILA | 5 cores / 56 probes / 463 bits, one core per clock domain |

  This top had left `ecc_single_err`, `ecc_double_err` and (once it existed) `dest_err`
  completely unconnected — errors detected and discarded, the same pattern as the original
  dangling-ECC bug. They are now tapped with `mark_debug` + `dont_touch` so the ILA can see
  them. They are deliberately **not** wired to the LEDs: this build's LEDs are UART activity
  indicators (`led[1]`/`led[2]` mirror rx/tx, `led[3]` is any-TX), not a pass/fail verdict
  like `arty_stress_top`'s, so there is no green light here that could lie. LED semantics
  are unchanged.

  **Run on hardware and working.** Programmed to the Arty A7-100T over Digilent JTAG; all 5
  ILA cores enumerate with exactly the probe counts `setup_debug.tcl` generated
  (9/17/10/10/10), which is end-to-end proof the scripted debug flow reaches silicon. A
  149-byte packet sent to node 3 (h11) on VC1 came back to node 00 byte-identical with
  `tlast` correct. Reading the `clk_noc` ILA core over 1024 samples: `ecc_sbe_cnt`,
  `ecc_dbe_cnt`, `dest_err_cnt` and every per-node flag are **0**.

  **`noc_host.py`'s VC field was wrong — a host-script bug, not RTL.** Its second packet
  never came back. `uart_noc_host.sv` does `tx_tid <= header_reg[6:5]`, passing the header's
  VC field straight through as the **one-hot** `tid` (`01` = VC0, `10` = VC1), but the
  script passed a lane *number*. So `vc_id=1` silently meant VC0, and `vc_id=0` produced
  `tid=00`, which matches no lane at all — and every consumer gates on `s_valid && s_tid[v]`,
  so those flits were dropped with no flag. Same silent-loss shape as the dangling-ECC bug.
  Confirmed on the board before changing anything:

  | dest | tid | echoed |
  |---|---|---|
  | 0101 | 01 (VC0) | yes |
  | 0101 | 10 (VC1) | yes |
  | 0100 | 01 (VC0) | yes |
  | 0100 | 10 (VC1) | yes |
  | 0100 | 00 (what the script sent) | **no** |

  All four valid one-hot combinations round-trip on both destinations and both VCs, so the
  fabric is fine. The header now builds `(1 << vc_id) << 5` and the RX display decodes
  one-hot back to a lane number; both packets return. Note this is the same one-hot `tid`
  contract the formal work assumes (`$onehot(s_tid)`) and that nothing in the RTL enforces.

  Two host-side traps worth remembering. Run it as `python -u`: with stdout piped to a file
  and the process killed by `timeout`, block buffering swallows the tail and makes a
  complete packet look truncated — that cost a false "147/149 flits, no tlast" alarm.
  And set `PYTHONIOENCODING=utf-8`, or the script dies on its own emoji under the cp1252
  console codepage before it prints anything.

  Host side: `noc_host.py` at 3,000,000 baud, `COM_PORT` hardcoded to `COM3` — verified
  present in Device Manager. Eight other test scripts sit alongside it.
- **Stress build re-run on hardware and fully green** (`PATTERN=1` hot-spot, `VC_MODE=2`
  alternate — the config that exposed bugs #3 and #4). Built with `setup_stress_build.tcl`
  then the scripted `setup_debug.tcl`: 1084 `MARK_DEBUG` nets, 5 ILA cores, 53 probes,
  1080 bits. Log: `hw_logs/ila_stress_vc2_pattern1_20260904.log`.

  | check | result |
  |---|---|
  | sequence errors | 0 — PASS |
  | liveness (all 4 nodes) | PASS — `stuck_seen`=0 everywhere |
  | ECC single / double | 0 / 0 — PASS |
  | `dest_err_cnt` | 0 — PASS |
  | node 00 local port | 97.0% utilisation, 80.2 MB/s injected |
  | VC split at agent_00 | 50.0% / 50.0% |
  | `max_gap` per agent | 219 / 40 / 138 / 108 cycles |

  This is the silicon regression for bugs #4, #5 and #6 in one run. The previous hardware
  run of this exact config reported `liveness FAIL` on agent_01 and agent_11; now every node
  moves throughout `S_RUN`, and the worst gap is 219 cycles against a 65536 threshold.

  The "arbiter fairness spread = 49.9%" line looks alarming but is not: it compares the
  three senders individually, while node 00's arbiter actually splits between two *input
  ports* — EAST carries agent_01 alone (48.3%) and NORTH carries agent_10 + agent_11
  (24.2 + 27.5 = 51.7%). That is the same ~50/50 the simulation reports (EAST 49% /
  NORTH 51%), so silicon and sim agree.

  `analyze_ila.py` gained a `dest_err` section alongside the ECC one; it predated the flag
  and would otherwise stay silent about it.
- **Two new traps in the scripted debug flow**, both found by running it and both now
  handled in `setup_debug.tcl`:
  - **Stale cores follow you across a build switch.** `open_run` applies all of `constrs_1`,
    including the *previous* build's `debug_auto.xdc`, so the design already contains
    `u_ila_0..N` wired to nets of a different top. `create_debug_core` then collides, and
    `get_clocks` starts returning ILA-derived clocks (`u_ila_0_clk_out1_clk_wiz_0`) instead
    of the real `clk_wiz` outputs — which mis-groups probes and ends in "debug port has N
    unconnected channels" at implementation. The script now deletes every pre-existing
    debug core first. This is gotcha 6 wearing a new hat: splitting the file stopped the
    *text* mixing, not the *state* carrying over.
  - **`debug_auto.xdc` must be `USED_IN = implementation` only.** It was created with the
    default `synthesis implementation`, so *synthesis* read it and baked the previous
    build's ILA cores straight into the netlist. The symptom is subtle: `setup_debug.tcl`
    reports clocks named `u_ila_0_clk_out1_clk_wiz_0` instead of `clk_out1_clk_wiz_0`.
  - **Deleting a debug core does not delete the clocks it created.** `delete_debug_core`
    removes the core, but the generated clock objects survive in that session, so
    `get_clocks` keeps returning the `u_ila_N_` names and probes get mis-grouped or dropped.
    `setup_debug.tcl` now maps such a name back to the real clock (`f_real_clock`). Running
    `setup_debug` in its own session, after synthesis, is the reliable pattern.
  - **Implementation must run in a fresh Vivado session.** Calling `launch_runs impl_1` in
    the same session that just wrote `debug_auto.xdc` produces a bitstream with no error and
    no debug cores at all — no `.ltx`, no ILA on the board. Vivado uses its cached
    constraint state rather than re-reading the file. Session A does synth + `setup_debug`,
    session B does implementation.
- `final_src/` diverges from `sources_1/new/` in 16 of 19 shared files. Stale July snapshot,
  historical reference only. Do not build from it.
