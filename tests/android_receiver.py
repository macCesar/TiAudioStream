from pathlib import Path
import subprocess, tempfile
workspace=tempfile.TemporaryDirectory(prefix='tiaudiostream-receiver-');root=Path(workspace.name);repo=Path(__file__).resolve().parents[1];s=(repo/'android/src/ti/audiostream/MediaActionReceiver.java').read_text();a=s.index('public void onReceive(');b=s.index('{',a)+1;n=1
while n:n+=(s[b]=='{')-(s[b]=='}');b+=1
method=s[a:b].replace("android.os.Parcelable", "Parcelable")
pre=r'''
class android {static class os {static class Build {static class VERSION {static int SDK_INT=32;} static class VERSION_CODES{static final int TIRAMISU=33,O=26;}}}}
interface Parcelable {}
class KeyEvent implements Parcelable {static final int ACTION_DOWN=0,KEYCODE_MEDIA_PLAY=1,KEYCODE_MEDIA_PAUSE=2,KEYCODE_MEDIA_STOP=3,KEYCODE_MEDIA_NEXT=4,KEYCODE_MEDIA_PREVIOUS=5,KEYCODE_MEDIA_PLAY_PAUSE=6,KEYCODE_HEADSETHOOK=7;int getAction(){return 0;}int getKeyCode(){return 1;}}
class Intent implements Parcelable {static final String EXTRA_KEY_EVENT="key",ACTION_MEDIA_BUTTON="media";Object extra;String action;Intent(){}Intent(Context c,Class<?> k){}Intent setAction(String s){action=s;return this;}String getAction(){return action;}<T extends Parcelable>T getParcelableExtra(String s){if(extra instanceof RuntimeException)throw (RuntimeException)extra;return (T)extra;}<T>T getParcelableExtra(String s,Class<T> c){if(extra instanceof RuntimeException)throw (RuntimeException)extra;return c.isInstance(extra)?c.cast(extra):null;}}
class Context {int starts;void startService(Intent i){starts++;}void startForegroundService(Intent i){starts++;}}
class MediaPlaybackService {static final String ACTION_PLAY="PLAY",ACTION_PAUSE="PAUSE",ACTION_STOP="STOP",ACTION_NEXT="NEXT",ACTION_PREV="PREV",ACTION_PLAY_PAUSE="PLAY_PAUSE";static Intent authorizeCommand(Intent i){return i;}static void releaseHardStopRequest(Intent i){}static boolean isForegroundReady(){return true;}}
class AudiostreamModule {static final int REMOTE_CONTROL_PLAY=1,REMOTE_CONTROL_PAUSE=2,REMOTE_CONTROL_STOP=3,REMOTE_CONTROL_PLAY_PAUSE=4;static void fireRemoteControl(int x){}static void fireState(String s){}static void fireError(String s){}}
public class ReceiverProbe {
'''
main=r'''
 public static void main(String[] args){ReceiverProbe p=new ReceiverProbe();Context c=new Context();Intent i=new Intent().setAction(Intent.ACTION_MEDIA_BUTTON);i.extra=new Intent();
  try{p.onReceive(c,i);System.out.println("PASS legacy receiver ignores non-KeyEvent Parcelable");}catch(ClassCastException e){throw new AssertionError("legacy wrong Parcelable",e);}
  android.os.Build.VERSION.SDK_INT=36;
  try{p.onReceive(c,i);System.out.println("PASS API36 typed getter ignores wrong Parcelable");}catch(Exception e){throw new AssertionError(e);}
  p.onReceive(c,new Intent().setAction("ti.audiostream.SET_STREAM"));
  if(c.starts!=0)throw new AssertionError("configuration forwarded");System.out.println("PASS exported receiver rejects configuration");
  android.os.Build.VERSION.SDK_INT=32;i.extra=new RuntimeException("bad parcel");p.onReceive(c,i);
  if(c.starts!=0)throw new AssertionError("malformed parcel forwarded");System.out.println("PASS malformed parcel ignored");
  i.extra=new KeyEvent();p.onReceive(c,i);if(c.starts!=1)throw new AssertionError("valid legacy key rejected");System.out.println("PASS valid legacy key retained");
  android.os.Build.VERSION.SDK_INT=36;p.onReceive(c,i);if(c.starts!=2)throw new AssertionError("valid typed key rejected");System.out.println("PASS valid typed key retained");

 }
}
'''
(root/'ReceiverProbe.java').write_text(pre+method+main)
subprocess.run(['javac','-d',str(root),str(root/'ReceiverProbe.java')],check=True)
subprocess.run(['java','-cp',str(root),'ReceiverProbe'],check=True)
