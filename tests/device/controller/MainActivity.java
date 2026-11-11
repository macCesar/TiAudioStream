package audit.controller;
import android.app.*;import android.content.*;import android.media.browse.*;import android.media.session.*;import android.media.*;import android.os.*;import android.graphics.*;import android.net.*;import org.json.*;import java.util.*;import java.io.*;
public class MainActivity extends Activity {
 MediaBrowser browser;MediaController controller;JSONArray events=new JSONArray();Handler handler=new Handler();String command; AudioManager audioManager; AudioManager.OnAudioFocusChangeListener focusListener = change -> record("focusChange",change);
 void record(String type,Object value){try{JSONObject e=new JSONObject();e.put("at",System.currentTimeMillis());e.put("type",type);e.put("value",value);events.put(e);android.util.Log.i("AuditController",e.toString());}catch(Exception x){}}
 void save(){try{JSONObject result=new JSONObject();result.put("command",command);result.put("events",events);try(FileOutputStream f=new FileOutputStream(new File(getFilesDir(),"controller-results.json"))){f.write(result.toString(2).getBytes("UTF-8"));}}catch(Exception x){record("saveError",x.toString());}}
 String hash(byte[] data)throws Exception{byte[] h=java.security.MessageDigest.getInstance("SHA-256").digest(data);StringBuilder b=new StringBuilder();for(byte x:h)b.append(String.format("%02x",x));return b.toString();}
 void inspect(){try{
  MediaMetadata m=controller.getMetadata();record("state",controller.getPlaybackState()==null?-1:controller.getPlaybackState().getState());
  if(m==null)return;record("title",m.getString(MediaMetadata.METADATA_KEY_TITLE));
  Bitmap b=m.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART);if(b!=null){record("embeddedArtwork",b.getWidth()+"x"+b.getHeight());ByteArrayOutputStream bytes=new ByteArrayOutputStream();b.compress(Bitmap.CompressFormat.PNG,100,bytes);record("embeddedHash",hash(bytes.toByteArray()));}
  String uri=m.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI);if(uri!=null&&!uri.isEmpty())try(InputStream in=getContentResolver().openInputStream(Uri.parse(uri))){ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] buf=new byte[8192];int count;while((count=in.read(buf))!=-1)bytes.write(buf,0,count);byte[] data=bytes.toByteArray();record("uriHash",hash(data));Bitmap image=BitmapFactory.decodeByteArray(data,0,data.length);record("uriArtwork",image==null?"invalid":image.getWidth()+"x"+image.getHeight());}catch(Exception x){record("uriReadError",x.toString());}
 }catch(Exception x){record("inspectError",x.toString());}}
 @Override public void onCreate(Bundle bundle){super.onCreate(bundle);command=getIntent().getStringExtra("command");android.widget.TextView text=new android.widget.TextView(this);text.setText("Controller audit: "+command);setContentView(text);
 browser=new MediaBrowser(this,new ComponentName("mx.codigomovil.audiostreamaudit","ti.audiostream.MediaPlaybackService"),new MediaBrowser.ConnectionCallback(){
  @Override public void onConnectionFailed(){record("connection","failed");save();}
  @Override public void onConnected(){record("connection","connected");controller=new MediaController(MainActivity.this,browser.getSessionToken());
   controller.registerCallback(new MediaController.Callback(){public void onPlaybackStateChanged(PlaybackState state){record("callbackState",state==null?-1:state.getState());}public void onMetadataChanged(MediaMetadata m){record("callbackTitle",m==null?"null":m.getString(MediaMetadata.METADATA_KEY_TITLE));}});
   browser.subscribe(browser.getRoot(),new MediaBrowser.SubscriptionCallback(){public void onChildrenLoaded(String id,List<MediaBrowser.MediaItem> items){JSONArray list=new JSONArray();for(MediaBrowser.MediaItem item:items)list.put(item.getMediaId());record("catalog",list);}});
   inspect();
   if("prepareB".equals(command)){controller.getTransportControls().prepareFromMediaId("B",null);handler.postDelayed(()->{record("command","play after prepare B");controller.getTransportControls().play();},500);}
   if("playB".equals(command))controller.getTransportControls().playFromMediaId("B",null);
   if("stop".equals(command))controller.getTransportControls().stop();
   if(command!=null&&command.startsWith("focus")){audioManager=(AudioManager)getSystemService(AUDIO_SERVICE);record("focusRequested",audioManager.requestAudioFocus(focusListener,AudioManager.STREAM_MUSIC,AudioManager.AUDIOFOCUS_GAIN_TRANSIENT));if("focusPause".equals(command))handler.postDelayed(()->controller.getTransportControls().pause(),2000);handler.postDelayed(()->{record("focusReleased",audioManager.abandonAudioFocus(focusListener));},6000);}
   if("pause".equals(command))controller.getTransportControls().pause();
   if("play".equals(command))controller.getTransportControls().play();
   if("next".equals(command))controller.getTransportControls().skipToNext();
   if("search".equals(command))controller.getTransportControls().playFromSearch("Station C",null);
   handler.postDelayed(()->{inspect();save();},command!=null&&command.startsWith("focus")?8500:4500);
  }
 },null);browser.connect();}
 @Override protected void onDestroy(){if(browser!=null)browser.disconnect();super.onDestroy();}
}
