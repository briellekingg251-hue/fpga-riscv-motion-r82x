"""Separate successful STA execution from actual internal timing closure."""
from pathlib import Path
import re,json,argparse
R=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('work');args=a.parse_args();W=R/args.work
assert W.resolve().parent==R
assert json.loads((W/'sta_receipt.json').read_text())['status']=='PASS'
reports=list((W/'report_timing').glob('*.rtr'));assert len(reports)==1
t=reports[0].read_text(errors='replace');design=re.search(r'Design Summary\s*:\s*([^\r\n]+)',t);assert design
rows=[];section=None
for l in t.splitlines():
 m=re.match(r'\s*((?:Setup|Hold|Recovery|Removal|Minimum Pulse Width|Max Delay|Min Delay|Max Skew) Summary\([^)]*\)):',l)
 if m:section=m[1];continue
 if section and l.strip().startswith('==='):section=None
 if not section:continue
 if section.startswith('Minimum Pulse Width'):
  m=re.match(r'\s*(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',l)
  if m:rows.append({'section':section,'launch':m[1],'capture':m[1],'WNS_ns':float(m[2]),'TNS_ns':float(m[3]),'failing_endpoints':int(m[4]),'total_endpoints':int(m[5])})
 else:
  m=re.match(r'\s*(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',l)
  if m:rows.append({'section':section,'launch':m[1],'capture':m[2],'WNS_ns':float(m[3]),'TNS_ns':float(m[4]),'failing_endpoints':int(m[5]),'total_endpoints':int(m[6])})
assert len(rows)>=6
assert all(any(row['section']==check+' Summary('+corner+' Corner)' for row in rows) for check in ['Setup','Hold','Recovery','Removal','Minimum Pulse Width'] for corner in ['Slow','Fast']), 'Missing timing class/corner'
failed=[r for r in rows if r['WNS_ns']<0 or r['TNS_ns']<0 or r['failing_endpoints']]
paths=[]
for p in re.split(r'(?m)^Startpoint\s*:',t)[1:]:
 fields={}
 for key in ['Endpoint','Path Group','Path Type','Path Class']:
  m=re.search(r'^'+re.escape(key)+r'\s*:\s*(.*)',p,re.M)
  if m:fields[key]=m[1].strip()
 m=re.search(r'Slack \((?:MET|VIOLATED)\)\s+(-?\d+\.\d+)',p)
 if m and float(m[1])<0:paths.append({'startpoint':p.splitlines()[0].strip(),**fields,'slack_ns':float(m[1])})
warnings=[]
for p in W.glob('*console.log'):
 warnings += [l.strip() for l in p.read_text(errors='replace').splitlines() if re.match(r'\s*[WC]:\s+(Timing-|STA-|SDC-|DRC-)',l)]
met=design[1].strip()=='All Constraints Met.' and not failed
j={'status':'PASS_REPORTED_INTERNAL_TIMING' if met else 'FAIL_REPORTED_INTERNAL_TIMING','STA_command_exit':0,'report':str(reports[0]),'design_summary':design[1].strip(),'summary_rows':rows,'failing_summary_rows':failed,'first_violated_paths':paths[:12],'timing_diagnostics':warnings,'external_IO_and_vendor_contract_signed_off':False,'CDC_routed_bus_bound_audit':'Separate exact endpoint/exception/skew audit still required'}
(W/'timing_assessment.json').write_text(json.dumps(j,indent=2));print(j['status']);print(json.dumps(failed,indent=2))
