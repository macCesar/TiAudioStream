"""Exercise the production Foundation HTTP/playlist loader with local fixtures."""
import http.server
import pathlib
import subprocess
import tempfile
import threading

repo = pathlib.Path(__file__).resolve().parents[1]

class Fixtures(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        path = self.path.split('?', 1)[0]
        code = int(path[1:4]) if path[1:4] in ('404', '429', '503') else 200
        base = f'http://127.0.0.1:{self.server.server_port}'
        bodies = {
            '/named.m3u': '#EXTM3U\nfile.php?token=value\n',
            '/plain.m3u': '../folder/../audio.mp3\n',
            '/absolute.pls': f'[playlist]\nFile1={base}/audio.mp3\n',
            '/relative.pls': '[playlist]\nFile1=audio.mp3\n',
            '/relative.m3u': '#EXTM3U\n../audio.mp3\n',
            '/hls.m3u': '#EXTM3U\n#EXT-X-TARGETDURATION:6\nsegment.ts\n',
            '/list': '#EXTM3U\naudio.mp3\n',
            '/live': 'fake live audio', '/empty.pls': '[playlist]\n', '/huge': 'x' * 2048,
        }
        body = bodies.get(path, '').encode()
        self.send_response(code)
        self.send_header('Content-Type', 'audio/mpeg' if path == '/live' else 'application/octet-stream')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

with tempfile.TemporaryDirectory(prefix='tiaudiostream-content-') as tmp:
    binary = pathlib.Path(tmp) / 'content'
    subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', '-I', str(repo/'ios/Classes'),
                    str(repo/'tests/ios_content.m'), str(repo/'ios/Classes/TiAudiostreamContentLoader.m'), '-o', str(binary)], check=True)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixtures)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        subprocess.run([str(binary), f'http://127.0.0.1:{server.server_port}/'], check=True, timeout=20)
    finally:
        server.shutdown()
