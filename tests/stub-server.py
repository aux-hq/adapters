#!/usr/bin/env python3
"""Tiny HTTP stub for the Aux dispatch and outcome-callback endpoints.

Used by the integration test job to stand in for the Aux control plane.
- GET  /dispatch -> 200 with the contents of --dispatch-file (requires Bearer auth).
- POST /result   -> 204; appends the request body as a JSON line to --record-file.
"""
from __future__ import annotations

import argparse
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("stub-server: " + (fmt % args) + "\n")

    def _check_auth(self) -> bool:
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            self.send_error(401, "missing bearer token")
            return False
        return True

    def do_GET(self):  # noqa: N802 (stdlib mandates this name)
        if self.path == "/dispatch":
            if not self._check_auth():
                return
            with open(self.server.dispatch_file, "rb") as f:  # type: ignore[attr-defined]
                payload = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self.send_error(404)

    def do_POST(self):  # noqa: N802
        if self.path == "/result":
            if not self._check_auth():
                return
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            with open(self.server.record_file, "ab") as f:  # type: ignore[attr-defined]
                f.write(body)
                f.write(b"\n")
            self.send_response(204)
            self.end_headers()
            return
        self.send_error(404)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--dispatch-file", required=True)
    ap.add_argument("--record-file", required=True)
    args = ap.parse_args()

    open(args.record_file, "wb").close()  # truncate

    httpd = HTTPServer(("127.0.0.1", args.port), Handler)
    httpd.dispatch_file = args.dispatch_file  # type: ignore[attr-defined]
    httpd.record_file = args.record_file  # type: ignore[attr-defined]
    sys.stderr.write(f"stub-server: listening on 127.0.0.1:{args.port}\n")
    httpd.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
