import argparse, tempfile, http.server, json, pathlib, subprocess, threading, time, urllib.parse
parser=argparse.ArgumentParser(description='Silent second-pass fixture; outputs live outside the repository')
parser.add_argument('--output',type=pathlib.Path,default=None)
parser.add_argument('--host',default='127.0.0.1')
parser.add_argument('--port',type=int,default=18767)
args=parser.parse_args()
root=args.output or pathlib.Path(tempfile.mkdtemp(prefix='tiaudiostream-silent-'))
root.mkdir(parents=True,exist_ok=True)
print('Evidence directory:',root,flush=True)
assets=root/'fixtures';assets.mkdir(exist_ok=True)
for name,freq in [('A',440),('B',880),('C',1760)]:
 subprocess.run(['ffmpeg','-v','error','-y','-f','lavfi','-i',f'sine=frequency={freq}:duration=8','-af','volume=0','-c:a','libmp3lame','-b:a','128k',str(assets/(name+'.mp3'))],check=True)
subprocess.run(['ffmpeg','-v','error','-y','-f','lavfi','-i','testsrc=size=2048x2048:duration=1','-frames:v','1',str(assets/'cover.png')],check=True)
tones={k:(assets/(k+'.mp3')).read_bytes() for k in 'ABC'}; cover=(assets/'cover.png').read_bytes();lock=threading.Lock()
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_POST(self):
  body=self.rfile.read(int(self.headers.get('Content-Length','0')))
  try:
   result=json.loads(body); platform=result.get('platform','unknown'); assert platform in ['android','ipad','iphone']
   (root/(platform+'-physical.json')).write_text(json.dumps(result,indent=2))
   self.send_response(200);self.end_headers();self.wfile.write(b'ok')
  except Exception:self.send_error(400)
 def do_GET(self):
  parsed=urllib.parse.urlsplit(self.path);query=urllib.parse.parse_qs(parsed.query);path=parsed.path
  with lock:
   with (root/'requests.jsonl').open('a') as f:f.write(json.dumps({'at':time.time(),'path':path,'query':query,'range':self.headers.get('Range'),'icy':self.headers.get('Icy-MetaData'),'ua':self.headers.get('User-Agent')})+'\n')
  delay=float(query.get('delay',['0'])[0]);time.sleep(min(delay,10))
  status=int(query.get('status',['200'])[0])
  if status!=200:self.send_error(status);return
  if path=='/cover.png':
   self.send_response(200);self.send_header('Content-Type','image/png');self.send_header('Content-Length',str(len(cover)));self.end_headers()
   try:self.wfile.write(cover)
   except (BrokenPipeError,ConnectionResetError):pass
   return
  if path.endswith('.pls') or path.endswith('.m3u'):
   station=query.get('station',['A'])[0];body=(('[playlist]\nFile1=' if path.endswith('.pls') else '#EXTM3U\n')+'/stream/'+station+'.mp3\n').encode()
   self.send_response(200);self.send_header('Content-Type','audio/x-scpls' if path.endswith('.pls') else 'audio/x-mpegurl');self.send_header('Content-Length',str(len(body)));self.end_headers()
   try:self.wfile.write(body)
   except (BrokenPipeError,ConnectionResetError):pass
   return
  name=path.rsplit('/',1)[-1].split('.')[0]
  if name not in tones:self.send_error(404);return
  data=tones[name];icy=self.headers.get('Icy-MetaData')=='1'
  self.send_response(200);self.send_header('Content-Type','audio/mpeg')
  if path.startswith('/finite/'):
   self.send_header('Content-Length',str(len(data)));self.end_headers()
   try:self.wfile.write(data)
   except (BrokenPipeError,ConnectionResetError):pass
   return
  if icy:self.send_header('icy-metaint','8192')
  self.end_headers();pos=0;chunks=0
  try:
   while True:
    chunk=(data+data)[pos:pos+8192];pos=(pos+8192)%len(data);self.wfile.write(chunk)
    if icy:
     metadata=("StreamTitle='Audit Artist - Station "+name+"';").encode();size=(len(metadata)+15)//16;self.wfile.write(bytes([size])+metadata.ljust(size*16,b'\0'))
    self.wfile.flush();chunks+=1
    if query.get('cut') and chunks>=int(query['cut'][0]):return
    time.sleep(.25)
  except (BrokenPipeError,ConnectionResetError):pass
http.server.ThreadingHTTPServer((args.host,args.port),Handler).serve_forever()
