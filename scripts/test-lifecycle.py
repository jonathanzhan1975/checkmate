import atexit,hashlib,json,os,pathlib,shutil,subprocess,sys,tempfile,time
import app_driver
from ui_locale import text, ui, record, proof_scope, language
root=pathlib.Path.cwd();evidence=pathlib.Path(os.environ['CHECKMATE_EVIDENCE_DIR']);state=pathlib.Path(tempfile.mkdtemp(prefix='checkmate-lifecycle-'));app=root/'build/CheckmateAutomation.app/Contents/MacOS/CheckmateNative'
# Removed at exit, after the finally below has stopped the app (run-gates fails a gate that leaves temporary files).
atexit.register(shutil.rmtree,state,ignore_errors=True)
helpers=app_driver.compile_helpers(evidence,{'ax-helper':'ax-helper','window-test-helper':'window-helper','board-click-helper':'board-helper'})
ax=helpers['ax-helper']
# A just-built executable's first run waits for the system to assess it; run the helper once here, so the timed launch
# below measures the app and not that wait.
subprocess.run([str(ax),str(os.getpid()),'windows'],check=True,stdout=subprocess.DEVNULL)
env=dict(os.environ,CHECKMATE_AUTOMATION='1');args=[str(app),'--automation','--data-dir',str(state)];process=None

def act(action,target=''):
 try:return app_driver.helper_output(ax,process.pid,action,target)
 except subprocess.CalledProcessError as error:print(error.output,flush=True);raise
def wait(predicate,timeout=10):app_driver.wait(predicate,'Lifecycle condition timed out',timeout,.05)
def window_action(*arguments):return subprocess.check_output([str(helpers['window-test-helper']),str(process.pid),*arguments],text=True,timeout=10).strip()
def board_action(action):return subprocess.check_output([str(helpers['board-click-helper']),str(process.pid),action],text=True,timeout=10).strip()
normal_height=None
def fullscreen(desired):
 global normal_height
 if desired:normal_height=float(window_action('geometry').split()[3])
 deadline=time.monotonic()+8
 while True:
  result=subprocess.run([str(helpers['window-test-helper']),str(process.pid),'fullscreen','on' if desired else 'off'],capture_output=True,text=True,timeout=10)
  if result.returncode==0:break
  if time.monotonic()>=deadline:raise AssertionError(result.stderr)
  time.sleep(.1)
 previous=None
 def settled():
  nonlocal previous
  try:
   current=window_action('fullscreen-state');geometry=window_action('geometry')
   restored=desired or abs(float(geometry.split()[3])-normal_height)<2
   ready=current==('full' if desired else 'normal') and geometry==previous and restored
   previous=geometry if current==('full' if desired else 'normal') else None
   return ready
  except subprocess.CalledProcessError:return False
 wait(settled,8)
 # AXFullScreen can change before AppKit reattaches the toolbar to its new
 # window/Space. The native fullscreen gate also waits for the content to settle.
 wait(lambda:'AXButton: Sidebar' in act('list'),10)
# Prepare test-side localization before measuring the app, just as the AX helper
# is warmed above. A first expectation also initializes the course-step index.
board_caption=text(ui('AXGrid: Chessboard'))
text(ui('Settings…'))
proof_scope(evidence)[0].mkdir(parents=True,exist_ok=True)
startup_timing={}
# Keep the user's accepted 2.003-second sample separate from each new sample.
# A timing failure is evaluated after functional checks, so it cannot prevent
# those checks from running or silently approve a slower new measurement.
approved=json.loads((root/'scripts/chinese-startup-acceptance.json').read_text())
hashes=json.loads(subprocess.check_output([sys.executable,'scripts/source-hashes.py',str(root)]))
product={p:h for p,h in hashes.items() if p.startswith(('Sources/','Artwork/')) or p in ('build.sh','Version.env','Package.swift','Package.resolved')}
manual_startup=language().startswith('zh') and hashlib.sha256(json.dumps(product,sort_keys=True).encode()).hexdigest()==approved['productFingerprint']
def startup_board_seen():
 queried=time.monotonic()
 shown=subprocess.check_output([str(ax),str(process.pid),'list'],text=True,timeout=30)
 observed=time.monotonic()
 # The same raw read must prove Chinese before it is accepted. Evidence disk I/O
 # happens after the observation timestamp, outside the app's readiness metric.
 record(process.pid,shown)
 if board_caption not in shown:return False
 (evidence/'startup-ready-ax.txt').write_text(shown)
 startup_timing['readyAccessibility']='startup-ready-ax.txt'
 startup_timing.update(axReadySeconds=observed-start,axQuerySeconds=observed-queried,evidenceProcessingSeconds=time.monotonic()-observed)
 return True
try:
 start=time.monotonic();process=app_driver.launch(args,env);startup_timing['launchAndRegistrationSeconds']=time.monotonic()-start;wait(startup_board_seen);warm=startup_timing['axReadySeconds']
 startup_timing['currentOriginalBudgetStatus']='met' if warm<2 else 'exceeded; not an automatic performance pass'
 if manual_startup:startup_timing['priorManuallyAcceptedSampleSeconds']=approved['measuredSeconds']
 board_action('activate');wait(lambda:board_action('active')=='true');fullscreen(True);act('press','Sidebar');time.sleep(.9);fullscreen(False);act('press','Sidebar');time.sleep(.9)
 act('drag');moved_x=float(act('position-x'));act('press','Sidebar');time.sleep(.9);act('press','Sidebar');time.sleep(.9);assert abs(float(act('position-x'))-moved_x)<=1,(moved_x,act('position-x'))
 # Saves land 250 ms after a change; wait for this one rather than racing it.
 wait(lambda:abs(json.loads((state/'state-v1.json').read_text())['window']['frame'][0]-moved_x)<=1)
 duplicate=app_driver.launch(args,env,interactive=False);duplicate.wait(timeout=5);assert process.poll() is None;assert act('windows').splitlines()[0]=='1'
 act('press','Settings…');wait(lambda:'Settings' in act('windows'));act('press','Settings…');assert act('windows').splitlines()[0]=='2';act('close-settings')
 act('press','e2, White, pawn');act('press','e4, move destination');time.sleep(1.2)
 act('quit');process.wait(timeout=5);saved=json.loads((state/'state-v1.json').read_text());assert saved['practice']['pgn'];pgn=saved['practice']['pgn'];process=app_driver.launch(args,env);wait(lambda:'e4, White, pawn' in act('list'));assert json.loads((state/'state-v1.json').read_text())['practice']['pgn']==pgn
 result={'passed':warm<2,'functionalPassed':True,'warmInteractiveSeconds':warm,'startupPerformance':startup_timing,'singleInstance':True,'settingsSingleton':True,'titlebarDrag':True,'dragAfterFullscreenPersists':True,'gameRestart':True};(evidence/'lifecycle-results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));assert warm<2,'Functional checks passed; this new sample exceeds the original automatic budget. Prior manual acceptance remains separately recorded.'
except Exception:
 try:(evidence/'lifecycle-failure-ax.txt').write_text(act('list'))
 except Exception:pass
 try:(evidence/'window-state.txt').write_text(window_action('diagnostic'))
 except Exception:pass
 subprocess.run(['screencapture','-x',str(evidence/'lifecycle-failure.png')],check=False)
 raise
finally:
 (evidence/'startup-timing.json').write_text(json.dumps(startup_timing,indent=2))
 app_driver.stop(process)
