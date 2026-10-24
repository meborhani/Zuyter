#!/usr/bin/env python3
"""Small CLI over the official Instagram API (Instagram Login). Stdlib only.

Env:
  IG_ACCESS_TOKEN   long-lived token (never printed, never stored by this script)
  IG_API_VERSION    default v21.0
  IG_API_HOST       default graph.instagram.com

Commands (read):  me | media [--limit N] | insights MEDIA_ID [--metrics a,b] | comments MEDIA_ID
Commands (write): reply COMMENT_ID TEXT --yes
                  publish --image-url URL --caption TEXT --yes
                  publish --video-url URL --caption TEXT --yes      (Reel)
Write commands only print what they WOULD do unless --yes is passed.
"""
import argparse, json, os, sys, time, urllib.error, urllib.parse, urllib.request

HOST = os.environ.get("IG_API_HOST", "graph.instagram.com")
VER = os.environ.get("IG_API_VERSION", "v21.0")


def call(method, path, params=None):
    token = os.environ.get("IG_ACCESS_TOKEN")
    if not token:
        sys.exit("IG_ACCESS_TOKEN is not set")
    params = dict(params or {})
    params["access_token"] = token
    url = f"https://{HOST}/{VER}/{path}"
    data = None
    if method == "GET":
        url += "?" + urllib.parse.urlencode(params)
    else:
        data = urllib.parse.urlencode(params).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=data, method=method), timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace").replace(token, "***")
        sys.exit(f"HTTP {e.code}: {body}")


def out(obj):
    print(json.dumps(obj, ensure_ascii=False, indent=2))


def need_yes(args, what):
    if not args.yes:
        print(f"DRY RUN, nothing sent. Would: {what}\nRe-run with --yes after the user approves this exact content.")
        sys.exit(0)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("me")
    m = sub.add_parser("media"); m.add_argument("--limit", type=int, default=25)
    i = sub.add_parser("insights"); i.add_argument("media_id"); i.add_argument("--metrics", default="reach,saved,shares")
    c = sub.add_parser("comments"); c.add_argument("media_id")
    r = sub.add_parser("reply"); r.add_argument("comment_id"); r.add_argument("text"); r.add_argument("--yes", action="store_true")
    b = sub.add_parser("publish"); b.add_argument("--image-url"); b.add_argument("--video-url")
    b.add_argument("--caption", default=""); b.add_argument("--yes", action="store_true")
    a = p.parse_args()

    if a.cmd == "me":
        out(call("GET", "me", {"fields": "user_id,username,account_type,followers_count,follows_count,media_count"}))
    elif a.cmd == "media":
        out(call("GET", "me/media", {"limit": a.limit, "fields": "id,caption,media_type,permalink,timestamp,like_count,comments_count"}))
    elif a.cmd == "insights":
        out(call("GET", f"{a.media_id}/insights", {"metric": a.metrics}))
    elif a.cmd == "comments":
        out(call("GET", f"{a.media_id}/comments", {"fields": "id,text,username,timestamp,like_count"}))
    elif a.cmd == "reply":
        need_yes(a, f"reply to comment {a.comment_id}: {a.text!r}")
        out(call("POST", f"{a.comment_id}/replies", {"message": a.text}))
    elif a.cmd == "publish":
        if bool(a.image_url) == bool(a.video_url):
            sys.exit("give exactly one of --image-url / --video-url")
        kind = "Reel" if a.video_url else "image post"
        need_yes(a, f"publish {kind} {a.video_url or a.image_url} with caption {a.caption!r}")
        params = {"caption": a.caption}
        params.update({"media_type": "REELS", "video_url": a.video_url} if a.video_url else {"image_url": a.image_url})
        cid = call("POST", "me/media", params)["id"]
        for _ in range(30):  # wait for processing
            st = call("GET", cid, {"fields": "status_code"}).get("status_code")
            if st == "FINISHED":
                break
            if st == "ERROR":
                sys.exit("media processing failed")
            time.sleep(5)
        out(call("POST", "me/media_publish", {"creation_id": cid}))


if __name__ == "__main__":
    main()
