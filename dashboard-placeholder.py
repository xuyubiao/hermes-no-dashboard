#!/usr/bin/env python3
"""404 placeholder so the platform health check passes on the routed port
while the real service stays off it.
Body text comes from $PLACEHOLDER_BODY (default: "not found").
Port comes from $HERMES_DASHBOARD_PORT (default 8080).
"""
import http.server
import os

_PORT = int(os.environ.get("HERMES_DASHBOARD_PORT", "8080"))
_BODY = os.environ.get("PLACEHOLDER_BODY", "not found").encode()


class _H(http.server.BaseHTTPRequestHandler):
    def _deny(self):
        self.send_response(404)
        self.end_headers()
        self.wfile.write(_BODY)

    do_GET = _deny
    do_POST = _deny
    do_PUT = _deny
    do_DELETE = _deny

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    http.server.HTTPServer(("0.0.0.0", _PORT), _H).serve_forever()
