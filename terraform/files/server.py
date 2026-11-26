"""Lab web server. Returns the S3 message, or the exact error if it cannot read it."""

import os
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

BUCKET = os.environ["LAB_BUCKET"]
REGION = os.environ["LAB_REGION"]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self._send(200, "ok\n")
            return
        result = subprocess.run(
            ["aws", "s3", "cp", f"s3://{BUCKET}/message.txt", "-", "--region", REGION],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode == 0:
            self._send(200, result.stdout + "\n")
        else:
            self._send(502, "Web server is up, but it cannot read from S3:\n" + result.stderr)

    def _send(self, status, body):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


HTTPServer(("0.0.0.0", 80), Handler).serve_forever()
