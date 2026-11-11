/* Run in the disposable audit app. Keep events in memory while measuring. */
const audio = require('ti.audiostream')
const base = Ti.App.Properties.getString('auditBaseURL', 'http://127.0.0.1:18765')
const result = { platform: Ti.Platform.osname, samples: [], events: [], complete: false }
const win = Ti.UI.createWindow({ backgroundColor: '#fff' })
const label = Ti.UI.createLabel({ color: '#111', text: 'Measuring audio event latency', left: 20, right: 20 })
win.add(label)
win.open()
const wait = ms => new Promise(resolve => setTimeout(resolve, ms))
audio.addEventListener('state', e => result.events.push({ kind: 'state', value: e.state, at: Date.now() }))
audio.addEventListener('metadata', e => result.events.push({ kind: 'metadata', value: e.title, at: Date.now() }))
audio.addEventListener('error', e => result.events.push({ kind: 'error', value: e.message, at: Date.now() }))
async function until(predicate, timeout) {
  const end = Date.now() + timeout
  while (!predicate()) {
    if (Date.now() > end) throw new Error('Timed out waiting for audio event')
    await wait(10)
  }
}
async function measure(name, action, state, budgetMs, timeout = 4000) {
  const index = result.events.length
  const start = Date.now()
  action()
  const match = () => result.events.slice(index).find(e => e.kind === 'state' && e.value === state)
  await until(match, timeout)
  const elapsedMs = match().at - start
  result.samples.push({ name, elapsedMs, budgetMs, passed: elapsedMs <= budgetMs })
  return { start, index }
}
async function play(url, name) {
  const action = await measure(name + ': buffering', () => {
    audio.setStream({ url, title: name, artist: 'Timing fixture', artwork: null })
    audio.start()
  }, 'buffering', 300)
  await until(() => result.events.slice(action.index).some(e => e.value === 'playing'), 12000)
  const expectedTitle = url.includes('/slow/') ? 'New Fixture Song' : 'Fixture Song'
  if (Ti.Platform.osname === 'android') {
    await until(() => result.events.slice(action.index).some(e => e.kind === 'metadata' && e.value === expectedTitle), 4000)
  }
  const events = result.events.slice(action.index)
  result.samples.push({ name: name + ': playing', elapsedMs: events.find(e => e.value === 'playing').at - action.start, budgetMs: null })
  if (url.includes('/slow/')) {
    result.samples.push({ name: name + ': no previous-station metadata during HTTP resolution', passed: !events.some(e => e.kind === 'metadata' && e.at - action.start < 2000) })
  }
  if (Ti.Platform.osname === 'android') {
    result.samples.push({ name: name + ': metadata belongs to selected station', passed: events.filter(e => e.kind === 'metadata').every(e => e.value === expectedTitle) })
  }
  const metadata = events.find(e => e.kind === 'metadata')
  if (metadata) result.samples.push({ name: name + ': received metadata', elapsedMs: metadata.at - action.start, budgetMs: null })
}
async function run() {
  await wait(600)
  for (let round = 1; round <= 3; round++) {
    await play(base + '/live.mp3', 'cold ' + round)
    const startIndex = result.events.length
    audio.start()
    await wait(300)
    result.samples.push({ name: 'repeated start ' + round, passed: !result.events.slice(startIndex).some(e => e.value === 'buffering') })
    await play(base + '/slow/live.mp3', 'switch with 2s HTTP delay ' + round)
    await measure('pause ' + round, () => audio.pause(), 'paused', 300)
    await measure('stop ' + round, () => audio.stop(), 'stopped', 300)
    audio.hardStop()
    await wait(300)
  }
  await measure('pending HTTP: buffering', () => {
    audio.setStream({ url: base + '/slow/live.mp3', title: 'Pending source', artwork: null })
    audio.start()
  }, 'buffering', 300)
  await measure('pause during HTTP resolution', () => audio.pause(), 'paused', 300)
  const pausedIndex = result.events.length
  await wait(5000)
  result.samples.push({ name: 'late HTTP response cannot resume paused playback', passed: !audio.playing && !result.events.slice(pausedIndex).some(e => e.value === 'playing') })
  await measure('stop after pending pause', () => audio.stop(), 'stopped', 300)
  result.complete = true
}
run().catch(error => { result.failure = String(error) }).finally(() => {
  audio.hardStop()
  Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory, 'latency-results.json').write(JSON.stringify(result, null, 2))
  Ti.API.info('TILATENCY ' + JSON.stringify(result))
  label.text = JSON.stringify(result.samples, null, 2)
})
