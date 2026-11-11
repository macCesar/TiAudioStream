"""Build the disposable native reader; requires Android SDK build-tools 36.0.0."""
from pathlib import Path
import argparse, os, subprocess, tempfile, zipfile
parser=argparse.ArgumentParser()
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
source=Path(__file__).resolve().parent
sdk=Path(os.environ.get('ANDROID_SDK_ROOT',str(Path.home()/'Library/Android/sdk')))
tools=sdk/'build-tools/36.0.0';android=sdk/'platforms/android-36/android.jar'
def run(*args):subprocess.run([str(a)for a in args],check=True)
args.output.parent.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='tiaudiostream-controller-')as temp:
 root=Path(temp);(root/'classes').mkdir();(root/'dex').mkdir()
 run('javac','--release','8','-classpath',android,'-d',root/'classes',source/'MainActivity.java')
 run('jar','cf',root/'controller.jar','-C',root/'classes','.')
 run(tools/'d8','--lib',android,'--output',root/'dex',root/'controller.jar')
 run(tools/'aapt2','link','-I',android,'--manifest',source/'AndroidManifest.xml','-o',root/'unsigned.apk')
 with zipfile.ZipFile(root/'unsigned.apk','a')as z:z.write(root/'dex/classes.dex','classes.dex')
 run(tools/'zipalign','-f','4',root/'unsigned.apk',root/'aligned.apk')
 run(tools/'apksigner','sign','--ks',Path.home()/'.android/debug.keystore','--ks-pass','pass:android','--out',args.output.resolve(),root/'aligned.apk')
