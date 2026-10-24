---
name: ig-api
description: Read the user's own Instagram data (profile, posts, insights, comments) and, only after explicit approval, reply to comments or publish through the official Instagram API. Use when the user wants real numbers for /ig-audit, wants comments pulled for /ig-reply, or asks to post or schedule something they already approved.
---

# ig-api

Wraps the official Instagram API with `ig_api.py` (stdlib Python, no installs).
Auth is either the `IG_ACCESS_TOKEN` env var or an environment network secret that adds `Authorization: Bearer` for graph.instagram.com. If `me` returns 401, point the user to
`SETUP.md` in this folder. Never ask for an Instagram password and never print
or save the token.

## Reading

```bash
python3 .claude/skills/ig-api/ig_api.py me
python3 .claude/skills/ig-api/ig_api.py media --limit 30
python3 .claude/skills/ig-api/ig_api.py insights MEDIA_ID --metrics reach,saved,shares
python3 .claude/skills/ig-api/ig_api.py comments MEDIA_ID
```

Feed `media` + `insights` output to `/ig-audit` and `comments` to `/ig-reply`.

## Writing: hard rules

1. Run `/ig-human` on every caption and reply first.
2. Show the user the exact text and media URL. Wait for a clear yes to *that* content.
3. Run the command without `--yes` first (dry run), then with `--yes` only after approval.
4. One approval covers one action. Approval for a post is not approval for a reply.
5. Publishing needs the media at a public HTTPS URL. Local files cannot be posted directly.
