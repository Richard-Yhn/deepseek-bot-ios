#!/usr/bin/env python3
# DeepSeek Bot for iOS — Apache-2.0
#
# 一条命令做完四件事，用的是 GitHub 的 REST API + git，不依赖 gh CLI：
#   1. 在你的账号下建 deepseek-bot-ios（已存在就跳过）
#   2. 把本地 iOS 仓的 main 推上去
#   3. fork 上游 Fei2411/DeepSeek-Bot，把 feat/room-log 分支推上去
#   4. 对上游 dev 开 PR（已存在就打印链接）
#
# 用法：
#   GITHUB_TOKEN=ghp_xxx python scripts/publish.py --user Richard-Yhn
#   python scripts/publish.py --user Richard-Yhn --dry-run     # 只看会做什么
#
# token 只在环境变量里，不写文件、不进 git 历史。

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.github.com"
UPSTREAM = "Fei2411/DeepSeek-Bot"
IOS_REPO = "deepseek-bot-ios"
BRANCH = "feat/room-log"
PR_TITLE = "feat: add a room-log endpoint so a client can read a group chat"

ROOT = Path(__file__).resolve().parent.parent          # deepseek-bot-ios/
WORKSPACE = ROOT.parent                                # 工作区
IOS_DIR = ROOT
UPSTREAM_DIR = WORKSPACE / "_src" / "ds-bot"

ok = lambda text: print(f"  \033[32m✓\033[0m {text}")
info = lambda text: print(f"  · {text}")
warn = lambda text: print(f"  \033[33m!\033[0m {text}")
fail = lambda text: print(f"  \033[31m✗\033[0m {text}")


def request(method, path, token, payload=None, accept="application/vnd.github+json", tries=4):
    url = path if path.startswith("http") else API + path
    data = None if payload is None else json.dumps(payload).encode()
    last = (-1, {"message": "no attempt"})
    for attempt in range(tries):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("Accept", accept)
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        req.add_header("User-Agent", "deepseek-bot-ios-publisher")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=45) as response:
                body = response.read().decode()
                return response.status, (json.loads(body) if body.strip() else None)
        except urllib.error.HTTPError as error:
            body = error.read().decode()
            try:
                parsed = json.loads(body)
            except Exception:
                parsed = {"message": body[:400]}
            # 5xx 是 GitHub 自己的抖动，值得重试；4xx 是我们的问题，直接回。
            if error.code < 500:
                return error.code, parsed
            last = (error.code, parsed)
        except Exception as error:                     # SSL EOF、超时、连接重置
            last = (-1, {"message": f"{type(error).__name__}: {error}"})
        time.sleep(2 + attempt * 2)
    return last


def git(args, cwd):
    result = subprocess.run(["git"] + args, cwd=str(cwd), capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} 失败:\n{result.stderr.strip()[:1500]}")
    return result.stdout.strip()


def push_url(user, repo, token):
    # 令牌只出现在这一条命令的 URL 里，不写进 .git/config。
    return f"https://x-access-token:{token}@github.com/{user}/{repo}.git"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--user", required=True, help="你的 GitHub 用户名")
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN", ""))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--base", default="", help="PR 的目标分支，默认 dev（没有就 main）")
    args = parser.parse_args()

    user = args.user.strip()
    token = args.token.strip()
    if not args.dry_run and not token:
        raise SystemExit("缺少 token：GITHUB_TOKEN=ghp_xxx python scripts/publish.py --user " + user)

    print(f"\n== 1/5 校验 token ==")
    if args.dry_run:
        info(f"[dry-run] 会用 {user} 的身份调用 GitHub API")
        login = user
    else:
        status, body = request("GET", "/user", token)
        if status != 200:
            raise SystemExit(f"token 无效（HTTP {status}）：{(body or {}).get('message')}")
        login = body.get("login", "")
        ok(f"身份 {login}")
        if login.lower() != user.lower():
            warn(f"token 属于 {login}，不是 {user}；按 {login} 继续")

    print(f"\n== 2/5 仓库 {login}/{IOS_REPO} ==")
    if args.dry_run:
        info(f"[dry-run] 不存在则创建 {IOS_REPO}，然后把 main 推上去")
    else:
        status, body = request("GET", f"/repos/{login}/{IOS_REPO}", token)
        if status == 404:
            status, body = request("POST", "/user/repos", token, {
                "name": IOS_REPO,
                "description": "iOS client for DeepSeek Bot (DeepSeek Harness + ds-bot), in a grok-build-ios shell",
                "homepage": f"https://github.com/{login}/{IOS_REPO}",
                "private": False,
                "has_issues": True,
                "has_wiki": False,
            })
            if status not in (200, 201):
                raise SystemExit(f"建仓失败（HTTP {status}）：{(body or {}).get('message')}")
            ok(f"已创建 {login}/{IOS_REPO}")
            time.sleep(2)
        elif status == 200:
            info("已存在，直接用")
        else:
            raise SystemExit(f"查仓失败（HTTP {status}）：{(body or {}).get('message')}")

        remotes = git(["remote"], IOS_DIR).split()
        if "origin" in remotes:
            git(["remote", "set-url", "origin", f"https://github.com/{login}/{IOS_REPO}.git"], IOS_DIR)
        else:
            git(["remote", "add", "origin", f"https://github.com/{login}/{IOS_REPO}.git"], IOS_DIR)
        git(["push", push_url(login, IOS_REPO, token), "main:main"], IOS_DIR)
        ok(f"main 已推送 → https://github.com/{login}/{IOS_REPO}")

    print(f"\n== 3/5 fork 上游 ==")
    if args.dry_run:
        info(f"[dry-run] 没有 fork 就 fork {UPSTREAM}")
    else:
        status, body = request("GET", f"/repos/{login}/{UPSTREAM.split('/')[1]}", token)
        if status == 200:
            info("fork 已存在")
        else:
            status, body = request("POST", f"/repos/{UPSTREAM}/forks", token, {"default_branch_only": False})
            if status not in (200, 201, 202):
                raise SystemExit(f"fork 失败（HTTP {status}）：{(body or {}).get('message')}")
            ok("已请求 fork")
            for _ in range(30):
                time.sleep(3)
                # fork 是异步的：等它真的可读，别急着推。
                status, _body = request("GET", f"/repos/{login}/{UPSTREAM.split('/')[1]}", token)
                if status == 200:
                    break
            else:
                raise SystemExit("等 fork 超时（90 秒），稍后重跑同一条命令即可")

    print(f"\n== 4/5 推送 {BRANCH} ==")
    if not UPSTREAM_DIR.exists():
        raise SystemExit(f"找不到上游克隆：{UPSTREAM_DIR}（先 git clone {UPSTREAM} 到那里）")
    current = git(["branch", "--show-current"], UPSTREAM_DIR)
    if current != BRANCH:
        raise SystemExit(f"{UPSTREAM_DIR} 当前在 {current}，不是 {BRANCH}")
    if args.dry_run:
        info(f"[dry-run] git push {login}/DeepSeek-Bot {BRANCH}")
    else:
        git(["push", push_url(login, UPSTREAM.split("/")[1], token), f"{BRANCH}:{BRANCH}"], UPSTREAM_DIR)
        ok(f"分支已推送 → https://github.com/{login}/{UPSTREAM.split('/')[1]}/tree/{BRANCH}")

    print(f"\n== 5/5 开 PR ==")
    if args.dry_run:
        base = args.base or "上游默认分支（dev 比 main 旧时用 main）"
    elif args.base:
        base = args.base
    else:
        # 上游的 dev 常常落后于 main；对着落后的 dev 开 PR 会把无关提交一起带进去，
        # 所以默认用仓库自己的默认分支，--base 可以强制指定。
        status, repo = request("GET", f"/repos/{UPSTREAM}", token)
        default = (repo or {}).get("default_branch", "main") if isinstance(repo, dict) else "main"
        base = default
        if base != "dev":
            warn(f"base 用 {base}（上游 dev 比它旧，对着 dev 开 PR 会带上无关提交）")
    info(f"目标分支 {base}")
    if args.dry_run:
        info(f"[dry-run] POST /repos/{UPSTREAM}/pulls  head={login}:{BRANCH}  base={base}")
        print("\n[dry-run] 结束，没有改动任何东西。")
        return

    status, body = request("GET", f"/repos/{UPSTREAM}/pulls?head={login}:{BRANCH}&state=open", token)
    if status == 200 and body:
        ok(f"PR 已存在：{body[0]['html_url']}")
        return

    pr_body = (ROOT / "docs" / "upstream-pr-body.md").read_text(encoding="utf-8")
    status, body = request("POST", f"/repos/{UPSTREAM}/pulls", token, {
        "title": PR_TITLE,
        "head": f"{login}:{BRANCH}",
        "base": base,
        "body": pr_body,
        "maintainer_can_modify": True,
    })
    if status not in (200, 201):
        message = (body or {}).get("message", "")
        errors = (body or {}).get("errors", "")
        compare = f"https://github.com/{UPSTREAM}/compare/{base}...{login}:{BRANCH}?expand=1"
        if status == 404:
            # 分支已经推好了，缺的只是"对别人的仓库开 PR"这一步。GitHub 在账号受限
            # （邮箱未验证、或该仓库限制了新贡献者）时只会回一个含糊的 404，网页才说原因。
            warn("API 开 PR 返回 404。分支已在 fork 上，缺的是对上游开 PR 的权限。")
            print(f"\n用网页点一下就能开（页面会显示真正的原因）：\n  {compare}\n")
            print("如果网页也拒绝：先确认 github.com/settings/emails 里的邮箱已验证，")
            print("再看上游仓库的 issue/PR 是否限制了新贡献者；处理完重跑本脚本即可。")
            raise SystemExit(2)
        raise SystemExit(f"开 PR 失败（HTTP {status}）：{message} {errors}")
    ok(f"PR 已开：{body['html_url']}")

    print("\n完成：")
    print(f"  iOS 仓    https://github.com/{login}/{IOS_REPO}")
    print(f"  iOS CI    https://github.com/{login}/{IOS_REPO}/actions")
    print(f"  PR        {body['html_url']}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
