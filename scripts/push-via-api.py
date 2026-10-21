#!/usr/bin/env python3
# DeepSeek Bot for iOS — Apache-2.0
#
# 当 `git push` 走不通时（代理 502、公司网络、墙），用 GitHub 的 Git Data API 把
# 最近一次本地提交推上去。生成的远端提交与本地内容一致，但 sha 不同，所以网络恢复后
# 需要 `git fetch origin && git reset --hard origin/main` 对齐一次。
#
#   GITHUB_TOKEN=ghp_xxx python scripts/push-via-api.py --user Richard-Yhn
#   GITHUB_TOKEN=ghp_xxx python scripts/push-via-api.py --user Richard-Yhn --dry-run

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.github.com"
ROOT = Path(__file__).resolve().parent.parent
REPO = "deepseek-bot-ios"


def api(method, path, token, payload=None, tries=4):
    data = None if payload is None else json.dumps(payload).encode()
    last = (-1, "no attempt")
    for attempt in range(tries):
        req = urllib.request.Request(API + path, data=data, method=method)
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        req.add_header("User-Agent", "dsb-push-api")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                body = response.read().decode()
                return response.status, (json.loads(body) if body.strip() else None)
        except urllib.error.HTTPError as error:
            text = error.read().decode()
            if error.code < 500:
                return error.code, text[:300]
            last = (error.code, text[:300])
        except Exception as error:
            last = (-1, f"{type(error).__name__}: {error}")
        time.sleep(2 + attempt * 2)
    return last


def git(*args):
    result = subprocess.run(["git"] + list(args), cwd=str(ROOT), capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} 失败: {result.stderr.strip()[:400]}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--user", required=True)
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN", ""))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    token = args.token.strip()
    if not token and not args.dry_run:
        raise SystemExit("缺少 token：GITHUB_TOKEN=ghp_xxx python scripts/push-via-api.py --user <名字>")

    message = git("log", "-1", "--pretty=%B").rstrip()
    files = [f for f in git("show", "--name-only", "--pretty=format:", "HEAD").splitlines() if f.strip()]
    # 删除的文件没法用 blob 表达，直接拒绝，别悄悄漏掉。
    missing = [f for f in files if not (ROOT / f).exists()]
    if missing:
        raise SystemExit(f"这次提交里有删除的文件，请改用 git push：{missing}")

    print(f"提交信息 {message.splitlines()[0][:60]}")
    print(f"改动文件 {len(files)} 个：{', '.join(files)}")
    if args.dry_run:
        print("[dry-run] 不做任何改动")
        return

    status, ref = api("GET", f"/repos/{args.user}/{REPO}/git/ref/heads/main", token)
    if status != 200:
        raise SystemExit(f"读远端 main 失败 {status}: {ref}")
    base = ref["object"]["sha"]
    status, commit = api("GET", f"/repos/{args.user}/{REPO}/git/commits/{base}", token)
    base_tree = commit["tree"]["sha"]
    print(f"远端 main {base[:12]} | tree {base_tree[:12]}")

    entries = []
    for path in files:
        blob_bytes = (ROOT / path).read_bytes()
        status, blob = api("POST", f"/repos/{args.user}/{REPO}/git/blobs", token,
                           {"content": base64.b64encode(blob_bytes).decode(), "encoding": "base64"})
        if status not in (200, 201):
            raise SystemExit(f"blob {path} 失败 {status}: {blob}")
        entries.append({"path": path, "mode": "100644", "type": "blob", "sha": blob["sha"]})
        print(f"  {path} -> {blob['sha'][:10]} ({len(blob_bytes)} B)")

    status, tree = api("POST", f"/repos/{args.user}/{REPO}/git/trees", token,
                       {"base_tree": base_tree, "tree": entries})
    if status not in (200, 201):
        raise SystemExit(f"tree 失败 {status}: {tree}")

    status, made = api("POST", f"/repos/{args.user}/{REPO}/git/commits", token,
                       {"message": message, "tree": tree["sha"], "parents": [base]})
    if status not in (200, 201):
        raise SystemExit(f"commit 失败 {status}: {made}")

    status, updated = api("PATCH", f"/repos/{args.user}/{REPO}/git/refs/heads/main", token,
                          {"sha": made["sha"], "force": False})
    if status not in (200, 201):
        raise SystemExit(f"更新 ref 失败 {status}: {updated}")

    print(f"\n已推送 -> {made['sha'][:12]}")
    print(f"https://github.com/{args.user}/{REPO}/commit/{made['sha']}")
    print("\n网络恢复后对齐本地：git fetch origin && git reset --hard origin/main")


if __name__ == "__main__":
    main()
