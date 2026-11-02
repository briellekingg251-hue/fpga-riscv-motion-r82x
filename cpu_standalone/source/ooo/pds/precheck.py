# precheck.py <native top.v>: flag constructs PDS cannot synthesize
import re, sys
bad = re.compile(r'\$(countones|onehot0?|clog2\s*\(\s*[a-z_]|display|fatal|finish|random|isunknown)')
n = 0
for i, l in enumerate(open(sys.argv[1], encoding='utf-8', errors='replace'), 1):
    if bad.search(l):
        print(f"{i}: {l.rstrip()[:120]}"); n += 1
print("precheck:", "OK" if n == 0 else f"{n} suspicious lines")
sys.exit(1 if n else 0)
