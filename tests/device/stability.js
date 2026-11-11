const audio = require('ti.audiostream')
const base = Ti.App.Properties.getString('auditBaseURL')
const win = Ti.UI.createWindow({ backgroundColor: '#fff' })
const label = Ti.UI.createLabel({ text: 'Silent final stability', color: '#111', left: 15, right: 15 })
if(Ti.Platform.osname==='android')win.keepScreenOn=true;
win.add(label); win.open()
const out = { platform: Ti.Platform.osname, started: Date.now(), fixtureBase: base, phase: 'init', checks: [], timings: [], events: [], complete: false }
const wait = ms => new Promise(r => setTimeout(r, ms))
function save(phase) {
 out.phase = phase; out.updated = Date.now(); label.text = phase + '\nChecks: ' + out.checks.length
 Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory, 'stability-results.json').write(JSON.stringify(out))
 const client=Ti.Network.createHTTPClient({timeout:5000}); client.open('POST',base+'/results');client.send(JSON.stringify(out))
}
audio.addEventListener('state', e => out.events.push({ type:'state', value:e.state, at:Date.now() }))
audio.addEventListener('metadata', e => out.events.push({ type:'metadata', value:e.title, at:Date.now() }))
audio.addEventListener('error', e => out.events.push({ type:'error', value:e.message, at:Date.now() }))
async function until(predicate, ms) {const end=Date.now()+ms;while(!predicate()){if(Date.now()>end)return false;await wait(10)}return true}
function check(name, passed, detail) {out.checks.push({ name, passed:!!passed, detail, at:Date.now() });Ti.API.info('AUDIT2 '+JSON.stringify(out.checks[out.checks.length-1]))}
function setup(name, query='', artwork=null) {audio.setStream({url:base+'/stream/'+name+'.mp3'+query,title:'Station '+name,artist:'Audit Artist',artwork})}
async function start(name, query='', artwork=null) {
 const index=out.events.length, at=Date.now();setup(name,query,artwork);audio.start()
 const buffered=await until(()=>out.events.slice(index).some(e=>e.value==='buffering'),1000)
 const playing=await until(()=>out.events.slice(index).some(e=>e.value==='playing'),12000)
 const events=out.events.slice(index)
 out.timings.push({case:'start '+name+query,buffering:buffered?events.find(e=>e.value==='buffering').at-at:null,playing:playing?events.find(e=>e.value==='playing').at-at:null})
 return {index,at,playing}
}
async function reset(){audio.hardStop();await wait(250)}
if (Ti.Platform.osname !== "android") Ti.App.idleTimerDisabled = true
async function run(){ await wait(750)
 // Verify finite EOF/restart with the exact packaged native module before the soak.
 audio.setStream({url:base+'/finite/A.mp3',title:'Finite acceptance',isLive:false,artwork:null});audio.start()
 let index=out.events.length
 check('finite starts',await until(()=>audio.playing,6000))
 check('finite ends stopped',await until(()=>out.events.slice(index).some(e=>e.value==='stopped'),15000))
 check('finite does not remain buffering',out.events.filter(e=>e.type==='state').slice(-1)[0].value==='stopped'&&!audio.playing)
 audio.start();check('finite restarts',await until(()=>audio.playing,6000))
 if(out.checks.some(c=>!c.passed))throw new Error('Finite acceptance failed before soak')
 out.soakStarted=Date.now();let cycle=0
 while(Date.now()-out.soakStarted<30*60*1000) {
  await reset();const name=cycle%2?'A':'C';const p=await start(name,'?cycle='+cycle,base+'/cover.png?cycle='+cycle)
  check('sustained play '+cycle,p.playing)
  if(Ti.Platform.osname==='android'){await wait(1200);const meta=out.events.slice(p.index).filter(e=>e.type==='metadata');check('sustained metadata '+cycle,meta.length>0&&meta[meta.length-1].value==='Station '+name)}
  audio.setMetadata({title:'Manual '+cycle,artwork:base+'/cover.png?cycle='+cycle})
  await wait(1000);audio.pause();await wait(100);audio.start();await wait(1000)
  check('sustained resume '+cycle,audio.playing)
  if(out.events.length>5000)out.events.splice(0,out.events.length-3000)
  save('sustained cycle '+cycle+'; elapsed '+Math.round((Date.now()-out.started)/1000)+'s')
  cycle++;await wait(25000)
 }
 audio.hardStop();if(Ti.Platform.osname!=='android')Ti.App.idleTimerDisabled=false;if(Ti.Platform.osname==='android')win.keepScreenOn=false;out.complete=true;save('COMPLETE')
}
run().catch(e=>{out.failure=String(e);audio.hardStop();if(Ti.Platform.osname==='android')win.keepScreenOn=false;if(Ti.Platform.osname!=='android')Ti.App.idleTimerDisabled=false;save('FAILED')})
