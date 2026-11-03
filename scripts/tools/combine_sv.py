import os
import glob
import re

INPUT_DIR = "D:\\OpalFolder\\MyOwnProject\\FPGA\\GALS_Packet-Based_Fabric\\GALS_Packet-Based_Fabric.srcs\\sources_1\\new"
OUTPUT_FILE = "combined.sv"

EXTENSIONS = ("*.sv", "*.v", "*.svh", "*.vh")


def remove_comments(text):
    # ลบ block comment
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)

    lines = []

    for line in text.splitlines():
        # ลบ single-line comment
        line = re.sub(r'//.*', '', line)

        # ถ้าบรรทัดเหลือแต่ช่องว่าง ให้เก็บเป็น ""
        line = line.rstrip()

        if line.strip():
            lines.append(line)
        else:
            lines.append("")

    # ยุบหลายบรรทัดว่างให้เหลือแค่ 1 บรรทัด
    output = []
    blank = False

    for line in lines:
        if line == "":
            if not blank:
                output.append("")
            blank = True
        else:
            output.append(line)
            blank = False

    return "\n".join(output)

files = []
for ext in EXTENSIONS:
    files.extend(glob.glob(os.path.join(INPUT_DIR, ext)))

files = sorted(files)

with open(OUTPUT_FILE, "w", encoding="utf-8") as out:
    for file in files:
        print(file)
        with open(file, encoding="utf-8") as f:
            out.write(remove_comments(f.read()))
            out.write("\n")

print("Finished!")