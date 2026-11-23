#!/usr/bin/env python3
"""A stand-in Arc for the simulator screenshot tests: it answers /api/v1 from answers.json
(recorded from a scratch Arc by record.py), draws a placeholder for every picture, and plays
fixtures/sample.mp4 for every title. Any token is accepted.

    python3 UITests/StandIn/serve.py 8080
"""
import hashlib, http.server, json, os, struct, subprocess, sys, tempfile, urllib.parse, urllib.request, zlib

here = os.path.dirname(os.path.abspath(__file__))
answers = json.load(open(os.path.join(here, "fixtures", "answers.json")))
sample = open(os.path.join(here, "fixtures", "sample.mp4"), "rb").read()
# The recording's Continue Watching has nothing part-watched: put each title 28 minutes in, so
# the cards' resume strip (play mark, progress, minutes left) shows.
for _c in (answers.get("GET home/continue?with_up_next=1", {}).get("body") or []):
    _c["user_data"] = dict(_c.get("user_data") or {}, position_ms=28 * 60_000)
pngs = {}
polls = [0]

# Real pictures from TMDB when the build has a TMDB_API_KEY secret (the recorded titles carry their
# TMDB ids); without one, or when TMDB has nothing, the placeholders below are drawn. The key is
# only sent to TMDB and never logged.
tmdb_key = os.environ.get("TMDB_API_KEY", "").strip()
titles = {}   # item id -> (kind, tmdb id, show's item id)
people = {}   # person id -> name
for _v in answers.values():
    _docs = [_v["body"]] if isinstance(_v["body"], dict) else []
    for _d in list(_docs):
        _docs += [x for x in (_d.get("items") or []) if isinstance(x, dict)]
    for _d in _docs:
        if _d.get("id") and _d.get("kind"):
            titles.setdefault(_d["id"], (_d["kind"], _d.get("tmdb_id"), _d.get("parent_id")))
        for _c in _d.get("credits") or []:
            people[str(_c.get("person_id"))] = _c.get("name")
real = {}

# Watch Together: two rooms on Home's row (one this profile hosts, one Jo invited it to), for the
# first two films recorded. Joining one gives a paused room at the start (the lobby); commands
# change it; its live stream sends it once and stays open.
import threading, time
_films = []
for _v in answers.values():
    _b = _v.get("body")
    for _d in ([_b] if isinstance(_b, dict) else []) + [x for x in ((_b or {}).get("items") or [] if isinstance(_b, dict) else []) if isinstance(x, dict)]:
        if _d.get("kind") == "movie" and _d.get("id") and _d["id"] not in [f["id"] for f in _films]:
            _films.append({"id": _d["id"], "title": _d.get("title", ""), "kind": "movie"})
wt_lock = threading.Lock()
wt_rooms = {}
for _i, (_rid, _hosting) in enumerate([("wt-hosting", True), ("wt-invited", False)]):
    if _i < len(_films):
        wt_rooms[_rid] = {"hosting": _hosting, "item": _films[_i], "revision": 1, "generation": 1, "state": "paused",
                          "position_ms": 0, "at_ms": int(time.time() * 1000), "joined": False}

def wt_listed(rid, r):
    return {"id": rid, "state": r["state"], "position_ms": r["position_ms"], "created_at_ms": 1, "host_name": "Admin" if r["hosting"] else "Jo",
            "hosting": r["hosting"], "joined": r["joined"], "item": r["item"],
            "participants": ["Admin"] if r["joined"] else [], "invited": ["Sam"] if r["hosting"] else []}

def wt_room(rid, r):
    me = {"id": "me", "name": "Admin", "available": True, "ready": True, "state": "playing" if r["state"] == "playing" else "paused"}
    people = [me] if r["hosting"] else [me, {"id": "sam", "name": "Sam", "available": True, "ready": True, "state": "paused"}]
    return {"id": rid, "revision": r["revision"], "generation": r["generation"], "state": r["state"], "position_ms": r["position_ms"],
            "at_ms": r["at_ms"], "rate": 1, "server_time_ms": int(time.time() * 1000), "host_id": "me" if r["hosting"] else "",
            "host_name": "Admin" if r["hosting"] else "Jo", "self_id": "me", "available": True, "item_id": r["item"]["id"],
            "item": r["item"], "participants": people, "invited": [{"name": "Sam"}] if r["hosting"] else []}

def tmdb(path, **query):
    q = dict(query)
    headers = {"Accept": "application/json"}
    if len(tmdb_key) > 40:   # a read access token
        headers["Authorization"] = "Bearer " + tmdb_key
    else:
        q["api_key"] = tmdb_key
    req = urllib.request.Request("https://api.themoviedb.org/3/" + path + "?" + urllib.parse.urlencode(q), headers=headers)
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read())

def real_picture(path):
    """A real picture for an Arc image path, or None."""
    if not tmdb_key: return None
    parts = path.split("/")
    try:
        if parts[0] == "people" and len(parts) >= 3:
            name = people.get(parts[1])
            if not name: return None
            key = ("person", name)
            if key not in real:
                hits = tmdb("search/person", query=name).get("results") or []
                pic = next((h.get("profile_path") for h in hits if h.get("profile_path")), None)
                real[key] = fetch("w342", pic) if pic else None
            return real[key]
        if len(parts) == 5 and parts[0] == "series" and parts[2] == "seasons" and parts[4] == "image":
            series, season = parts[1], parts[3]
            kind, tmdb_id, _ = titles.get(series, (None, None, None))
            if kind != "series" or not tmdb_id or not season.isdecimal(): return None
            key = ("season", tmdb_id, season)
            if key not in real:
                try:
                    imgs = tmdb(f"tv/{tmdb_id}/season/{season}/images", include_image_language="en,null")
                    posters = imgs.get("posters") or []
                    pic = next((p["file_path"] for lang in ("en", None) for p in posters
                                if p.get("iso_639_1") == lang and p.get("file_path")), None)
                    real[key] = fetch("w500", pic) if pic else None
                except (OSError, ValueError) as e:
                    sys.stderr.write(f"standin: no TMDB season picture: {type(e).__name__}\n")
                    real[key] = None
            return real[key] or real_picture(f"items/{series}/images/primary")
        if parts[0] != "items" or len(parts) < 4: return None
        item, which = parts[1], parts[3]
        kind, tmdb_id, parent = titles.get(item, (None, None, None))
        if kind in ("episode", "season") and parent:
            kind, tmdb_id, _ = titles.get(parent, (None, None, None))
            if which == "primary": which = "backdrop"   # an episode's still: its show's background
        if not tmdb_id or kind not in ("movie", "series"): return None
        key = (kind, tmdb_id, which)
        if key not in real:
            imgs = tmdb(("movie/" if kind == "movie" else "tv/") + str(tmdb_id) + "/images", include_image_language="en,null")
            pick = lambda xs, langs: next((x["file_path"] for l in langs for x in xs if x.get("iso_639_1") == l), None)
            if which == "logo": pic, size = pick(imgs.get("logos") or [], ["en"]), "w500"
            elif which == "backdrop": pic, size = pick(imgs.get("backdrops") or [], [None, "en"]), "w1280"
            else: pic, size = pick(imgs.get("posters") or [], ["en", None]), "w500"
            real[key] = fetch(size, pic) if pic else None
        return real[key]
    except Exception as e:
        sys.stderr.write(f"standin: no TMDB picture for {path.split('?')[0]}: {type(e).__name__}\n")
        return None

def fetch(size, file_path):
    with urllib.request.urlopen("https://image.tmdb.org/t/p/" + size + file_path, timeout=15) as r:
        data = r.read()
    return (data, "image/png" if file_path.endswith(".png") else "image/jpeg")

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

palettes = {}

def palette(item_id):
    """The four quarter colours of a title's backdrop, shrunk to 2 x 2 with macOS's sips."""
    if item_id in palettes: return palettes[item_id]
    out = {"available": False, "algorithm": "standin", "color_space": "srgb", "artwork_type": "backdrop", "reason": "image_unavailable"}
    item = (answers.get(f"GET items/{item_id}") or {}).get("body") or {}
    images = item.get("images") or {}
    path = images.get("backdrop") or images.get("series_backdrop")
    got = real_picture(path.split("/api/", 1)[-1].split("?")[0]) if path else None
    if got:
        try:
            with tempfile.TemporaryDirectory() as d:
                src, dst = os.path.join(d, "in"), os.path.join(d, "out.bmp")
                open(src, "wb").write(got[0])
                subprocess.run(["sips", "-z", "2", "2", "-s", "format", "bmp", src, "--out", dst], check=True, capture_output=True, timeout=20)
                bmp = open(dst, "rb").read()
            start, = struct.unpack_from("<I", bmp, 10)
            w, h = struct.unpack_from("<ii", bmp, 18)
            bpp, = struct.unpack_from("<H", bmp, 28)
            step = bpp // 8
            stride = (w * step + 3) // 4 * 4
            def at(x, y):
                row = (abs(h) - 1 - y) if h > 0 else y  # rows run bottom up unless the height is negative
                o = start + row * stride + x * step
                b, g, r = bmp[o], bmp[o + 1], bmp[o + 2]
                return f"#{r:02x}{g:02x}{b:02x}"
            out = {"available": True, "algorithm": "standin", "color_space": "srgb", "artwork_type": "backdrop",
                   "colors": {"top_left": at(0, 0), "top_right": at(1, 0), "bottom_left": at(0, 1), "bottom_right": at(1, 1)}}
        except Exception as e:
            sys.stderr.write(f"standin: no palette for {item_id}: {type(e).__name__}\n")
    palettes[item_id] = out
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
        if "/images/" in path or path.endswith("/image"):
            got = real_picture(path)
            if got: return self.send(200, got[0], got[1], {"Cache-Control": "max-age=3600"})
        if path.endswith("/images/logo"): return self.json(404, {"error": "no logo"})
        if "/images/" in path or path.endswith("/image"):
            wide = "backdrop" in path or "thumb" in path or (parts[0] == "items" and path.endswith("primary") and query.get("ep") == "1")
            w, h = (320, 180) if wide else (200, 300)
            return self.send(200, png(path.split("/images/")[0], w, h), "image/png", {"Cache-Control": "max-age=3600"})
        # A title's four artwork colours, from the picture the stand-in serves (as Arc works
        # them out from its cached artwork: one colour for each quarter of the backdrop).
        if method == "GET" and len(parts) == 4 and parts[0] == "items" and parts[2:] == ["artwork", "palette"]:
            return self.json(200, palette(parts[1]))
        # The walk-through's last step: no rooms, so Home opens on Continue Watching (the README's picture).
        if method == "POST" and path == "standin/no-rooms":
            with wt_lock: wt_rooms.clear()
            return self.json(200, {})
        if path.startswith("watch-together"):
            return self.watch_together(method, parts, query, body)
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
        # Timeline thumbnails: one placeholder sheet of 4 x 3 for the 12-second clip.
        if method == "GET" and len(parts) == 3 and parts[0] == "items" and parts[2] == "trickplay":
            return self.json(200, {"info": {"interval_ms": 1000, "width": 320, "height": 180, "columns": 4, "rows": 3, "count": 12, "sheets": 1},
                                   "sheets": [f"/api/items/{parts[1]}/trickplay/{query.get('file', '1')}/0"]})
        if method == "GET" and len(parts) == 5 and parts[0] == "items" and parts[2] == "trickplay":
            return self.send(200, png("trick" + parts[1], 1280, 540), "image/png")
        # Subtitle lines for any track: one every two seconds.
        if method == "GET" and len(parts) == 4 and parts[0] == "items" and parts[2] == "subtitles":
            return self.json(200, {"track": {"id": parts[3]}, "cues": [{"start_ms": i * 2000, "end_ms": i * 2000 + 1800, "text": f"Stand-in subtitles, line {i + 1}"} for i in range(30)]})
        # A library's Recommended rows, made from its titles (the recording has none: it was
        # made before the app asked for them).
        if method == "GET" and len(parts) == 3 and parts[0] == "libraries" and parts[2] == "recommended":
            lib = parts[1]
            titles = next((v["body"].get("items", []) for kk, v in answers.items()
                           if kk.startswith("GET items?") and f"library_id={lib}&" in kk and "sort=added" in kk), [])
            if not titles:
                titles = next((v["body"].get("items", []) for kk, v in answers.items() if kk.startswith("GET items?") and f"parent_id=" not in kk), [])
            kinds = {t.get("kind") for t in titles}
            kinds |= {"episode"} if "series" in kinds else set()
            cont = [c for c in answers.get("GET home/continue?with_up_next=1", {}).get("body") or [] if c.get("kind") in kinds]
            rows = [{"id": "continue", "type": "continue", "title": "Continue Watching", "items": cont},
                    {"id": "added", "type": "recently_added", "title": "Recently Added", "items": titles},
                    {"id": "because", "type": "because_you_watched", "title": "Because you watched", "name": titles[0]["title"] if titles else "", "items": list(reversed(titles))},
                    {"id": "top", "type": "top_rated", "title": "Top Rated", "items": titles[1:] + titles[:1]}]
            return self.json(200, {"rows": [r for r in rows if r["items"]]})
        if path == "search" and "q" in query:
            query["q"] = query["q"].strip().casefold()
        k = key(method, path, query)
        if method == "POST" and path == "auth/profile" and body:
            k += "#" + str(body.get("id"))
        a = answers.get(k) or answers.get(f"{method} {path}")
        if a is None and method == "GET" and parts[0] == "items" and len(parts) == 1:
            a = next((v for kk, v in answers.items() if kk.startswith("GET items?")), None)
        if a is None and method == "GET" and path == "search":
            a = {"status": 200, "body": {"movies": [], "shows": [], "episodes": [], "collections": [], "people": []}}
        # Someone with no page in the fixtures (the made-up cast): the titles that list them,
        # else a handful of the library's, so the person page has rows to show.
        if a is None and method == "GET" and parts[0] == "people" and len(parts) == 2:
            pid = parts[1]
            mine = []
            for kk, v in answers.items():
                if kk.startswith("GET items/") and kk.count("/") == 1 and v["status"] == 200:
                    for c in v["body"].get("credits") or []:
                        if str(c.get("person_id")) == pid:
                            mine.append({"item": v["body"], "character": c.get("character"), "roles": [c.get("role") or "actor"]})
                            break
            if not mine:
                listing = next((v["body"].get("items", []) for kk, v in answers.items() if kk.startswith("GET items?") and "parent_id=" not in kk), [])
                mine = [{"item": it, "character": "Role", "roles": ["actor"]} for it in listing[:8]]
            name = globals()["people"].get(pid) or "Ada Stone"
            a = {"status": 200, "body": {"person": {"id": int(pid) if pid.isdigit() else 0, "name": name, "known_for": "Acting",
                                                    "count": len(mine), "image": f"/api/people/{pid}/image"}, "credits": mine}}
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
            # Two versions, three chapters and a high bitrate, for the Quality, Version and Chapters choices.
            fid = doc.get("file_id") or 1
            doc["versions"] = [{"file_id": fid, "width": 3840, "height": 2160, "video_codec": "hevc", "hdr": "HDR10", "size": 58_000_000_000},
                               {"file_id": fid + 1000, "edition": "Director's Cut", "width": 1920, "height": 1080, "video_codec": "h264", "size": 14_000_000_000}]
            doc["chapters"] = [{"start_ms": 0, "end_ms": 4000, "title": "Opening"}, {"start_ms": 4000, "end_ms": 8000, "title": "The Job"},
                               {"start_ms": 8000, "end_ms": 12000, "title": "Getaway"}]
            doc["source_kbps"] = 25000
        # Films get a trailer and a featurette (they play the sample clip through a cast link).
        # Titles get a cast, a crew, a studio and a 4K Dolby Vision file with Atmos (made-up
        # people), so the title page's badges, Starring line and cards have something to show.
        if method == "GET" and len(parts) == 2 and parts[0] == "items" and a["status"] == 200 and doc.get("kind") in ("movie", "series"):
            people = ["Ada Stone", "Ben Okafor", "Cleo Marsh", "Dev Patel-Ray", "Eli Novak"]
            credits = [{"person_id": 900 + i, "name": n, "role": "actor", "character": f"Role {i + 1}"} for i, n in enumerate(people)]
            credits += [{"person_id": 950, "name": "Fran Leigh", "role": "director"}, {"person_id": 951, "name": "Gus Hart", "role": "writer"}]
            doc = dict(doc, credits=doc.get("credits") or credits, studio=doc.get("studio") or "Stand-in Pictures",
                       tagline=doc.get("tagline") or "A stand-in tagline.")
            if doc.get("kind") == "movie" and doc.get("files"):
                f0 = dict(doc["files"][0], size=58_000_000_000, container="matroska",
                          streams=[{"kind": "video", "codec": "hevc", "width": 3840, "height": 2160, "color_transfer": "smpte2084", "dolby_vision": True},
                                   {"kind": "audio", "codec": "eac3", "profile": "Dolby Digital Plus + Dolby Atmos", "channels": 6, "is_default": True}])
                doc["files"] = [f0] + doc["files"][1:]
        if method == "GET" and len(parts) == 2 and parts[0] == "items" and a["status"] == 200 and doc.get("kind") == "movie":
            doc = dict(doc, extras=[{"id": "e1" + parts[1][:6], "kind": "trailer", "title": "Official Trailer", "duration_ms": 12000, "stream_url": "/api/extras/e1/stream"},
                                    {"id": "e2" + parts[1][:6], "kind": "featurette", "title": "Making Of", "duration_ms": 12000, "stream_url": "/api/extras/e2/stream"}])
        return self.json(a["status"], doc)

    def watch_together(self, method, parts, query, body):
        now = int(time.time() * 1000)
        if len(parts) == 3 and parts[2] == "events":
            # The room once, then the stream stays open (outside the lock) with keep-alives.
            with wt_lock:
                r = wt_rooms.get(parts[1])
                doc = json.dumps(wt_room(parts[1], r)) if r else None
            if doc is None:
                return self.json(404, {"error": "room or playable invitation not found"})
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            try:
                self.wfile.write(f"id: 1\nevent: room\ndata: {doc}\n\n".encode())
                self.wfile.flush()
                for _ in range(6):
                    time.sleep(5)
                    self.wfile.write(b": keep-alive\n\n")
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            self.close_connection = True
            return
        with wt_lock:
            if parts == ["watch-together", "rooms"] and method == "GET":
                return self.json(200, {"rooms": [wt_listed(k, r) for k, r in wt_rooms.items()]})
            if parts == ["watch-together", "rooms"] and method == "POST":
                r = {"hosting": True, "item": next((f for f in _films if f["id"] == (body or {}).get("item_id")), _films[0] if _films else {"id": "", "title": ""}),
                     "revision": 1, "generation": 1, "state": "paused", "position_ms": 0, "at_ms": now, "joined": False}
                wt_rooms["wt-new"] = r
                return self.json(201, {"room": wt_listed("wt-new", r), "invite_code": "K7Q2M4XP", "invite_expires_at_ms": now + 900_000})
            if parts == ["watch-together", "people"]:
                return self.json(200, {"people": [{"id": "sam", "name": "Sam", "color": "blue", "friend": False, "can_watch": True},
                                                   {"id": "jo", "name": "Jo", "color": "rose", "friend": True, "can_watch": True},
                                                   {"id": "kid", "name": "Kid", "color": "amber", "friend": False, "can_watch": False}]})
            if parts == ["watch-together", "time"]:
                return self.json(200, {"client_sent_ms": int(query.get("client_sent_ms", 0)), "server_received_ms": now, "server_sent_ms": now})
            if parts == ["watch-together", "current"]:
                return self.json(404, {"error": "room or playable invitation not found"})
            if len(parts) == 4 and parts[1] == "rooms" and parts[2] in wt_rooms:
                r = wt_rooms[parts[2]]
                if parts[3] == "join":
                    r["joined"] = True
                    return self.json(200, wt_room(parts[2], r))
                if parts[3] == "dismiss":
                    wt_rooms.pop(parts[2], None)
                    return self.send(204, b"")
            if len(parts) >= 2 and parts[1] in wt_rooms:
                rid, r = parts[1], wt_rooms[parts[1]]
                action = parts[2] if len(parts) > 2 else ""
                if action == "commands":
                    a = (body or {}).get("action")
                    pos = r["position_ms"] + (now - r["at_ms"] if r["state"] == "playing" else 0)
                    if a == "play": r.update(state="playing", position_ms=pos, at_ms=now)
                    elif a == "pause": r.update(state="paused", position_ms=pos, at_ms=now)
                    elif a == "seek": r.update(position_ms=int((body or {}).get("position_ms") or 0), at_ms=now, generation=r["generation"] + 1)
                    elif a == "end": r.update(state="ended")
                    r["revision"] += 1
                    return self.json(200, wt_room(rid, r))
                if action == "heartbeat":
                    return self.json(200, wt_room(rid, r))
                if action == "leave":
                    r["joined"] = False
                    return self.send(204, b"")
                if not action:
                    return self.json(200, wt_room(rid, r))
        return self.json(404, {"error": "room or playable invitation not found"})

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

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    print(f"stand-in Arc on http://127.0.0.1:{port}", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
