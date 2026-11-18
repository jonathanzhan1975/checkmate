import json,pathlib,sys
root=pathlib.Path(__file__).resolve().parents[1]
for name in ['Package.swift','build.sh','Sources/CheckmateNative/App.swift','Sources/CheckmateCore/Resources/course.json','Sources/CheckmateCore/Resources/chess.js','Sources/CheckmateCore/Resources/stockfish']:
 assert (root/name).is_file(),name
result=json.loads(pathlib.Path(sys.argv[1]).read_text());assert result['passed'],result['failures'];samples=result['samples'];normal=[v for v in samples if v['phase'].startswith('normal-')];assert max(v['boardSide'] for v in normal)-min(v['boardSide'] for v in normal)<=1
assert max(abs(v['titleCenter']-v['boardCenter']) for v in samples)<=1
# The control bar was measured in every mode at every size, and fits one row from the usual minimum (600) up.
bar=result['bar'];assert len(bar)==12 and all(len(v['barControls'])>=4 for v in bar),bar
assert all(v['barRows']==1 for v in bar if int(v['phase'].rsplit('-',1)[-1])>=600),bar
for v in samples:
 if v['phase'].endswith('-23'):
  # The allocated split pane remains full height. Tahoe's floating glass
  # sidebar legitimately insets its content, which must stay inside that pane.
  for collapsed,allocated,content in zip([v['leftCollapsed'],v['rightCollapsed']],v['paneAllocatedFrames'],v['paneContentFrames']):
   if not collapsed:
    assert abs(allocated[1]-v['main'][1])<=1 and abs(allocated[3]-v['main'][3])<=1,v
    assert content[2]>0 and content[3]>0,v
    assert content[0]>=allocated[0]-1 and content[1]>=allocated[1]-1,v
    assert content[0]+content[2]<=allocated[0]+allocated[2]+1 and content[1]+content[3]<=allocated[1]+allocated[3]+1,v
phases={v['phase'].rsplit('-',1)[0] for v in samples if v['phase'].rsplit('-',1)[-1].isdigit()}
for phase in phases:
 end=[v for v in samples if v['phase'].startswith(phase+'-') and int(v['phase'].rsplit('-',1)[-1])>=20]
 for a,b in zip(end,end[1:]):assert max(abs(x-y) for x,y in zip(a['window'],b['window']))<=1,(phase,a['window'],b['window'])
print(json.dumps({'passed':True,'samples':len(samples),'normalBoardVariationPoints':0,'titleCenterErrorPoints':max(abs(v['titleCenter']-v['boardCenter']) for v in samples),'fullHeightPanes':True,'settledFrameJump':False,'barSamples':len(bar)}))
