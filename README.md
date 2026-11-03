# GALS-NoC

A 2x2 mesh network-on-chip with GALS (globally asynchronous, locally synchronous) nodes,
virtual channels and ECC-protected buffers, built and tested on a Digilent Arty board.

Start with [docs/WALKTHROUGH.md](docs/WALKTHROUGH.md) (Thai: [docs/WALKTHROUGH.th.md](docs/WALKTHROUGH.th.md)).
The dated working log with every silicon result is [docs/HANDOFF.md](docs/HANDOFF.md).

## Layout

| path | what |
|---|---|
| `GALS_Packet-Based_Fabric.xpr` | Vivado project; must stay next to `GALS_Packet-Based_Fabric.srcs/` |
| `GALS_Packet-Based_Fabric.srcs/` | RTL, testbenches, constraints, IP `.xci` |
| `formal/` | SymbiYosys scripts, one per module; `run_wsl.sh` runs them |
| `scripts/vivado/` | Tcl: simulation regression, build setup, scripted ILA, batch flow |
| `scripts/ila/` | Python: analyse ILA CSV exports and fault-campaign captures |
| `scripts/host/` | Python: UART host (`noc_host.py`, `uart_roundtrip.py`); `demos/` holds the image/video/stress experiments |
| `scripts/tools/` | `combine_sv.py` (concatenate sources for sharing) |
| `logs/sim/`, `logs/hw/` | regression logs and ILA captures that back the numbers in the docs |
| `docs/` | walkthrough, handoff log, Tcl snippets |
| `garbage/` | old snapshots and superseded files; local only (ignored by git), see `garbage/README.md` on the machine that has it. The full history is in `GALS-NoC-Archive` |

Vivado batch scripts run from the repo root, for example
`vivado -mode batch -source scripts/vivado/batch_impl.tcl -tclargs arty_stress_top`.
The Tcl scripts open the project at the absolute path
`D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric`; change `proj` / `proj_dir`
at the top of each script if the repo lives elsewhere.
