# Discussion draft — Discussions → Ideas

> ✅ **已发布（2026-10-22 01:22）**：<https://github.com/Fei2411/DeepSeek-Bot/discussions/419>
> 分类 Ideas，标题与正文即下面的内容。等维护者回应。

Post at:
<https://github.com/Fei2411/DeepSeek-Bot/discussions/new?category=ideas>

Per `CONTRIBUTING.md` and `.github/ISSUE_TEMPLATE/config.yml`, a feature idea goes to
Discussions (`category=ideas`); pull requests are limited to collaborators for now, so
this is the way in for anyone outside the team.

Title:

```
A room-log endpoint so a client other than this window can read a group chat
```

Body (English, the repository's language):

---

**What I would like**

A read-only endpoint on `POST /api/bot`:

```
room-log { roomId, before?, limit? }
→ { seq, kept, limit, lines: [{ seq, who, botId?, kind?, length?, files?, text }], cursor }
```

Newest page first, cursor by `seq`, `kept` reporting how many lines the host still
holds. `length` only when the host cut the text (as `state.rooms[].log` already does),
so `file-text` remains the way to fetch the whole post.

**Why**

`state` carries only the last line of each room as `preview` — `view()` destructures
`log` out of every room:

```js
rooms: Object.values(state.rooms).map(({ log, seen, lateRounds, sessions, segments, ...room }) => {
  const last = (log ?? []).filter(line => line.kind === undefined).at(-1)
  return { ...room, parts, ...(last ? { preview: … } : {}) }
})
```

and `chat` / `earlier` both go through `partsOf(botId)`, which returns `[]` for a room
id, so they answer `Unknown Bot`.

The result is that a client which is not this window cannot read a group chat at all —
an iPhone client, a desktop panel, a CLI. Writing already works (`send` with `room.id`),
so this only fills in the read side.

**A patch is ready if it is wanted**

Branch on my fork (one commit on top of `ae63b45`):

```
https://github.com/Richard-Yhn/DeepSeek-Bot/tree/feat/room-log
```

What it touches:

| File | Change |
|---|---|
| `ds-bot/src/host/room-log.js` | new: pure paging over the array, no DSH imports |
| `ds-bot/src/host/channel.js` | one `case`, and `room-log` in `READS` |
| `ds-bot/test/room-log.test.js` | new: 9 cases |

`node --check` on both files and `node --test ds-bot/test/room-log.test.js` pass
(9/9) without `dev/harness/`, because the paging is a pure function — the same shape as
`bot-draft.js` and its test. I could not run `npm test` / `npm run lint` / the smoke
test here, so those are the first things to run.

It is additive: no existing endpoint, payload or return value changes, and it follows
`room-progress` in shape and in error codes (`bot/not-found` for an unknown room).

**If you would rather not take it**

No problem — say so and I will keep it in my own client, where it already works
against a patched host and falls back cleanly against an unpatched one.

---

**Notes for Richard (not part of the post)**

- 这条不是 bug，走 bug 模板会被当成走错门，所以在这里发。
- 发完把链接记下来；如果维护者说"可以，开个 PR"，让他把你加成 collaborator 或临时放开
  限制，然后重跑 `python scripts/publish.py --user Richard-Yhn`（PR 那步会自动成功）。
- 也可以在 Discussion 里直接请他把这个 commit cherry-pick 进去，省一轮。
