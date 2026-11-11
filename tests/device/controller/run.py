import argparse,subprocess,time,json,pathlib
parser=argparse.ArgumentParser(description='Exercise an installed disposable controller-target audit app')
parser.add_argument('--fixture-evidence',type=pathlib.Path,required=True)
parser.add_argument('--output',type=pathlib.Path,required=True)
args=parser.parse_args()
root=args.fixture_evidence
out=args.output;out.mkdir(exist_ok=True,parents=True)
target='mx.codigomovil.audiostreamaudit';client='mx.codigomovil.audiostreamcontrolleraudit'
def adb(*a):
 p=subprocess.run(['adb',*a],capture_output=True,text=True)
 if p.returncode:raise RuntimeError(p.stderr)
 return p.stdout
def read(pkg,path):
 try:return json.loads(adb('shell','run-as',pkg,'cat',path))
 except Exception:return None
def poll(fn,seconds):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  d=fn()
  if d:return d
  time.sleep(.15)
 raise RuntimeError('timeout')
def requests():return [json.loads(l) for l in (root/'requests.jsonl').read_text().splitlines()]
summary=[]
for command in ['inspect','prepareB','playB','stop','focusTransient','focusPause']:
 for pkg in [client,target]:adb('shell','am','force-stop',pkg)
 adb('shell','run-as',target,'rm','-f','app_appdata/controller-target-results.json');adb('shell','run-as',client,'rm','-f','files/controller-results.json')
 mode='normal' if command in ['inspect','prepareB','playB'] else 'slow'
 before=len(requests());adb('shell','am','start','-W','-n',target+'/.AudiostreamauditActivity','--es','mode',mode)
 def ready():
  d=read(target,'app_appdata/controller-target-results.json')
  return d if d and d.get('ready') and any(e['value']==('playing' if mode=='normal' else 'buffering') for e in d['events']) else None
 initial=poll(ready,15)
 adb('shell','am','start','-W','-n',client+'/audit.controller.MainActivity','--es','command',command)
 result=poll(lambda:read(client,'files/controller-results.json'),16)
 time.sleep(.2);target_result=read(target,'app_appdata/controller-target-results.json')
 if not target_result or target_result['started']!=initial['started']:
  raise RuntimeError(f'{command}: target stopped reporting or restarted')
 # Compare snapshots from the same device instead of comparing its clock to the host clock.
 new_events=target_result['events'][len(initial['events']):]
 added=requests()[before:]
 errors=[e for e in result['events'] if e['type'] in ['uriReadError','inspectError','saveError']]
 checks={'controllerConnected':any(e['type']=='connection' and e['value']=='connected' for e in result['events']),'noReaderErrors':not errors}
 if command=='inspect':
  for kind in ['embeddedArtwork','uriArtwork','embeddedHash','uriHash']:
   values=[e['value']for e in result['events']if e['type']==kind]
   checks[kind+'PresentAndUnchanged']=len(values)==2 and len(set(values))==1
  checks['embedded512']=any(e['type']=='embeddedArtwork'and e['value']=='512x512'for e in result['events'])
  checks['uri1024']=any(e['type']=='uriArtwork'and e['value']=='1024x1024'for e in result['events'])
 if command in ['prepareB','playB']:
  checks['BRequested']=any(r['path']=='/stream/B.mp3' for r in added)
  checks['BMetadata']=any(e['type']=='metadata'and e['value']=='Station B' for e in new_events)
  checks['BPlaying']=any(e['type']=='state'and e['value']=='playing' for e in new_events)
 if command=='stop':
  states=[e['value'] for e in new_events if e['type']=='state']
  checks['lateSourceCannotResume']='stopped' in states and 'playing' not in states
 if command.startswith('focus'):
  events=result['events'];requested=next(e for e in events if e['type']=='focusRequested');released=next(e for e in events if e['type']=='focusReleased');checks['focusGranted']=requested['value']==1
  states=[e for e in target_result['events']if e['type']=='state'];checks['pausedDuringFocusLoss']=any(e['value']=='paused' and requested['at']-100<=e['at']<released['at']for e in states)
  checks['noPlayingDuringFocusLoss']=not any(e['value']=='playing' and requested['at']+100<=e['at']<released['at']for e in states)
  resumed=any(e['value']=='playing' and e['at']>=released['at']-100 for e in states)
  checks['manualPauseWins' if command=='focusPause'else 'focusGainResumes']=not resumed if command=='focusPause'else resumed
 data={'command':command,'initial':initial,'controller':result,'target':target_result,'requests':added,'checks':checks}
 (out/(command+'.json')).write_text(json.dumps(data,indent=2));summary.append({'command':command,'checks':checks});print(command,checks,flush=True)
for pkg in [client,target]:adb('shell','am','force-stop',pkg)
(out/'summary.json').write_text(json.dumps(summary,indent=2))
