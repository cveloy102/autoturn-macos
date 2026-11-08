#!/usr/bin/env python3
"""Refresh bundled FQDN suffix seeds from a pinned domain-list-community revision.
Single-label TLDs and regex rules cannot be represented by AutoTurn's suffix UI;
they are counted in provenance rather than interpreted as executable patterns.
"""
import concurrent.futures, ipaddress, json, re, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
REPO='https://api.github.com/repos/v2fly/domain-list-community'
with urllib.request.urlopen(REPO+'/git/ref/heads/master',timeout=25) as r:
    sha=json.load(r)['object']['sha']
assert re.fullmatch('[a-f0-9]{40}',sha)
base='https://raw.githubusercontent.com/v2fly/domain-list-community/'+sha+'/'
roots=['google','github','discord','anthropic']
texts={}; pending=set(roots)
def fetch(tag):
    assert re.fullmatch('[a-z0-9_-]+',tag)
    with urllib.request.urlopen(base+'data/'+tag,timeout=25) as r:data=r.read(700001)
    assert len(data)<=700000
    return tag,data.decode('utf-8')
while pending:
    assert len(texts)+len(pending)<=128
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for tag,text in pool.map(fetch,sorted(pending)):texts[tag]=text
    pending=set()
    for text in texts.values():
        for line in text.splitlines():
            value=line.split('#',1)[0].strip().split()
            if value and value[0].startswith('include:'):
                tag=value[0][8:]
                if tag not in texts:pending.add(tag)

def domains(tag,seen=None):
    seen=set() if seen is None else seen
    if tag in seen:return set(),0
    seen.add(tag);result=set();omitted=0
    for line in texts[tag].splitlines():
        parts=line.split('#',1)[0].strip().split()
        if not parts:continue
        value=parts[0]
        if value.startswith('include:'):
            child,skip=domains(value[8:],seen);result.update(child);omitted+=skip;continue
        if value.startswith(('full:','domain:')):value=value.split(':',1)[1]
        if '.' not in value or ':' in value or not re.fullmatch(r'[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)+',value):omitted+=1;continue
        if any(p.startswith('-') or p.endswith('-') or '_' in p for p in value.split('.')):omitted+=1;continue
        result.add(value.lower().rstrip('.'))
    return result,omitted
seed_path=ROOT/'Resources/Routing/seed.json';seed=json.loads(seed_path.read_text())
byid={s['id']:s for s in seed['services']};proof={}
for tag in roots:
    values,omitted=domains(tag)
    row=byid.get(tag)
    if row is None:
        row={'id':tag,'name':{'google':'Google','anthropic':'Anthropic / Claude'}.get(tag,tag),'sourcePath':'source1/'+tag+'.txt','domains':[]}
        seed['services'].append(row)
    row['domains']=sorted(set(row['domains'])|values)
    proof[tag]={'fqdnSuffixes':len(values),'unrepresentableRulesOmitted':omitted}
    print(tag,proof[tag])
# Include the public IP lists too: a newly added service must have both
# protections before the first daily network refresh runs.
geo='68c48de0d53b246a5255fbce49241328ecea2eeb'
for tag in ['google','anthropic']:
    with urllib.request.urlopen('https://raw.githubusercontent.com/Ground-Zerro/Geo-Aggregator/'+geo+'/source1/'+tag+'.txt',timeout=25) as r:
        lines=r.read(700001).decode().splitlines()
    ranges={str(ipaddress.ip_network(line.strip(),strict=False)) for line in lines if line.strip() and not line.startswith('#')}
    row=next(s for s in seed['services'] if s['id']==tag)
    row['domains']=sorted(set(row['domains'])|ranges)
    proof[tag]['ipRanges']=len(ranges)
seed_path.write_text(json.dumps(seed,ensure_ascii=False,indent=2)+'\n')
(ROOT/'Resources/Routing/domain-seed-provenance.json').write_text(json.dumps({'repository':'v2fly/domain-list-community','commit':sha,'geoAggregatorCommit':geo,'groups':proof},indent=2)+'\n')
with urllib.request.urlopen(base+'LICENSE',timeout=25) as r:license=r.read()
(ROOT/'Resources/Routing/domain-seed-LICENSE.txt').write_bytes(license)
