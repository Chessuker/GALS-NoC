"""Print the last sample of every flag/counter probe in a folder of iladata*.csv (UART build has no agents)."""
import csv, glob, sys, os
want = ('ecc', 'dest_err', 'tid_err', 'flit_cnt', 'pkt_cnt', 'stall_cnt', 'rx_cnt', 'tx_cnt', 'echo', 'uart')
for f in sorted(glob.glob(os.path.join(sys.argv[1], 'iladata*.csv'))):
    rows = list(csv.reader(open(f, newline='')))
    hdr, radix, data = rows[0], rows[1], [r for r in rows[2:] if len(r) == len(rows[0])]
    if not data: continue
    last = data[-1]
    print(f"== {os.path.basename(f)}  samples={len(data)}")
    for h, rdx, v in zip(hdr, radix, last):
        if any(w in h.lower() for w in want):
            try: val = int(v, 16) if 'HEX' in rdx.upper() else int(v, 2) if 'BIN' in rdx.upper() else int(v)
            except Exception: val = v
            print(f"   {h:60s} {val}")
