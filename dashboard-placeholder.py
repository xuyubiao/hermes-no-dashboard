#!/usr/bin/env python3
"""404 placeholder for hermes mode with dashboard disabled.
Listens on $HERMES_DASHBOARD_PORT (default 8080) so the platform
health check passes while the dashboard stays off.
"""
import http.server
import os

_PORT = int(os.environ.get("HERMES_DASHBOARD_PORT", "8080"))


class _H(http.server.BaseHTTPRequestHandler):
    def _deny(self):
        self.send_response(404)
        self.end_headers()
        self.wfile.write(b"dashboard disabled")

    do_GET = _deny
    do_POST = _deny
    do_PUT = _deny
    do_DELETE = _deny

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    http.server.HTTPServer(("0.0.0.0", _PORT), _H).serve_forever()
