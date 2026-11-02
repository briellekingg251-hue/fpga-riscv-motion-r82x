import re,sys,difflib
def split(path):
    txt=open(path,encoding='utf-8',errors='replace').read()
    return {m.group(1):m.group(0) for m in re.finditer(r'^module\s+(\w+)(.*?)^endmodule',txt,re.S|re.M)}
a=split(sys.argv[1]); b=split(sys.argv[2])
for k in sys.argv[3:]:
    d=list(difflib.unified_diff(a[k].splitlines(),b[k].splitlines(),lineterm='',n=1))
    print(k, len(d)); print("\n".join(d[:60]))
