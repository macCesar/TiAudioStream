"""Source identity, playlist cancellation and external preparation regressions.
Production methods run with a small player substitute and real gated HTTP.
"""
import ast
import pathlib
import subprocess
import tempfile

repo = pathlib.Path(__file__).resolve().parents[1]
source = (repo/'android/src/ti/audiostream/MediaPlaybackService.java').read_text()
def method(signature):
    start=source.index(signature);end=source.index('{',start)+1;depth=1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end]
tree=ast.parse((repo/'tests/android_buffering.py').read_text())
java=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='java' for t in n.targets))
java=java.replace('BufferingProbe','TransitionProbe').replace('STATE_ENDED=4','STATE_ENDED=4,STATE_READY=3').replace('boolean isPlaying(){return playing;}', 'boolean getPlayWhenReady(){return true;} boolean isPlaying(){return playing;}')
java=java.replace('static void e(String a,String b){}', 'static int errors;static void e(String a,String b){errors++;}')
java=java.replace('static List<String> events=new ArrayList<>();', 'static final int REMOTE_CONTROL_PLAY=1,REMOTE_CONTROL_STOP=3;static int remotes;static void fireRemoteControl(int n){remotes++;} static List<String> events=new ArrayList<>();')
java=java.replace('boolean playing; int prepared;', 'boolean playing; int prepared; int state=1; MediaItem item;')
java=java.replace('int getPlaybackState(){return STATE_IDLE;}', 'int getPlaybackState(){return state;}')
java=java.replace('void clearMediaItems(){}','void clearMediaItems(){item=null;state=1;}')
java=java.replace('void setMediaItem(MediaItem item){}','void setMediaItem(MediaItem value){item=value;}')
java=java.replace('class MediaItem {static class Builder {','class MediaItem {String url;static class Builder {String url;')
java=java.replace('Builder setUri(String s){return this;}','Builder setUri(String s){url=s;return this;}')
java=java.replace('return new MediaItem();','MediaItem i=new MediaItem();i.url=url;return i;')
java+='''
 AtomicLong artworkGeneration=new AtomicLong();Object currentArtwork;
 String getStationString(JSONObject s,String k,String fallback){return s.url;}
 void resetMetadataEventDedup(){}void persistCurrentAutomotiveStation(){}void loadArtworkAsync(String u,long g){}String normalizeArtworkUrl(String u){return u;}
 boolean sessionPublishedToSystemUi,systemController;boolean isSystemUiController(){return systemController;}
 boolean resumeOnFocusGain;long generation;static class Bundle {} static class JSONObject {String url;JSONObject(String u){url=u;}}
 static final String RESUME_MEDIA_ID="resume";JSONObject currentAutomotiveStation;
 static final String EXTRA_URL="url",EXTRA_IS_LIVE="live",EXTRA_AUTO_UPDATE_METADATA="auto",EXTRA_TITLE="title",
  EXTRA_ARTIST="artist",EXTRA_ARTWORK_URL="art",EXTRA_METADATA_RULES="rules";
 static class Intent {
  String url;Intent(String url){this.url=url;}
  String getStringExtra(String key){return EXTRA_URL.equals(key)?url:null;}
  boolean getBooleanExtra(String key,boolean fallback){return fallback;}
  boolean hasExtra(String key){return false;}
 }
 String currentTitle,currentArtist;boolean autoUpdateMetadata;
 void handleSetMetadataRules(Intent intent){}
 JSONObject findAutomotiveStation(String id){return new JSONObject(id);}
 void seedPlaybackFieldsFromStation(JSONObject station){currentUrl=station.url;}
 void updateMediaSessionMetadata(){} void updateNotification(){} void resetRetryLogic(){} void abandonAudioFocus(){}
 boolean isTerminalPlaybackError(PlaybackException e){return true;} void attemptReconnect(){throw new AssertionError("stale error retried");}
 static class PlaybackException extends Exception {int errorCode=2004;}
'''
java+='\n'.join(method(s) for s in [
 'private void handleSetStream(', 'private void preparePlayback()', 'private void play()', 'private void setMediaItemAndPrepare(',
 'private void cancelPlaylistResolution()', 'private boolean isNativeAudioUrl(',
 'private PlaybackSource resolvePlaylist(', 'private static final class PlaybackSource',
 'private boolean isPlaylistUrl(', 'private String parsePlaylist(', 'private String readPlaylistBody(',
 'private void rememberSystemUiPlayRequest()', 'private void stop()', 'public void onStop()', 'public void onPlay()', 'public void onIsPlayingChanged(', 'public void onPrepare()', 'public void onPlaybackStateChanged(', 'public void onPlayerError(', 'public void onPrepareFromMediaId('])
java=java.replace('org.appcelerator.kroll.common.TiConfig.LOGD','false').replace('androidx.media3.common.MimeTypes.APPLICATION_M3U8','"application/x-mpegURL"')
java+=r'''
 public static void main(String[] args)throws Exception {
 TransitionProbe p=new TransitionProbe();
 com.sun.net.httpserver.HttpServer server=com.sun.net.httpserver.HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
 ExecutorService serving=Executors.newCachedThreadPool();server.setExecutor(serving);
 CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1),latest=new CountDownLatch(1);
 server.createContext("/old",e->{entered.countDown();try{release.await();}catch(InterruptedException ignored){}try{e.getResponseHeaders().set("Content-Type","audio/mpeg");e.sendResponseHeaders(200,0);e.close();}catch(IOException ignored){}});
 server.createContext("/latest",e->{latest.countDown();e.getResponseHeaders().set("Content-Type","audio/mpeg");e.sendResponseHeaders(200,0);e.close();});
 server.createContext("/mixed",e->{byte[] b="[playlist]\nFile1=/stream/B.mp3\n".getBytes();e.getResponseHeaders().set("Content-Type","Audio/X-Scpls");e.sendResponseHeaders(200,b.length);e.getResponseBody().write(b);e.close();});server.start();
 try {
 p.playerListener=p;p.playbackRequested=true;p.controlsVisible=true;p.playlistPending=true;
 p.onPlayerError(new PlaybackException());check(p.playbackRequested&&AudiostreamModule.events.isEmpty(),"old error while resolving cannot revoke new playback");
 p.playlistPending=false;p.generation=p.streamGeneration.get();p.playbackRequested=false;p.onPlaybackStateChanged(Player.STATE_BUFFERING);
 check(AudiostreamModule.events.isEmpty(),"source preparation after pause cannot replace paused with buffering");p.playbackRequested=true;
 p.streamGeneration.incrementAndGet();p.onPlayerError(new PlaybackException());
 check(p.playbackRequested&&AudiostreamModule.events.isEmpty(),"callback from retired source generation is ignored");
 p.generation=p.streamGeneration.get();p.playerListener=new Object();p.onPlayerError(new PlaybackException());
 check(p.playbackRequested&&AudiostreamModule.events.isEmpty(),"replaced listener cannot fail a retry of the same URL generation");p.playerListener=p;

 p.playerListener=p;p.generation=p.streamGeneration.get();p.player.playing=false;p.playbackRequested=true;p.onPlaybackStateChanged(Player.STATE_READY);
 check(AudiostreamModule.events.isEmpty(),"ready with play intent does not claim audio is playing");
 p.player.playing=true;p.generation=p.streamGeneration.get()-1;p.onPlaybackStateChanged(Player.STATE_READY);check(AudiostreamModule.events.isEmpty(),"retired state callback cannot announce playing");
 p.player.state=3;p.player.playing=true;p.playbackRequested=true;p.sessionState=PlaybackStateCompat.STATE_PLAYING;p.onPrepare();
 check(p.player.playing&&p.sessionState==PlaybackStateCompat.STATE_PLAYING,"resumption prepare preserves active playback state");
 p.onPrepareFromMediaId("https://fixture/B.mp3",new Bundle());
 check(!p.player.playing&&p.player.item==null&&!p.playbackRequested,"prepare B retires A without starting audio");check(AudiostreamModule.events.contains("paused"),"external prepare emits paused to JS when it retires audio");p.play();
 check("https://fixture/B.mp3".equals(p.player.item.url),"play after prepare B installs B");
 check(!p.mediaSession.active,"loading does not advertise active audio ownership");p.generation=p.streamGeneration.get();p.playerListener=p;p.onIsPlayingChanged(true);
 check(p.mediaSession.active&&p.sessionState==PlaybackStateCompat.STATE_PLAYING,"native playing activates audio ownership with truthful state");
 p.playbackRequested=false;p.player.playing=true;p.setMediaItemAndPrepare("https://fixture/paused.mp3");
 check(!p.player.playing,"configuration while paused clears an inherited Media3 play request");
 p.playerListener=p;p.playbackRequested=true;
 p.player.playing=false;p.player.state=Player.STATE_ENDED;p.onPlaybackStateChanged(Player.STATE_ENDED);
 check(!p.playbackRequested&&p.sessionState==PlaybackStateCompat.STATE_STOPPED,"finite EOF clears play intent and leaves resumable stopped controls");
 p.systemController=true;p.sessionPublishedToSystemUi=false;p.playbackRequested=true;p.controlsVisible=true;int remotes=AudiostreamModule.remotes;p.onStop();
 check(p.playbackRequested&&AudiostreamModule.remotes==remotes,"retired SystemUI card cannot cancel an unpublished session or emit a remote Stop");
 p.systemController=false;p.onStop();check(!p.playbackRequested,"other controllers can cancel initial buffering");
 p.systemController=true;p.currentUrl="https://fixture/live.mp3";p.onPlay();boolean explicitSystemUiPlay=p.sessionPublishedToSystemUi;p.onStop();
 check(explicitSystemUiPlay&&!p.playbackRequested,"explicit SystemUI play can be cancelled before first audio");
 p.sessionPublishedToSystemUi=true;p.playbackRequested=true;p.onStop();
 check(!p.playbackRequested,"SystemUI Stop remains valid after the session was published");
 p.mediaSession.setActive(true);p.sessionPublishedToSystemUi=true;p.playbackRequested=true;p.controlsVisible=true;
 p.handleSetStream(new Intent("https://fixture/next.mp3"));p.onStop();
 check(!p.mediaSession.active&&p.playbackRequested,"old SystemUI card cannot stop a new in-app selection during loading");
 p.serviceDestroyed=true;p.playbackRequested=true;int beforeDestroyed=AudiostreamModule.remotes;p.onStop();p.onPlay();
 check(p.playbackRequested&&AudiostreamModule.remotes==beforeDestroyed,"destroyed session cannot forward old transport into the current JS runtime");p.serviceDestroyed=false;


 check("https://fixture/live".equals(p.parsePlaylist("\uFEFF#EXTM3U\nhttps://fixture/live\n")),"UTF8 BOM stripped from playlist");
 String base="http://127.0.0.1:"+server.getAddress().getPort();PlaybackSource mixed=p.resolvePlaylist(base+"/mixed");
 check((base+"/stream/B.mp3").equals(mixed.url),"mixed-case MIME resolves extensionless playlist");
 p.currentUrl=base+"/old";p.preparePlayback();check(entered.await(2,TimeUnit.SECONDS),"obsolete HTTP starts and remains held");
 long at=System.nanoTime();p.currentUrl=base+"/latest";p.preparePlayback();
 check(latest.await(750,TimeUnit.MILLISECONDS),"latest HTTP starts without releasing old response");
 check((System.nanoTime()-at)/1e6<1000,"cancelling obsolete HTTP does not block selection for a second");
 check(DiagnosticLog.errors==0,"intentional HTTP cancellation is not logged as a stream failure");
 }finally{release.countDown();p.cancelPlaylistResolution();p.playlistExecutor.shutdownNow();p.executor.shutdownNow();server.stop(0);serving.shutdownNow();}
 }
}
'''
with tempfile.TemporaryDirectory(prefix='tiaudiostream-transitions-') as temp:
    path=pathlib.Path(temp);(path/'TransitionProbe.java').write_text(java)
    subprocess.run(['javac','-d',str(path),str(path/'TransitionProbe.java')],check=True)
    subprocess.run(['java','-cp',str(path),'TransitionProbe'],check=True,timeout=20)
