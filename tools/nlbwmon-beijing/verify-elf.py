import json, re, sys
lock=json.load(open(sys.argv[1]))
text=open(sys.argv[2]).read()
needed=set(re.findall(r"Shared library: \[(.*?)\]", text))
expected=set(lock["expected_needed"])
if needed != expected:
    raise SystemExit(f"ABI mismatch: expected {sorted(expected)}, got {sorted(needed)}")
print("PASS: target ELF dependencies match the installed router ABI")
