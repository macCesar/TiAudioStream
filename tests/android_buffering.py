"""Focused source-loading regression with production methods and a gated HTTP response.

Run: python3 tests/android_buffering.py
"""
import pathlib
import subprocess
import tempfile

repo = pathlib.Path(__file__).resolve().parents[1]
source = (repo / 'android/src/ti/audiostream/MediaPlaybackService.java').read_text()


def method(signature):
    start = source.index(signature)
    pos = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[pos] == '{') - (source[pos] == '}')
        pos += 1
    return source[start:pos]


methods = '\n'.join(method(s) for s in [
    'private void cancelPlaylistResolution()', 'private boolean isNativeAudioUrl(', 'private void preparePlayback()', 'private void play()',
    'private void setMediaItemAndPrepare(', 'private PlaybackSource resolvePlaylist(',
    'private static final class PlaybackSource', 'private boolean isPlaylistUrl(',
    'private String parsePlaylist(', 'private String readPlaylistBody(',
])
methods = methods.replace('org.appcelerator.kroll.common.TiConfig.LOGD', 'false')
methods = methods.replace('androidx.media3.common.MimeTypes.APPLICATION_M3U8', '"application/x-mpegURL"')

java = r'''
import java.io.*; import java.net.*; import java.util.*; import java.util.concurrent.*; import java.util.regex.*;
import java.util.concurrent.atomic.*;
class DiagnosticLog {static void d(String a,String b){} static void i(String a,String b){}
 static void w(String a,String b){} static void e(String a,String b){}}
class AudiostreamModule {
 static List<String> events=new ArrayList<>();
 static void fireState(String s){events.add(s);} static void fireError(String s){}
}
class PlaybackStateCompat {static final int STATE_BUFFERING=6,STATE_PAUSED=2,STATE_ERROR=7,STATE_PLAYING=3,STATE_STOPPED=1;}
class Player {
 static final int STATE_IDLE=1,STATE_BUFFERING=2,STATE_ENDED=4; boolean playing; int prepared;
 boolean isPlaying(){return playing;} int getPlaybackState(){return STATE_IDLE;}
 void addListener(Object x){} void removeListener(Object x){} void clearMediaItems(){} void pause(){playing=false;} void stop(){playing=false;} void play(){playing=true;} void prepare(){prepared++;} void setMediaItem(MediaItem item){}
}
class MediaItem {static class Builder {
 Builder setUri(String s){return this;} Builder setMimeType(String s){return this;}
 MediaItem build(){return new MediaItem();}}}
class Session {boolean active=false;boolean isActive(){return active;} void setActive(boolean b){active=b;}}
class Handler {
 Queue<Runnable> tasks=new ConcurrentLinkedQueue<>();
 void post(Runnable r){tasks.add(r);} void drain(){Runnable r;while((r=tasks.poll())!=null)r.run();}
}
public class BufferingProbe {
 static final String LCAT="test"; String currentUrl,currentMimeType;
 boolean controlsVisible,playbackRequested,playbackFailed,playlistPending,isLive=true;
 boolean allowForeground=true; int lastStartId=1,sessionState;
 boolean hasAudioFocus=true; boolean serviceDestroyed; Object playerListener;Object createPlayerListener(long g){return new Object();} final Object playlistConnectionLock=new Object();HttpURLConnection playlistConnection;Future<?> playlistTask;ExecutorService playlistExecutor=Executors.newSingleThreadExecutor();
 Player player=new Player(); Session mediaSession=new Session(); Handler mainHandler=new Handler();
 ExecutorService executor=Executors.newSingleThreadExecutor(); AtomicLong streamGeneration=new AtomicLong();
 boolean startForegroundWithNotification(){return allowForeground;}
 boolean stopSelfResult(int id){return true;} void removeNotification(){}
 boolean requestAudioFocus(){hasAudioFocus=true;return true;} void updatePlaybackState(int state){sessionState=state;}
 static void check(boolean ok,String name){if(!ok)throw new AssertionError(name);System.out.println("PASS "+name);}
'''
main = r'''
 public static void main(String[] args)throws Exception {
  CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
  com.sun.net.httpserver.HttpServer server=com.sun.net.httpserver.HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
  server.createContext("/live",e->{
   entered.countDown();try{release.await();}catch(InterruptedException ex){Thread.currentThread().interrupt();}
   e.getResponseHeaders().set("Content-Type","audio/mpeg");e.sendResponseHeaders(200,0);e.close();
  });
  server.start();BufferingProbe p=new BufferingProbe();
  String url="http://127.0.0.1:"+server.getAddress().getPort()+"/live";
  try {
   p.currentUrl=url;p.preparePlayback();
   check(entered.await(2,TimeUnit.SECONDS),"HTTP response is held before headers");
   check(AudiostreamModule.events.isEmpty(),"configuration without play does not announce buffering");
   p.play();
   check(AudiostreamModule.events.contains("buffering"),"cold start reports buffering while HTTP is still blocked");
   check(p.sessionState==PlaybackStateCompat.STATE_BUFFERING,"system media session reports source loading");
   check(p.player.prepared==0,"buffering precedes Media3 preparation");
   AudiostreamModule.events.clear();p.player.playing=true;p.preparePlayback();
   check(AudiostreamModule.events.contains("buffering"),"station switch reports loading");
   check(!p.player.isPlaying(),"old audio stops before resolution finishes");
   AudiostreamModule.events.clear();p.playbackRequested=false;p.preparePlayback();
   check(AudiostreamModule.events.isEmpty(),"paused configuration does not announce buffering");
   release.countDown();p.playlistExecutor.submit(()->{}).get(5,TimeUnit.SECONDS);p.mainHandler.drain();
   check(p.player.prepared==1,"only newest source resolution prepares the player");
   check(AudiostreamModule.events.isEmpty()&&!p.playbackRequested,"late HTTP completion cannot report loading or resume a paused request");
   AudiostreamModule.events.clear();p.currentUrl="";p.play();
   check(!AudiostreamModule.events.contains("buffering")&&!p.playbackRequested,"invalid URL cannot announce buffering or retain playback intent");
   AudiostreamModule.events.clear();p.currentUrl=url;p.playlistPending=true;p.allowForeground=false;p.play();
   check(!AudiostreamModule.events.contains("buffering")&&p.sessionState==PlaybackStateCompat.STATE_ERROR,"denied foreground start cannot announce buffering and clears native loading");
  }finally{release.countDown();p.executor.shutdownNow();p.playlistExecutor.shutdownNow();server.stop(0);}
 }
}
'''
with tempfile.TemporaryDirectory(prefix='tiaudiostream-buffering-') as temp:
    root = pathlib.Path(temp)
    (root / 'BufferingProbe.java').write_text(java + methods + main)
    subprocess.run(['javac', '-d', str(root), str(root / 'BufferingProbe.java')], check=True)
    subprocess.run(['java', '-cp', str(root), 'BufferingProbe'], check=True, timeout=20)
