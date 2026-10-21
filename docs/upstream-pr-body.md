## What

`room-log { roomId, before?, limit? }` returns one page of `room.log` over
`POST /api/bot`: newest page first, cursor by `seq`, with `kept` reporting how many
lines the host still holds.

## Why

`state` carries only the last line of each room as `preview` — `view()` destructures
`log` out of every room — and `chat` / `earlier` both gate on `botOf(sessionId)`,
which a room id never satisfies. So a client that is not this window has no way to
read a group chat: an iPhone client, a desktop panel, a CLI, all of them.

Writing already works (`send` with `room.id`). This adds the read side.

## How

- `src/host/room-log.js` — pure paging over the array, no DSH imports, so
  `test/room-log.test.js` covers it without `dev/harness/`.
- `src/host/channel.js` — one `case`, and `room-log` in `READS`, so a host that only
  reads the team still answers it.
- A line the host cut keeps the head it stored plus `length`; `file-text` still
  fetches the whole text, so long posts need nothing new.

## API

```json
{ "endpoint": "room-log", "payload": { "roomId": "…", "before": 41, "limit": 20 } }

{ "ok": true, "value": {
    "seq": 58,
    "kept": 60,
    "limit": 20,
    "lines": [
      { "seq": 42, "who": "阿鲸", "botId": "…", "text": "…" },
      { "seq": 43, "who": "User", "text": "…", "length": 9000 }
    ],
    "cursor": { "before": 42 }
} }
```

- `before` is the `seq` of the oldest line the caller already holds; the answer is the
  newest `limit` lines older than it. `limit` is clamped to 1..`ROOM_LOG_KEPT`.
- `cursor` is `null` once the log is read to its start, or the host has dropped those
  lines (it keeps `ROOM_LOG_KEPT`).
- `length` only appears when the text was cut in state; `files` only when the post
  carried any.
- Unknown `roomId` answers `bot/not-found` instead of throwing.

## Compatibility

Additive. No existing endpoint, payload or return value changes. It follows
`room-progress` in shape and in error codes.

## Tests

```
node --check ds-bot/src/host/room-log.js
node --check ds-bot/src/host/channel.js
node --test  ds-bot/test/room-log.test.js
# 9 pass / 0 fail
```

`npm test`, `npm run lint` and the smoke test still need a run with `dev/harness/`
installed — I could not fetch those packages where this was written, so treat that as
the first thing to check in CI.

## Context

Written for an iOS client that talks to `POST /api/bot` (SwiftUI, no DSH inside), so
it only ever sees this channel. Without `room-log` that client shows a group chat's
last line and sends the reader to the web view for the rest; with it, the same screen
draws the transcript. Nothing in the plugin's own window changes.
