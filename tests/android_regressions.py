"""Behavioral regressions using the actual Java method bodies and small Android substitutes.
Run: python3 tests/android_regressions.py
Requires JDK 11+; generated sources/classes live in a temporary directory.
"""
import pathlib, subprocess, tempfile, argparse
repo=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--source',type=pathlib.Path,default=repo/'android/src/ti/audiostream/MediaPlaybackService.java')
args=parser.parse_args()
src=args.source.read_text()
def method(text,sig):
 start=text.index(sig); opening=text.index('{',start); n=1;i=opening+1
 while n:
  if text[i]=='{': n+=1
  elif text[i]=='}': n-=1
  i+=1
 return text[start:i]
sigs=['private boolean isPlaylistUrl(', 'private String parsePlaylist(', 'private void handleSetMetadata(', 'private String normalizeArtworkUrl(', 'private String applyRules(', 'private void pause()', 'private void attemptReconnect()', 'private void cancelPendingReconnect()', 'private void resetRetryLogic()', 'private void play()', 'private boolean parseStreamTitle(', 'private void publishReceivedMetadata(', 'private void clearFailedArtwork(', 'private PlaybackSource resolvePlaylist(', 'private boolean isTerminalPlaybackError(', 'static synchronized Intent authorizeCommand(', 'private void loadArtworkAsync(', 'private void setMediaItemAndPrepare(', 'private static final class PlaybackSource', 'private void handleSetAutoUpdateMetadata(', 'private android.net.Uri getCatalogArtwork(', 'private boolean isArtworkRequestCurrent(', 'private void clearFailedArtwork(long generation, boolean automatic', 'private void loadArtworkAsync(String artworkUrl, long expectedGeneration, boolean automatic', 'private String readPlaylistBody(', 'private void cancelPlaylistResolution()', 'private void stop()', 'private void hardStop()', 'private void stopForegroundService()', 'static boolean isForegroundReady()', 'static synchronized void releaseHardStopRequest(']
methods='\n'.join(method(src,s) for s in sigs)
methods+='\n'+method((repo/'android/src/ti/audiostream/AudiostreamModule.java').read_text(),'private void startServiceSafely(')
methods+='\n'+method((repo/'android/src/ti/audiostream/DiagnosticLog.java').read_text(),'static String sanitize(')
methods=methods.replace('MediaPlaybackService.', '').replace('androidx.media3.datasource.HttpDataSource.InvalidResponseCodeException', 'HttpStatusException').replace('org.appcelerator.kroll.common.TiConfig.LOGD', 'false').replace('android.os.SystemClock.elapsedRealtime()', 'System.currentTimeMillis()').replace('android.net.Uri', 'FakeUri').replace('androidx.media3.common.MimeTypes.APPLICATION_M3U8', '"application/x-mpegURL"')
preamble=r"""
import java.net.*;import java.io.*;import java.util.*;import java.util.regex.*;import java.util.concurrent.*;
class DiagnosticLog {static void d(String a,String b){} static void i(String a,String b){} static void w(String a,String b){} static void e(String a,String b){}}
class Intent {
 Map<String,Object> data=new HashMap<>();
 Intent putExtra(String k,long value){data.put(k,value);return this;} long getLongExtra(String k,long value){return data.containsKey(k)?(Long)data.get(k):value;} String action="PLAY"; Intent setAction(String value){action=value;return this;} String getAction(){return action;} Intent putExtra(String k,String v){data.put(k,v);return this;}
 String getStringExtra(String k){return (String)data.get(k);}
 Intent putExtra(String k,boolean value){data.put(k,value);return this;} boolean getBooleanExtra(String k,boolean value){return data.containsKey(k)?(Boolean)data.get(k):value;}
 boolean hasExtra(String k){return data.containsKey(k);}
}
class Player {static final int STATE_IDLE=1,STATE_BUFFERING=2,STATE_READY=3,STATE_ENDED=4;
 MediaItem lastItem; boolean playing; int state=STATE_IDLE; int plays; boolean isPlaying(){return playing;}
 int getPlaybackState(){return state;} void pause(){playing=false;} void play(){playing=true;plays++;}
 void addListener(Object x){} void removeListener(Object x){} void clearMediaItems(){lastItem=null;} void stop(){playing=false;state=STATE_IDLE;} void setMediaItem(MediaItem i){lastItem=i;} void prepare(){state=STATE_BUFFERING;}
}
class MediaItem {String url,mime; static MediaItem fromUri(String s){return new Builder().setUri(s).build();}
 static class Builder {MediaItem item=new MediaItem();Builder setUri(String url){item.url=url;return this;} Builder setMimeType(String mime){item.mime=mime;return this;} MediaItem build(){return item;}}
}
class PlaybackStateCompat {static final int STATE_ERROR=7,STATE_PAUSED=2,STATE_STOPPED=1,STATE_BUFFERING=6;}
class FakeSession {boolean active=true;boolean isActive(){return active;} void setActive(boolean b){active=b;}}
class Handler {List<Runnable> queue=new ArrayList<>(); void post(Runnable r){queue.add(r);} void drain(){for(Runnable r:new ArrayList<>(queue))r.run();queue.clear();}}
class AudiostreamModule {static void fireError(String s){} static void fireState(String s){}}
class FailingContext {void startService(Intent intent){throw new RuntimeException("denied");}}
class FakeUri {}
class Bitmap {String identity;Bitmap(String value){identity=value;}}
class HttpStatusException extends Exception {int responseCode; HttpStatusException(int status){responseCode=status;}}
class PlaybackException extends Exception {
 static final int ERROR_CODE_IO_BAD_HTTP_STATUS=2004,ERROR_CODE_IO_FILE_NOT_FOUND=2005,ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE=2003,ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED=3003,ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED=3004;
 int errorCode; PlaybackException(int code,Throwable cause){super(cause);errorCode=code;}
}
public class JavaProbe {
 static long nextHardStopMarker; static Set<Long> pendingHardStopMarkers=new HashSet<>(); static final String EXTRA_HARD_STOP_MARKER="marker"; static boolean foregroundActive,hardStopPending; static final String ACTION_STOP="STOP",EXTRA_HARD_STOP="hard"; static final String COMMAND_TOKEN="private-token",EXTRA_COMMAND_TOKEN="commandToken";
 static final String LCAT="probe", EXTRA_AUTO_UPDATE_METADATA="auto",EXTRA_TITLE="title",EXTRA_ARTIST="artist",EXTRA_ARTWORK_URL="artworkUrl";
 String currentMimeType; String currentTitle="Manual title",currentArtist="Manual artist",currentUrl="https://radio.test/live";
 Object currentArtwork=new Object(); List<MetadataRule> titleRules,artistRules;
 String receivedTitle="",receivedArtist=""; Object receivedArtwork; boolean playbackFailed=false,hasAudioFocus=true; boolean sessionPublishedToSystemUi;boolean playbackRequested=true,controlsVisible=true,playlistPending=false; boolean isLive=true,resumeOnFocusGain=false;int published=0,notified=0,prepared=0;boolean autoUpdateMetadata=false;
 Object playerListener;Object createPlayerListener(long g){return new Object();} final Object playlistConnectionLock=new Object();HttpURLConnection playlistConnection;Future<?> playlistTask;
 Player player=new Player();FakeSession mediaSession=new FakeSession();
 ExecutorService executor=Executors.newSingleThreadExecutor();Handler mainHandler=new Handler();
 Future<?> pendingReconnectTask;int retryCount=0;static final int MAX_RETRIES=5,RETRY_DELAY_MS=1;
 static class MetadataRule {Pattern pattern;String replace;MetadataRule(String p,String r){pattern=Pattern.compile(p);replace=r;}}
 void updateMediaSessionMetadata(){published++;}void updateNotification(){notified++;}
 boolean failArtwork; int reads,treeNotifications; boolean serviceDestroyed; static final String ROOT_ID="ROOT",RESUMPTION_ROOT_ID="recent";
 Map<String,FakeUri> catalogArtwork=new HashMap<>();Set<String> catalogArtworkPending=new HashSet<>();Map<String,Long> catalogArtworkRetryAfter=new HashMap<>();
 Bitmap readArtwork(String url)throws IOException{reads++;if(failArtwork)throw new IOException("temporary");return new Bitmap(url);} FakeUri publishArtworkUri(Bitmap b){return b==null?null:new FakeUri();} Bitmap getAppIconBitmap(){return new Bitmap("fallback");} void notifyChildrenChanged(String id){treeNotifications++;}int lastNativeState=-1,stateAtPromotion=-1;void updatePlaybackState(int s){lastNativeState=s;}
 java.util.concurrent.atomic.AtomicLong streamGeneration=new java.util.concurrent.atomic.AtomicLong(0); java.util.concurrent.atomic.AtomicLong autoMetadataGeneration=new java.util.concurrent.atomic.AtomicLong(0); java.util.concurrent.atomic.AtomicLong playbackGeneration=new java.util.concurrent.atomic.AtomicLong(0); java.util.concurrent.atomic.AtomicLong artworkGeneration=new java.util.concurrent.atomic.AtomicLong(0);
 int foregroundPromotions; boolean startForegroundWithNotification(){stateAtPromotion=lastNativeState;foregroundPromotions++;return true;} int lastStartId=1,frameworkLatestStartId=1,destroyRequests; void stopSelf(){destroyRequests++;} boolean stopSelfResult(int id){if(id==frameworkLatestStartId){destroyRequests++;return true;}return false;} void removeNotification(){} void abandonAudioFocus(){} void preparePlayback(){prepared++;player.prepare();} boolean requestAudioFocus(){hasAudioFocus=true;return true;}

 FailingContext getContext(){return new FailingContext();} static void fireState(String state){} static void fireError(String error){}
 static void out(String key,Object value){System.out.println(key+"="+value);}
"""
main=r"""
 static int failures; static void check(boolean ok,String name){System.out.println((ok?"PASS ":"FAIL ")+name);if(!ok)failures++;}
 public static void main(String[] args)throws Exception{
 JavaProbe s=new JavaProbe();
 JavaProbe initial=new JavaProbe();initial.play();check(initial.stateAtPromotion==PlaybackStateCompat.STATE_BUFFERING,"first notification sees loading rather than an old paused/stopped session");initial.executor.shutdownNow();
 try {
 String diagnostic=sanitize("HTTP failed https://user:password@radio.test/live?token=private#secret and content://private/file");
 check(!diagnostic.contains("private")&&!diagnostic.contains("password")&&!diagnostic.contains("radio.test")&&!diagnostic.contains("token="),"native diagnostics redact complete signed URLs and credentials");
 check("HTTP 503".equals(sanitize("HTTP 503")),"native diagnostics retain safe status details");
 s.lastStartId=1;s.frameworkLatestStartId=1;s.hardStop();check(s.destroyRequests==1,"hard stop without newer starts stops service");check(s.lastNativeState==PlaybackStateCompat.STATE_STOPPED&&!s.mediaSession.active,"hard stop deactivates the stopped session");s.stop();check(s.lastNativeState==PlaybackStateCompat.STATE_STOPPED,"soft stop retains the stopped transport state");s.destroyRequests=0;
 foregroundActive=true;hardStopPending=false;check(isForegroundReady(),"active foreground status permits regular command delivery");
 Intent pending=authorizeCommand(new Intent().setAction(ACTION_STOP).putExtra(EXTRA_HARD_STOP,true));check(!isForegroundReady(),"queued hard stop prevents stale foreground assumption");releaseHardStopRequest(pending);
 foregroundActive=true;hardStopPending=false;s.startServiceSafely(new Intent().setAction(ACTION_STOP).putExtra(EXTRA_HARD_STOP,true));
 check(isForegroundReady(),"failed hard stop delivery releases pending marker");
 Intent first=authorizeCommand(new Intent().setAction(ACTION_STOP).putExtra(EXTRA_HARD_STOP,true));Intent second=authorizeCommand(new Intent().setAction(ACTION_STOP).putExtra(EXTRA_HARD_STOP,true));
 releaseHardStopRequest(first);check(!isForegroundReady(),"failed older stop preserves newer pending marker");releaseHardStopRequest(second);check(isForegroundReady(),"last completed stop releases foreground readiness");
 foregroundActive=false;hardStopPending=false;
 s.lastStartId=1;s.frameworkLatestStartId=3;s.hardStop();
 check(s.destroyRequests==0,"hard stop cannot destroy service with later commands already queued");
 s.currentUrl="https://radio.test/replacement.pls";s.play();check(s.player.playing,"play after queued hard stop reaches replacement player");
 int promotions=s.foregroundPromotions;s.play();check(s.foregroundPromotions>promotions,"repeated play fulfills foreground start before already-playing guard");
 s.currentUrl="";promotions=s.foregroundPromotions;s.play();check(s.foregroundPromotions>promotions,"missing URL foreground request is acknowledged before stopping");
 s.currentUrl="https://radio.test/live";s.prepared=0;s.player.playing=false;
 check(s.isPlaylistUrl("https://radio.test/list.m3u?q=1#radio"),"playlist query and fragment");
 check(s.isPlaylistUrl("https://radio.test/list.m3u#radio"),"playlist fragment without query");
 check("../audio/live.mp3".equals(s.parsePlaylist("#EXTM3U\n../audio/live.mp3\n")),"relative M3U");
 check("../live".equals(s.parsePlaylist("[playlist]\nFile1=../live\n")),"relative PLS");
 check("https://radio.test/live?token=abc".equals(s.parsePlaylist("#EXTM3U\nhttps://radio.test/live?token=abc\n")),"M3U absolute signed URL");
 check("../live?token=abc".equals(s.parsePlaylist("#EXTM3U\n../live?token=abc\n")),"M3U relative signed URL");
 check(s.parsePlaylist("[playlist]\nNumberOfEntries=0\nVersion=2\n")==null,"PLS settings are not M3U entries");
 check("File1=stream".equals(s.parsePlaylist("#EXTM3U\nFile1=stream\n")),"M3U equals entry is not a PLS key");
 Intent title=new Intent();title.putExtra(EXTRA_TITLE,"New title");s.handleSetMetadata(title);
 check(s.published==1 && s.notified==1,"manual title publishes immediately");
 check("Manual artist".equals(s.currentArtist),"omitted artist preserved");
 Object artwork=s.currentArtwork;s.handleSetMetadata(title);check(s.currentArtwork==artwork,"omitted artwork preserved");
 Intent clear=new Intent();clear.putExtra(EXTRA_ARTWORK_URL,(String)null);s.handleSetMetadata(clear);check(s.currentArtwork==null,"explicit null clears artwork");
 s.currentTitle="Manual branding";s.currentArtist="Station";s.parseStreamTitle("Singer - Song");
 check("Manual branding".equals(s.currentTitle)&&"Station".equals(s.currentArtist),"stream metadata preserves manual fields");
 check("Song".equals(s.receivedTitle)&&"Singer".equals(s.receivedArtist),"received metadata remains available");
 s.autoUpdateMetadata=false;s.receivedTitle="Broadcast";s.publishReceivedMetadata();check("Manual branding".equals(s.currentTitle),"auto false publication is inert");
 s.autoUpdateMetadata=true;s.publishReceivedMetadata();check("Broadcast".equals(s.currentTitle),"auto true publishes received title");
 s.currentArtwork=new Object();s.artworkGeneration.set(4);s.clearFailedArtwork(3);s.mainHandler.drain();check(s.currentArtwork!=null,"stale failed artwork cannot clear current");
 s.clearFailedArtwork(4);s.mainHandler.drain();check(s.currentArtwork==null,"latest failed artwork clears current");
 s.artworkGeneration.set(10);s.loadArtworkAsync("old-song",10);s.executor.submit(()->{}).get();
 s.artworkGeneration.set(11);s.loadArtworkAsync("new-song",11);s.executor.submit(()->{}).get();s.mainHandler.drain();
 check("new-song".equals(((Bitmap)s.currentArtwork).identity),"older artwork success cannot replace newer song");
 s.artworkGeneration.set(100);s.loadArtworkAsync("manual-slow",100);s.executor.submit(()->{}).get();
 s.handleSetAutoUpdateMetadata(new Intent().putExtra(EXTRA_AUTO_UPDATE_METADATA,false));s.mainHandler.drain();
 check("manual-slow".equals(((Bitmap)s.currentArtwork).identity),"disabling auto metadata preserves pending manual artwork");
 s.receivedArtwork=new Bitmap("disabled-auto-embedded");s.handleSetAutoUpdateMetadata(new Intent().putExtra(EXTRA_AUTO_UPDATE_METADATA,true));
 check(s.receivedArtwork==null,"auto policy toggle discards unpublished embedded artwork");
 s.autoUpdateMetadata=true;s.artworkGeneration.set(120);s.loadArtworkAsync("obsolete-auto",120,true,s.autoMetadataGeneration.get());s.executor.submit(()->{}).get();
 s.handleSetAutoUpdateMetadata(new Intent().putExtra(EXTRA_AUTO_UPDATE_METADATA,false));s.handleSetAutoUpdateMetadata(new Intent().putExtra(EXTRA_AUTO_UPDATE_METADATA,true));s.mainHandler.drain();
 check("manual-slow".equals(((Bitmap)s.currentArtwork).identity),"auto off then on cannot resurrect pending automatic artwork");
 s.failArtwork=true;s.artworkGeneration.set(121);s.loadArtworkAsync("failed-obsolete-auto",121,true,s.autoMetadataGeneration.get());s.executor.submit(()->{}).get();
 s.handleSetAutoUpdateMetadata(new Intent().putExtra(EXTRA_AUTO_UPDATE_METADATA,false));s.handleSetAutoUpdateMetadata(new Intent().putExtra(EXTRA_AUTO_UPDATE_METADATA,true));s.mainHandler.drain();
 check("manual-slow".equals(((Bitmap)s.currentArtwork).identity),"obsolete automatic failure cannot clear manual artwork");
 s.failArtwork=true;s.getCatalogArtwork("retry-cover");s.executor.submit(()->{}).get();s.mainHandler.drain();
 check(!s.catalogArtworkPending.contains("retry-cover"),"catalog failure releases pending request");
 check(s.treeNotifications==0,"catalog failure does not trigger browse retry loop");
 int reads=s.reads;s.getCatalogArtwork("retry-cover");s.executor.submit(()->{}).get();s.mainHandler.drain();
 check(s.reads==reads,"catalog failure uses retry backoff");
 s.failArtwork=false;s.catalogArtworkRetryAfter.put("retry-cover",0L);s.getCatalogArtwork("retry-cover");s.executor.submit(()->{}).get();s.mainHandler.drain();
 check(s.catalogArtwork.containsKey("retry-cover"),"later browse retries catalog transient failure");
 check(!s.isTerminalPlaybackError(new PlaybackException(2004,new HttpStatusException(429))),"HTTP 429 retries");
 check(!s.isTerminalPlaybackError(new PlaybackException(2004,new HttpStatusException(503))),"HTTP 503 retries");
 check(s.isTerminalPlaybackError(new PlaybackException(2004,new HttpStatusException(404))),"HTTP 404 terminal");
 check(!s.isTerminalPlaybackError(new PlaybackException(2001,new IOException(new SocketTimeoutException()))),"nested timeout retries");
 check(!s.isTerminalPlaybackError(new PlaybackException(2001,new UnknownHostException())),"DNS failure retries boundedly");
 check(s.isTerminalPlaybackError(new PlaybackException(2001,new javax.net.ssl.SSLHandshakeException("invalid cert"))),"certificate failure terminal");
 Intent authorized=authorizeCommand(new Intent());check(COMMAND_TOKEN.equals(authorized.getStringExtra(EXTRA_COMMAND_TOKEN)),"internal intent carries private capability");
 com.sun.net.httpserver.HttpServer server=com.sun.net.httpserver.HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
 server.createContext("/list/station.pls",exchange->{byte[] body="[playlist]\nFile1=../audio/live\n".getBytes();exchange.getResponseHeaders().set("Content-Type","audio/x-scpls");exchange.sendResponseHeaders(200,body.length);exchange.getResponseBody().write(body);exchange.close();});
 server.createContext("/hls.m3u",exchange->{byte[] body="#EXTM3U\n#EXT-X-TARGETDURATION:10\nsegment.aac\n".getBytes();exchange.getResponseHeaders().set("Content-Type","audio/x-mpegurl");exchange.sendResponseHeaders(200,body.length);exchange.getResponseBody().write(body);exchange.close();});
 server.createContext("/hls",exchange->{byte[] body="#EXTM3U\n#EXT-X-TARGETDURATION:10\nsegment.aac\n".getBytes();exchange.getResponseHeaders().set("Content-Type","application/vnd.apple.mpegurl");exchange.sendResponseHeaders(200,body.length);exchange.getResponseBody().write(body);exchange.close();});
 server.start();
 try{String base="http://127.0.0.1:"+server.getAddress().getPort();check((base+"/audio/live").equals(s.resolvePlaylist(base+"/list/station.pls").url),"PLS resolves against response URL");check((base+"/hls.m3u").equals(s.resolvePlaylist(base+"/hls.m3u").url),"HLS m3u delegated intact");PlaybackSource detected=s.resolvePlaylist(base+"/hls");check((base+"/hls").equals(detected.url)&&"application/x-mpegURL".equals(detected.mimeType),"suffixless HLS carries detected MIME from response");}finally{server.stop(0);}
 final int[] bytesRead={0};InputStream oversized=new InputStream(){public int read(){bytesRead[0]++;return 'a';} public int read(byte[] b,int off,int len){Arrays.fill(b,off,off+len,(byte)'a');bytesRead[0]+=len;return len;}};
 boolean oversizedRejected=false;try{s.readPlaylistBody(oversized);}catch(IOException expected){oversizedRejected=true;}
 check(oversizedRejected && bytesRead[0]<=262144+8192,"playlist byte cap enforced before reading giant line");
 check(s.readPlaylistBody(new ByteArrayInputStream(new byte[262144])).length()==262144,"playlist exact byte limit accepted");
 s.currentUrl="https://radio.test/station.pls";s.player.state=Player.STATE_IDLE;s.play();check(s.prepared==1,"cold playlist starts resolution");
 s.player.playing=false;s.player.state=Player.STATE_READY;s.resumeOnFocusGain=true;s.pause();check(!s.resumeOnFocusGain,"pause after focus loss invalidates resume");
 s.playbackRequested=true;s.attemptReconnect();s.pendingReconnectTask.get();s.pause();s.mainHandler.drain();check(!s.player.playing,"queued reconnect cannot resume after pause");
 s.playbackRequested=true;s.hasAudioFocus=false;s.attemptReconnect();s.pendingReconnectTask.get();s.mainHandler.drain();check(!s.player.playing,"queued reconnect cannot play without focus");
 s.playbackRequested=true;s.hasAudioFocus=true;s.attemptReconnect();s.pendingReconnectTask.get();s.mainHandler.drain();check(s.player.playing,"authorized reconnect still plays");
 s.currentUrl="https://radio.test/hls";s.currentMimeType="application/x-mpegURL";s.setMediaItemAndPrepare(s.currentUrl);
 check("application/x-mpegURL".equals(s.player.lastItem.mime),"extensionless HLS uses detected MIME");
 s.playbackRequested=true;s.hasAudioFocus=true;s.attemptReconnect();s.pendingReconnectTask.get();s.mainHandler.drain();
 check("application/x-mpegURL".equals(s.player.lastItem.mime),"extensionless HLS retry preserves MIME");
 s.currentUrl="https://radio.test/hls.m3u";s.currentMimeType="application/x-mpegURL";s.attemptReconnect();s.pendingReconnectTask.get();s.mainHandler.drain();
 check("application/x-mpegURL".equals(s.player.lastItem.mime),"m3u HLS retry preserves MIME");
 s.titleRules=List.of(new MetadataRule("(Song)","$2"));check("Song".equals(s.applyRules(s.titleRules,"Song")),"invalid regex replacement contained");
 } finally{s.executor.shutdownNow();}
 if(failures>0)throw new AssertionError(failures+" regression(s)");
 }
}
"""
with tempfile.TemporaryDirectory(prefix='tiaudiostream-android-tests-') as temp:
 root=pathlib.Path(temp)
 (root/'JavaProbe.java').write_text(preamble+methods+main)
 subprocess.run(['javac','-d',str(root),str(root/'JavaProbe.java')],check=True)
 subprocess.run(['java','-cp',str(root),'JavaProbe'],check=True)
