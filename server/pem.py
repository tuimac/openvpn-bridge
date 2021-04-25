 # -*- coding: utf-8 -*-

from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
import os
import sys
import time
import traceback

class DFPem:
    @staticmethod
    def run(ip="0.0.0.0", port=80, filename=''):
        try:
            class ServerHandler(BaseHTTPRequestHandler):
                def do_GET(self):
                    self.send_response(200)
                    self.send_header("Content-type", "text/html; charset=utf-8")
                    self.send_header("Content-Disposition", "attachment; filename=" + os.path.basename(filename))
                    self.end_headers()
                    with open(filename, 'rb') as f:
                        self.wfile.write(f.read())
                    os.remove(filename)
                    sys.exit(0)

            httpServer = HTTPServer((ip, port), ServerHandler)
            httpServer.serve_forever()
        except:
            traceback.print_exc()

if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(1)
    filename = sys.argv[1]
    port = int(sys.argv[2])
    DFPem.run(filename=filename, port=port)
