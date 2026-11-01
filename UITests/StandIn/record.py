#!/usr/bin/env python3
"""Records a scratch Arc's answers for the stand-in server (serve.py), which the simulator
screenshot tests run against in CI, where no real Arc is available.

    python3 UITests/StandIn/record.py http://127.0.0.1:8099 TOKEN

Point it only at a scratch Arc built from arc-media-server with tools/testmedia's library, never
at a real server. Pictures aren't recorded (serve.py draws placeholders) and the token isn't kept.
"""
import json, os, sys, urllib.parse, urllib.request

base, token = sys.argv[1].rstrip("/"), sys.argv[2]
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
os.makedirs(out, exist_ok=True)
saved = {}

def key(method, path, query=None):
    q = "&".join(f"{k}={v}" for k, v in sorted((query or {}).items()))
    return f"{method} {path}" + (f"?{q}" if q else "")

def call(method, path, query=None, body=None):
    url = f"{base}/api/v1/{path}" + ("?" + urllib.parse.urlencode(query) if query else "")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            status, raw = r.status, r.read()
    except urllib.error.HTTPError as e:
        status, raw = e.code, e.read()
    doc = json.loads(raw) if raw else None
    saved[key(method, path, query)] = {"status": status, "body": doc}
    return doc

for p in ["health", "auth/status", "identity", "libraries", "me/prefs", "home/next-up", "watchlist"]:
    call("GET", p)
call("GET", "home/continue", {"with_up_next": "1"})
status = saved[key("GET", "auth/status")]["body"]
# One answer per profile (serve.py picks by the body's id); a PIN profile is chosen without its PIN.
for prof in status["profiles"]:
    body = {"id": prof["id"]}
    call("POST", "auth/profile", body=body)
    saved[key("POST", "auth/profile") + "#" + prof["id"]] = saved.pop(key("POST", "auth/profile"))
    if saved[key("POST", "auth/profile") + "#" + prof["id"]]["status"] != 200:
        saved[key("POST", "auth/profile") + "#" + prof["id"]] = {"status": 200, "body": prof}

ids, series = set(), set()
def collect(items):
    for it in items or []:
        it = it.get("item", it)
        ids.add(it["id"])
        if it.get("kind") == "series": series.add(it["id"])
        if it.get("parent_id"): series.add(it["parent_id"])

for lib in call("GET", "libraries"):
    kind = "series" if lib["kind"] == "shows" else "movie"
    page = call("GET", "items", {"library_id": str(lib["id"]), "kind": kind, "sort": "added", "limit": "24"})
    collect(page.get("items"))
    if lib["kind"] == "shows":
        collect(call("GET", f"libraries/{lib['id']}/recent-shows"))
# The library tabs: each sort (the stand-in answers any other /items with one of these), the
# filters, collections, folders (Other videos), the playlists tab and search as it's typed.
people = set()
for lib in call("GET", "libraries"):
    kind = "series" if lib["kind"] == "shows" else "movie"
    for sort in ["title", "added", "release", "year", "rating", "runtime", "watched"]:
        collect(call("GET", "items", {"library_id": str(lib["id"]), "kind": kind, "sort": sort, "offset": "0", "limit": "60"}).get("items"))
    call("GET", f"libraries/{lib['id']}/facets")
    for c in call("GET", f"libraries/{lib['id']}/collections") or []:
        collect(call("GET", f"collections/{c['id']}").get("items"))
    if lib["kind"] == "videos":
        def walk(path):
            page = call("GET", f"libraries/{lib['id']}/folders", {"path": path} if path else None)
            collect(page.get("items"))
            for f in page.get("folders") or []:
                walk(f["path"])
        walk("")
for pl in call("GET", "playlists") or []:
    collect(call("GET", f"playlists/{pl['id']}").get("entries"))
for word in ["firefly", "alien"]:
    for n in range(1, len(word) + 1):
        found = call("GET", "search", {"q": word[:n]})
        for p in found.get("people") or []:
            people.add(p["id"])

for p in ["home/continue?with_up_next=1", "home/next-up", "watchlist"]:
    k = key("GET", *p.split("?")) if "?" not in p else key("GET", "home/continue", {"with_up_next": "1"})
    collect(saved[k]["body"])

for s in sorted(series):
    seasons = call("GET", f"series/{s}/seasons")
    for season in (seasons or {}).get("seasons", []):
        collect(season.get("episodes"))
caps = {"containers": ["mp4", "mov"], "video": ["h264", "hevc"], "audio": ["aac", "mp3", "ac3", "eac3"], "hdr": [], "max_height": 2160}
for i in sorted(ids):
    item = call("GET", f"items/{i}")
    for c in (item.get("credits") or [])[:8]:
        people.add(c["person_id"])
    if item.get("kind") in ("movie", "series"):
        call("GET", f"items/{i}/similar")
    if item.get("kind") == "episode":
        call("GET", f"items/{i}/next")
    if item.get("kind") in ("movie", "episode"):
        call("POST", f"items/{i}/playback", body={"caps": caps, "start_ms": 0})

for p in sorted(people):
    call("GET", f"people/{p}")

with open(os.path.join(out, "answers.json"), "w") as f:
    json.dump(saved, f, indent=1, sort_keys=True)
print(f"{len(saved)} answers, {len(ids)} titles")
