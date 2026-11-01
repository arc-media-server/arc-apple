#!/usr/bin/env python3
"""A stand-in Arc for the simulator screenshot tests: it answers /api/v1 from answers.json
(recorded from a scratch Arc by record.py), draws a placeholder for every picture, and plays
fixtures/sample.mp4 for every title. Any token is accepted.

    python3 UITests/StandIn/serve.py 8080
"""
import hashlib, http.server, json, os, struct, sys, urllib.parse, zlib

here = os.path.dirname(os.path.abspath(__file__))
answers = json.load(open(os.path.join(here, "fixtures", "answers.json")))
sample = open(os.path.join(here, "fixtures", "sample.mp4"), "rb").read()
pngs = {}
polls = [0]

def png(seed, w, h):
    """A dark two-tone gradient in a colour picked from seed: enough to tell cards apart."""
    k = (seed, w, h)
    if k in pngs: return pngs[k]
    d = hashlib.md5(seed.encode()).digest()
    top = [40 + d[0] % 120, 40 + d[1] % 120, 40 + d[2] % 120]
    rows = b""
    for y in range(h):
        f = y / max(h - 1, 1)
        px = bytes(int(c * (1 - 0.7 * f)) for c in top)
        rows += b"\0" + px * w
    def chunk(t, b): return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b"")
    pngs[k] = out
    return out

def key(method, path, query):
    q = "&".join(f"{k}={v}" for k, v in sorted(query.items()) if k != "v")
    return f"{method} {path}" + (f"?{q}" if q else "")

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("standin: " + (fmt % args) + "\n")

    def send(self, status, body, ctype="application/json", extra=None):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items(): self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD": self.wfile.write(body)

    def json(self, status, doc):
        self.send(status, json.dumps(doc).encode() if doc is not None else b"")

    def do_HEAD(self): self.do_GET()
    def do_GET(self): self.route("GET")
    def do_POST(self): self.route("POST")
    def do_PUT(self): self.route("PUT")
    def do_PATCH(self): self.route("PATCH")
    def do_DELETE(self): self.route("DELETE")

    def route(self, method):
        u = urllib.parse.urlsplit(self.path)
        query = dict(urllib.parse.parse_qsl(u.query))
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"null") if length else None
        path = u.path
        if path.startswith("/media/"): return self.media()
        if path.startswith("/api/v1/"): path = path[len("/api/v1/"):]
        elif path.startswith("/api/"): path = path[len("/api/"):]
        parts = path.split("/")
        # Pictures: placeholders, posters tall and backdrops wide. Logos are left out so titles show as text.
        if path.endswith("/images/logo"): return self.json(404, {"error": "no logo"})
        if "/images/" in path or path.endswith("/image"):
            wide = "backdrop" in path or "thumb" in path or (parts[0] == "items" and path.endswith("primary") and query.get("ep") == "1")
            w, h = (320, 180) if wide else (200, 300)
            return self.send(200, png(path.split("/images/")[0], w, h), "image/png", {"Cache-Control": "max-age=3600"})
        # Sign-in with a code: the code is "approved" on the third check, so its screen can be seen.
        if method == "POST" and path == "auth/link":
            return self.json(200, {"code": "K7Q2", "poll": "standin"})
        if method == "GET" and path == "auth/link/standin":
            polls[0] += 1
            return self.json(200, {"token": "standin-token"}) if polls[0] >= 3 else self.json(202, {"status": "waiting"})
        if method == "POST" and path == "cast":
            host = self.headers.get("Host")
            return self.json(200, {"url": f"http://{host}/media/sample.mp4"})
        # Preferences: the recorded ones with the change made (not kept between requests).
        if method == "PATCH" and path == "me/prefs":
            return self.json(200, dict(answers["GET me/prefs"]["body"], **(body or {})))
        if method in ("PUT", "DELETE") or (method == "POST" and (path.endswith("/ping") or path == "auth/logout")):
            return self.send(204, b"")
        # Subtitle lines for any track: one every two seconds.
        if method == "GET" and len(parts) == 4 and parts[0] == "items" and parts[2] == "subtitles":
            return self.json(200, {"track": {"id": parts[3]}, "cues": [{"start_ms": i * 2000, "end_ms": i * 2000 + 1800, "text": f"Stand-in subtitles, line {i + 1}"} for i in range(30)]})
        k = key(method, path, query)
        if method == "POST" and path == "auth/profile" and body:
            k += "#" + str(body.get("id"))
        a = answers.get(k) or answers.get(f"{method} {path}")
        if a is None and method == "GET" and parts[0] == "items" and len(parts) == 1:
            a = next((v for kk, v in answers.items() if kk.startswith("GET items?")), None)
        if a is None and method == "GET" and path == "search":
            a = {"status": 200, "body": {"movies": [], "shows": [], "episodes": [], "collections": [], "people": []}}
        if a is None and method == "GET" and parts[-1] == "next":
            return self.send(204, b"")
        if a is None:
            return self.json(404, {"error": "the stand-in has no answer for " + k})
        doc = a["body"]
        if method == "POST" and parts[-1] == "playback" and a["status"] == 200:
            # Every title plays the sample clip, directly.
            doc = dict(doc, method="direct", hls=False, url=f"/api/items/{parts[1]}/stream", reasons=[], offset_ms=0, duration_ms=12000)
            doc.pop("session_id", None)
            # Something to show the player's Skip Intro and Subtitles with: the clip's first 9
            # seconds are an "intro", and every title has a stand-in subtitle track.
            doc["markers"] = [{"kind": "intro", "start_ms": 0, "end_ms": 9000}]
            doc["subtitle_tracks"] = (doc.get("subtitle_tracks") or []) + [{"id": "standin", "language": "eng", "title": "Stand-in", "codec": "subrip"}]
        return self.json(a["status"], doc)

    def media(self):
        size = len(sample)
        rng = self.headers.get("Range")
        if rng and rng.startswith("bytes="):
            a, _, b = rng[6:].partition("-")
            start = int(a) if a else size - int(b)
            end = int(b) if a and b else size - 1
            end = min(end, size - 1)
            return self.send(206, sample[start:end + 1], "video/mp4", {"Content-Range": f"bytes {start}-{end}/{size}", "Accept-Ranges": "bytes"})
        self.send(200, sample, "video/mp4", {"Accept-Ranges": "bytes"})

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
print(f"stand-in Arc on http://127.0.0.1:{port}", flush=True)
http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
