/* Native-device smoke test. Use only in a disposable app with ti.audiostream. */
const audio = require('ti.audiostream')
const base = Ti.App.Properties.getString('auditBaseURL', 'http://127.0.0.1:18765')
const results = { platform: Ti.Platform.osname, checks: [], states: [], metadata: [], errors: [] }
const window = Ti.UI.createWindow({ backgroundColor: '#fff' })
const label = Ti.UI.createLabel({ color: '#111', text: 'AudioStream audit running', left: 20, right: 20 })
window.add(label)
window.open()
function save() {
  Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory, 'audit-results.json').write(JSON.stringify(results, null, 2))
}
function check(name, passed) {
  results.checks.push({ name, passed: !!passed, at: Date.now() })
  label.text = results.checks.map(item => `${item.passed ? 'PASS' : 'FAIL'} ${item.name}`).join('\n')
  Ti.API.info('TIAUDIT ' + JSON.stringify(results.checks[results.checks.length - 1]))
  save()
}
const wait = ms => new Promise(resolve => setTimeout(resolve, ms))
audio.addEventListener('state', event => { results.states.push({ state: event.state, at: Date.now() }); save() })
audio.addEventListener('metadata', event => { results.metadata.push({ title: event.title, artist: event.artist }); save() })
audio.addEventListener('error', event => { results.errors.push(event.message); save() })
async function run() {
  await wait(1000)
  const stations = [{ id: 'fixture', title: 'Audit Station', artist: 'Manual Artist', streamUrl: base + '/live.mp3', artwork: base + '/cover.png' }]
  audio.setAutomotiveStations(stations)
  audio.setCurrentAutomotiveStation(stations[0])
  audio.setStream({ url: base + '/live.mp3', title: 'Manual Title', artist: 'Manual Artist', artwork: base + '/cover.png', autoUpdateMetadata: false })
  audio.start()
  await wait(7000)
  check('direct stream plays', audio.playing)
  const bufferedBefore = results.states.filter(item => item.state === 'buffering').length
  audio.start()
  await wait(1000)
  check('repeated start keeps playing', audio.playing)
  check('repeated start does not prepare again', results.states.filter(item => item.state === 'buffering').length === bufferedBefore)
  audio.setMetadata({ title: 'Updated Title' })
  await wait(2000)
  check('metadata event with automatic publication disabled', results.metadata.some(item => item.title === 'Fixture Song'))
  audio.pause()
  await wait(4000)
  check('manual pause remains paused', !audio.playing && results.states[results.states.length - 1].state === 'paused')
  audio.stop()
  const stopIndex = results.states.length
  await wait(2000)
  check('soft stop remains stopped', !audio.playing && results.states[results.states.length - 1].state === 'stopped' && results.states.slice(stopIndex).every(item => item.state === 'stopped'))
  audio.play()
  await wait(2000)
  check('play alias resumes after soft stop', audio.playing)
  audio.hardStop()
  audio.setStream({ url: base + '/relative.pls?test=1#radio', title: 'PLS Station', autoUpdateMetadata: false })
  audio.start()
  await wait(5000)
  check('relative PLS plays after hard stop', audio.playing)
  audio.hardStop()
  audio.setStream({ url: base + '/relative.m3u?test=1#radio', title: 'M3U Station', autoUpdateMetadata: false })
  audio.start()
  await wait(5000)
  check('relative M3U plays', audio.playing)
  audio.hardStop()
  audio.setStream({ url: base + '/503', title: 'Retry Station' })
  audio.start()
  await wait(1000)
  audio.pause()
  const pauseIndex = results.states.length
  await wait(5000)
  check('pause cancels pending retry', !audio.playing && !results.states.slice(pauseIndex).some(item => item.state === 'playing'))
  audio.hardStop()
  audio.setMetadata({ artwork: null })
  results.publicStreams = []
  const publicStations = [
    { title: 'Radio Paradise', url: 'https://stream.radioparadise.com/aac-320' },
    { title: 'Heart London HLS', url: 'https://hls.thisisdax.com/hls/HeartLondon/master.m3u8' },
    { title: 'The VIP Lounge 2', url: 'https://solid33.streamupsolutions.com/proxy/otrsiktc/stream' }
  ]
  for (const station of publicStations) {
    const metadataStart = results.metadata.length
    audio.hardStop()
    audio.setStream({ url: station.url, title: station.title, artist: 'Public stream test', artwork: null })
    audio.start()
    await wait(12000)
    check('public stream plays: ' + station.title, audio.playing)
    results.publicStreams.push({ title: station.title, metadata: results.metadata.slice(metadataStart) })
    audio.pause()
    await wait(1000)
    check('public stream pauses: ' + station.title, !audio.playing)
  }
  audio.hardStop()
  results.complete = true
  save()
  Ti.API.info('TIAUDIT COMPLETE ' + JSON.stringify(results))
}
run().catch(error => { results.failure = String(error); save(); label.text = String(error) })
