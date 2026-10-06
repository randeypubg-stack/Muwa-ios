"""Loopback-only native networking fixture; never loads production credentials."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import json

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    redirect_hits = 0
    def log_message(self, *args): pass
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', '0')))
        if self.path == '/redirect':
            self.send_response(307)
            self.send_header('Location', '/redirect-target')
            self.send_header('Content-Length', '0')
            self.end_headers()
        else:
            self.do_GET()
    def do_GET(self):
        try:
            if self.path == '/redirect-target': Handler.redirect_hits += 1
            self.send_response(200)
            if self.path in {'/declared-large', '/chunked-large'}:
                chunked = self.path == '/chunked-large'
                self.send_header('Transfer-Encoding', 'chunked') if chunked else self.send_header('Content-Length', str(11 * 1024 * 1024))
                self.end_headers()
                # Send real bytes: declaring a length and closing an empty body
                # tests connection loss, not the client's size boundary.
                for _ in range(176):
                    self.wfile.write((b'10000\r\n' if chunked else b'') + b'x' * 65536 + (b'\r\n' if chunked else b''))
                if chunked: self.wfile.write(b'0\r\n\r\n')
                return
            body = json.dumps({'cookie': self.headers.get('Cookie', '')} if self.path == '/cookie' else {'redirectHits': Handler.redirect_hits}).encode()
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print('http://127.0.0.1:' + str(server.server_port), flush=True)
server.serve_forever()
