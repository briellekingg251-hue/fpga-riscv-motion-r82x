import re,sys
def split(path):
    txt=open(path,encoding='utf-8',errors='replace').read()
    mods={}
    for m in re.finditer(r'^module\s+(\w+)(.*?)^endmodule',txt,re.S|re.M):
        mods[m.group(1)]=m.group(0)
    return mods
a=split(sys.argv[1]); b=split(sys.argv[2])
for k in sorted(set(a)|set(b)):
    if k in a and k in b:
        print(f"{k:22s}", "IDENTICAL" if a[k]==b[k] else "DIFF")
    else:
        print(f"{k:22s}", "only in", "A" if k in a else "B")
