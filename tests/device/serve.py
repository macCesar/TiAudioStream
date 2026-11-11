"""Local HTTP/ICY fixtures for the disposable Titanium device test app."""
import http.server
import pathlib
import subprocess
import tempfile
import time

workspace = tempfile.TemporaryDirectory(prefix='tiaudiostream-device-fixtures-')
root = pathlib.Path(workspace.name)
subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=30', '-af', 'volume=0.02', '-c:a', 'libmp3lame', '-b:a', '128k', str(root/'tone.mp3')], check=True)
subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=navy:s=1024x1024', '-frames:v', '1', str(root/'cover.png')], check=True)
mp3 = (root/'tone.mp3').read_bytes()
cover = (root/'cover.png').read_bytes()
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_GET(self):
        path = self.path.split('?', 1)[0]
        slow = path == '/slow/live.mp3'
        if slow:
            time.sleep(2)
            path = '/live.mp3'
        if path == '/live.mp3':
            icy = self.headers.get('Icy-MetaData') == '1'
            self.send_response(200)
            self.send_header('Content-Type', 'audio/mpeg')
            if icy: self.send_header('icy-metaint', '8192')
            self.end_headers()
            position = 0
            try:
                for _ in range(300):
                    chunk = (mp3 + mp3)[position:position + 8192]
                    position = (position + 8192) % len(mp3)
                    self.wfile.write(chunk)
                    if icy:
                        title = 'New Fixture Song' if slow else 'Fixture Song'
                        metadata = ("StreamTitle='Fixture Artist - " + title + "';").encode()
                        length = (len(metadata) + 15) // 16
                        self.wfile.write(bytes([length]) + metadata.ljust(length * 16, b'\0'))
                    self.wfile.flush()
                    time.sleep(0.25)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        body, mime, code = {
            '/relative.pls': (b'[playlist]\nFile1=live.mp3\n', 'audio/x-scpls', 200),
            '/relative.m3u': (b'#EXTM3U\nlive.mp3\n', 'audio/x-mpegurl', 200),
            '/cover.png': (cover, 'image/png', 200),
            '/503': (b'temporary unavailable', 'text/plain', 503),
        }.get(path, (b'not found', 'text/plain', 404))
        self.send_response(code)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

http.server.ThreadingHTTPServer(('0.0.0.0', 18765), Handler).serve_forever()
