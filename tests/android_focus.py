"""Focus changes while a source is still preparing; actual listener and player methods."""
import pathlib
import subprocess
import tempfile

repo=pathlib.Path(__file__).resolve().parents[1]
path=repo/'tests/android_transitions.py'
text=path.read_text()
setup=text[:text.index("java+=r'''\n public static void main")]
namespace={'__file__':str(path)}
exec(compile(setup,str(path),'exec'),namespace)
java=namespace['java'].replace('TransitionProbe','FocusProbe')
java=java.replace('public class FocusProbe {','''class AudioManager {
 static final int AUDIOFOCUS_GAIN=1,AUDIOFOCUS_LOSS=-1,AUDIOFOCUS_LOSS_TRANSIENT=-2,AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK=-3;
 interface OnAudioFocusChangeListener {void onAudioFocusChange(int change);}
}
public class FocusProbe {''')
java=java.replace('void pause(){playing=false;}', 'void setVolume(float value){} void pause(){playing=false;}')
java=java.replace('static void fireRemoteControl(int n)', 'static int focusEvents;static void fireAudioFocusChange(int n){focusEvents++;} static void fireRemoteControl(int n)')
java+='\nvoid cancelPendingReconnect(){}\n'+namespace['method']('private void pause()')
java+='\n'+namespace['method']('private final AudioManager.OnAudioFocusChangeListener audioFocusListener')+';\n'
java=java.replace('org.appcelerator.kroll.common.TiConfig.LOGD','false')
java+=r'''
 public static void main(String[] args)throws Exception {
 FocusProbe p=new FocusProbe();
 try {
 p.currentUrl="https://fixture/stream.mp3";p.playbackRequested=true;p.controlsVisible=true;p.hasAudioFocus=true;p.player.state=Player.STATE_BUFFERING;
 p.sessionState=PlaybackStateCompat.STATE_BUFFERING;AudiostreamModule.events.clear();
 p.audioFocusListener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT);
 check(p.sessionState==PlaybackStateCompat.STATE_PAUSED&&AudiostreamModule.events.contains("paused"),"transient focus loss reports paused even before first audio");
 check(p.playbackRequested&&p.resumeOnFocusGain,"transient focus loss preserves conditional resume intent");
 p.setMediaItemAndPrepare(p.currentUrl);check(!p.player.playing,"late source completion cannot play without audio focus");
 p.audioFocusListener.onAudioFocusChange(AudioManager.AUDIOFOCUS_GAIN);check(p.player.playing&&!p.resumeOnFocusGain,"focus regain resumes the prepared selected source");
 p.player.playing=false;p.player.state=Player.STATE_BUFFERING;p.audioFocusListener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT);
 p.pause();p.setMediaItemAndPrepare(p.currentUrl);p.audioFocusListener.onAudioFocusChange(AudioManager.AUDIOFOCUS_GAIN);
 check(!p.player.playing&&!p.playbackRequested,"manual pause during focus loss wins over late preparation and gain");
 p.playbackRequested=true;p.controlsVisible=true;p.player.playing=false;p.player.state=Player.STATE_BUFFERING;AudiostreamModule.events.clear();
 p.audioFocusListener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS);
 check(!p.playbackRequested&&p.sessionState==PlaybackStateCompat.STATE_PAUSED&&AudiostreamModule.events.contains("paused"),"permanent focus loss reports paused during loading");
 p.setMediaItemAndPrepare(p.currentUrl);check(!p.player.playing,"permanent focus loss cannot be undone by source completion");
 p.serviceDestroyed=true;p.hasAudioFocus=false;p.resumeOnFocusGain=true;p.playbackRequested=true;int focusCount=AudiostreamModule.focusEvents;
 p.audioFocusListener.onAudioFocusChange(AudioManager.AUDIOFOCUS_GAIN);
 check(!p.player.playing&&!p.hasAudioFocus&&AudiostreamModule.focusEvents==focusCount,"retired service ignores queued focus callbacks");

 }finally{p.cancelPlaylistResolution();p.playlistExecutor.shutdownNow();p.executor.shutdownNow();}
 }
}
'''
with tempfile.TemporaryDirectory(prefix='tiaudiostream-focus-') as temp:
    root=pathlib.Path(temp);(root/'FocusProbe.java').write_text(java)
    subprocess.run(['javac','-d',str(root),str(root/'FocusProbe.java')],check=True)
    subprocess.run(['java','-cp',str(root),'FocusProbe'],check=True,timeout=20)
