/* Interactive CarPlay integration fixture; install only in a disposable simulator app. */
const audio = require('ti.audiostream')
const base = 'http://127.0.0.1:18766'
let stations
const observed = { states: [], selections: [], actions: [] }
const win = Ti.UI.createWindow({ backgroundColor: '#fff', layout: 'vertical' })
const status = Ti.UI.createLabel({ text: 'CarPlay QA', color: '#111', top: 18, height: 70 })
win.add(status)
function record(kind, value) {
  observed[kind].push(value)
  status.text = kind + ': ' + JSON.stringify(value)
  Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory, 'carplay-results.json').write(JSON.stringify(observed, null, 2))
}
function catalog() {
  stations = [
    { id: 'a', title: 'QA A — RED', subtitle: 'Station A', streamUrl: base + '/live.mp3?id=a', artwork: base + '/slow-red.png', isLive: true },
    { id: 'b', title: 'QA B — BLUE', subtitle: 'Station B', streamUrl: base + '/live.mp3?id=b', artwork: base + '/blue.png', isLive: true }
  ]
  audio.setAutomotiveStations(stations)
  record('actions', 'catalog registered')
}
function button(title, callback) {
  const item = Ti.UI.createButton({ title, top: 10, height: 42, width: '90%' })
  item.addEventListener('click', callback)
  win.add(item)
}
button('1. Reset catalog', catalog)
button('2. Play A', () => {
  audio.setCurrentAutomotiveStation(stations[0])
  audio.setStream({ url: stations[0].streamUrl, title: stations[0].title, artist: 'CarPlay QA', artwork: stations[0].artwork, autoUpdateMetadata: false })
  audio.start()
})
button('3. Race: replace rows and artwork', () => {
  const nonce = Date.now()
  audio.setAutomotiveStations([{ ...stations[0], artwork: base + '/slow-red.png?n=' + nonce }, stations[1]])
  setTimeout(() => {
    stations = [
      { id: 'b', title: 'QA B — GREEN', subtitle: 'Reused first row', streamUrl: base + '/live.mp3?id=b', artwork: base + '/green.png', isLive: true },
      { id: 'a', title: 'QA A — YELLOW', subtitle: 'Reused second row', streamUrl: base + '/live.mp3?id=a', artwork: base + '/yellow.png', isLive: true }
    ]
    audio.setAutomotiveStations(stations)
    record('actions', 'race expected GREEN first / YELLOW second after slow RED finishes')
  }, 200)
})
button('4. Clear artwork', () => {
  stations = stations.map(station => ({ ...station, artwork: null }))
  audio.setAutomotiveStations(stations)
  audio.setMetadata({ artwork: null })
  record('actions', 'clear all artwork')
})
button('5. Pause', () => audio.pause())
button('6. Soft stop', () => audio.stop())
button('7. Resume', () => audio.start())
button('8. Hard stop', () => audio.hardStop())
audio.addEventListener('state', event => record('states', event.state))
audio.addEventListener('automotivestationselected', event => record('selections', { id: event.station.id, source: event.source }))
audio.addEventListener('error', event => { status.text = 'ERROR: ' + event.message })
win.open()
catalog()
