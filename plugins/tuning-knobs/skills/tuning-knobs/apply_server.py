#!/usr/bin/env python3
"""
apply_server.py — closes the tuning loop with zero dependencies (stdlib only).

It serves the harness HTML and accepts the "Apply to code" POST, writing the
chosen values to a JSON file that Claude then reads and applies to the real
source. Serving the page (rather than opening it via file://) is what makes the
in-page Apply button work — same origin, no CORS/mixed-content issues.

Usage:
    python3 apply_server.py --html card.tuner.html --out .tuner-values.json --once

  --html   path to the harness file to serve at "/"        (required)
  --out    where to write the values payload on Apply       (default: .tuner-values.json)
  --once   exit 0 after the first Apply (clean for an agent to await)
  --port   fixed port (default: first free port from 8731)

On Apply the process prints "APPLIED <out>" to stdout. With --once it then exits,
so an agent can simply run it in the foreground and read <out> when it returns.
"""

import argparse
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

args = None  # set in main()


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body=b"", ctype="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            try:
                with open(args.html, "rb") as f:
                    self._send(200, f.read(), "text/html; charset=utf-8")
            except OSError as e:
                self._send(500, f"cannot read {args.html}: {e}".encode())
        else:
            self._send(404, b"not found")

    def do_POST(self):
        if self.path != "/apply":
            self._send(404, b"not found")
            return
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw or b"{}")
        except json.JSONDecodeError as e:
            self._send(400, f"bad json: {e}".encode())
            return
        with open(args.out, "w") as f:
            json.dump(payload, f, indent=2)
        self._send(200, b'{"ok":true}', "application/json")
        changed = payload.get("changed", {})
        print(
            f"APPLIED {args.out}  ({len(changed)} changed: {', '.join(changed) or 'none'})",
            flush=True,
        )
        if args.once:
            # Defer shutdown so this response flushes first.
            import threading

            threading.Thread(target=self.server.shutdown, daemon=True).start()

    def log_message(self, *a):  # quiet the default per-request logging
        pass


def pick_port(preferred):
    import socket

    candidates = [preferred] if preferred else range(8731, 8800)
    for p in candidates:
        with socket.socket() as s:
            try:
                s.bind(("127.0.0.1", p))
                return p
            except OSError:
                continue
    sys.exit("no free port found")


def main():
    global args
    ap = argparse.ArgumentParser()
    ap.add_argument("--html", required=True)
    ap.add_argument("--out", default=".tuner-values.json")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--once", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(args.html):
        sys.exit(f"--html not found: {args.html}")

    port = pick_port(args.port)
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"tuning-knobs: open  http://localhost:{port}", flush=True)
    print(
        f"  serving {args.html} → will write {args.out} on Apply"
        + ("  (exits after first Apply)" if args.once else ""),
        flush=True,
    )
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    print("tuning-knobs: server stopped", flush=True)


if __name__ == "__main__":
    main()
