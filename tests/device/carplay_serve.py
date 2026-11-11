"""Loopback-only CarPlay fixtures: delayed/colored images and low-volume ICY audio."""
import http.server
import pathlib
import struct
import subprocess
import tempfile
import time
import zlib

def png(rgb):
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data) & 0xffffffff)
    pixels = (b'\0' + bytes(rgb) * 256) * 256
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 256, 256, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')

with tempfile.TemporaryDirectory(prefix='tiaudiostream-carplay-audio-') as tmp:
    mp3file = pathlib.Path(tmp)/'tone.mp3'
    subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=30', '-af', 'volume=0.02', '-c:a', 'libmp3lame', '-b:a', '128k', str(mp3file)], check=True)
    audio = mp3file.read_bytes()
    images = {'/slow-red.png': png((220, 30, 30)), '/blue.png': png((30, 50, 220)), '/green.png': png((20, 180, 50)), '/yellow.png': png((240, 190, 20))}
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_GET(self):
            path = self.path.split('?', 1)[0]
            if path == '/live.mp3':
                icy = self.headers.get('Icy-MetaData') == '1'
                self.send_response(200)
                self.send_header('Content-Type', 'audio/mpeg')
                if icy: self.send_header('icy-metaint', '8192')
                self.end_headers()
                position = 0
                try:
                    for _ in range(1200):
                        self.wfile.write((audio + audio)[position:position+8192])
                        position = (position + 8192) % len(audio)
                        if icy:
                            value = b"StreamTitle='QA Artist - QA Track';"
                            size = (len(value)+15)//16
                            self.wfile.write(bytes([size])+value.ljust(size*16, b'\0'))
                        self.wfile.flush()
                        time.sleep(0.25)
                except (BrokenPipeError, ConnectionResetError):
                    pass
                return
            if path == '/slow-red.png': time.sleep(4)
            image = images.get(path)
            self.send_response(200 if image else 404)
            self.send_header('Content-Type', 'image/png')
            self.send_header('Content-Length', str(len(image or b'')))
            self.end_headers()
            try: self.wfile.write(image or b'')
            except (BrokenPipeError, ConnectionResetError): pass
    http.server.ThreadingHTTPServer(('127.0.0.1', 18766), Handler).serve_forever()
