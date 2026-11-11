/* Silent fixtures from the second audit, disposable app only. */
const audio = require('ti.audiostream')
const base = Ti.App.Properties.getString('auditBaseURL')
if (Ti.Platform.osname !== 'android') Ti.App.idleTimerDisabled = true
audio.setAutomotiveStations(['A','B','C'].map(id=>({id,title:'Station '+id,streamUrl:base+'/stream/'+id+'.mp3',artwork:base+'/cover.png'})))
const out = {platform: Ti.Platform.osname, started: Date.now(), fixtureBase: base, checks: [], timings: [], events: [], complete: false}
const win = Ti.UI.createWindow({backgroundColor:'#fff'}), label = Ti.UI.createLabel({color:'#111',text:'Silent regression run'})
if(Ti.Platform.osname==='android')win.keepScreenOn=true;
win.add(label);win.open()
const wait = ms => new Promise(r => setTimeout(r, ms))
audio.addEventListener('state',e=>out.events.push({type:'state',value:e.state,at:Date.now()}))
audio.addEventListener('metadata',e=>out.events.push({type:'metadata',value:e.title,at:Date.now()}))
audio.addEventListener('error',e=>out.events.push({type:'error',value:e.message,at:Date.now()}))
function check(name,passed){out.checks.push({name,passed:!!passed,at:Date.now()});save()}
function save(){Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory,'fix2-results.json').write(JSON.stringify(out));label.text='Silent checks '+out.checks.length+'; failed '+out.checks.filter(c=>!c.passed).length}
async function until(fn,ms){const end=Date.now()+ms;while(!fn()&&Date.now()<end)await wait(10);return !!fn()}
async function start(url,title){const index=out.events.length,at=Date.now();audio.setStream({url,title,artwork:null});audio.start();const playing=await until(()=>out.events.slice(index).some(e=>e.value==='playing'),6000);const events=out.events.slice(index);out.timings.push({url,at,buffering:events.find(e=>e.value==='buffering')?events.find(e=>e.value==='buffering').at-at:null,playing:playing?events.find(e=>e.value==='playing').at-at:null});return {index,at,playing}}
async function run(){
 await wait(500)
 for(let i=0;i<60;i++){
  audio.hardStop();await wait([0,25,100,250][i%4]);const p=await start(base+'/stream/'+(i%2?'A':'C')+'.mp3?fix2='+i,'Cold '+i)
  check('cold playing '+i,p.playing)
  const event=out.events.slice(p.index).find(e=>e.value==='buffering');check('cold buffering under 300ms '+i,event&&event.at-p.at<=300)
  await wait(100)
  if(i%3===0)audio.pause();else if(i%3===1)audio.stop();
  await wait(20)
 }
 for(let i=0;i<10;i++){audio.stop();await wait(10);audio.start();check('immediate soft restart '+i,await until(()=>audio.playing,6000));await wait(50)}
 let p=await start(base+'/stream/A.mp3','A');check('A active',p.playing)
 const index=out.events.length;audio.setStream({url:base+'/slow.pls?station=B&delay=2',title:'B',artwork:null});audio.start();await until(()=>out.events.slice(index).some(e=>e.value==='buffering'),1000)
 check('buffering during delayed playlist',out.events.slice(index).some(e=>e.value==='buffering'))
 audio.pause();await wait(2500);check('pause survives delayed source',!audio.playing&&!out.events.slice(index).some(e=>e.value==='playing'))
 audio.start();check('resume selected B',await until(()=>audio.playing,6000))
 for(const name of ['A','B','C']){audio.setStream({url:base+'/list.pls?station='+name+'&delay='+(name==='C'?0:2),title:name,artwork:null});audio.start();await wait(50)}
 check('rapid selection reaches C',await until(()=>audio.playing,6000))
 await wait(1000)
 if(Ti.Platform.osname==='android'){const meta=out.events.filter(e=>e.type==='metadata');check('latest received title C',meta.length&&meta[meta.length-1].value==='Station C')}
 audio.hardStop();await wait(250);audio.setStream({url:base+'/finite/A.mp3',title:'Finite',isLive:false,artwork:null});const endIndex=out.events.length;audio.start()
 check('finite starts',await until(()=>audio.playing,6000));check('finite ends as stopped',await until(()=>out.events.slice(endIndex).some(e=>e.value==='stopped'),15000))
 await wait(500);check('finite stays stopped',!audio.playing&&out.events.filter(e=>e.type==='state').slice(-1)[0].value==='stopped')
 audio.start();check('finite restart plays again',await until(()=>audio.playing,6000))
 audio.hardStop();if(Ti.Platform.osname==='android')win.keepScreenOn=false;out.complete=true;save()
}
run().catch(e=>{out.failure=String(e);audio.hardStop();if(Ti.Platform.osname==='android')win.keepScreenOn=false;save()})
