#!/usr/bin/env python3
"""
모든 Claude 프로파일(~/.claude, ~/.claude-*)에 대해:
  1) skills repo의 각 스킬을 <profile>/skills/<name> 심링크로 설치 (모든 프로파일)
  2) SessionStart 훅으로 doil-secretary 활성화 프롬프트 주입
     - settings.json이 있는(초기화된) 프로파일에만
     - 기존 SessionStart 훅은 보존하고 append (예: ~/.claude의 gptaku 훅)
     - 이미 doil-secretary 훅이 있으면 dedup으로 건너뜀 (idempotent)

옵션:
  --all-settings  : settings.json이 없는 프로파일에도 새로 만들어 훅 주입
  --dry-run       : 변경 없이 계획만 출력
"""
import json, os, glob, sys

HOME = os.path.expanduser('~')
REPO = '/DEVELOP/DOIL/skills'
DRY = '--dry-run' in sys.argv
ALL_SETTINGS = '--all-settings' in sys.argv

skills = sorted(d for d in os.listdir(REPO)
                if os.path.isfile(os.path.join(REPO, d, 'SKILL.md')))
profiles = sorted(p for p in ([os.path.join(HOME, '.claude')] + glob.glob(os.path.join(HOME, '.claude-*')))
                  if os.path.isdir(p))

inner = json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
        "additionalContext": "'/doil-secretary' 스킬을 활성화하고 비서로서 작동한다"}}, ensure_ascii=False)
CMD = "printf '%s' " + json.dumps(inner, ensure_ascii=False)
ENTRY = {"hooks": [{"type": "command", "command": CMD}]}

def has_doil(ss):
    for e in ss or []:
        for h in e.get("hooks", []):
            if "doil-secretary" in (h.get("command") or ""):
                return True
    return False

print(f"{'DRY-RUN' if DRY else 'APPLY'}  skills={skills}  profiles={len(profiles)}\n")
print(f"{'profile':<38} {'symlinks':<16} {'hook'}")
print("-" * 82)
for p in profiles:
    sk = os.path.join(p, 'skills')
    made = 0
    if not DRY:
        os.makedirs(sk, exist_ok=True)
    for s in skills:
        link = os.path.join(sk, s); tgt = os.path.join(REPO, s)
        cur = os.path.realpath(link) if (os.path.islink(link) or os.path.exists(link)) else None
        if cur != os.path.realpath(tgt):
            made += 1
            if not DRY:
                if cur is not None:
                    os.remove(link)
                os.symlink(tgt, link)
    sym = f"{made} new/fixed"

    sj = os.path.join(p, 'settings.json')
    if os.path.isfile(sj):
        try:
            with open(sj) as f: s = json.load(f)
        except Exception as ex:
            print(f"{os.path.basename(p):<38} {sym:<16} SKIP(parse-err:{ex})"); continue
        ss = s.setdefault('hooks', {}).setdefault('SessionStart', [])
        if has_doil(ss):
            hk = "already(dedup)"
        else:
            hk = "INJECT(append)"
            if not DRY:
                ss.append(ENTRY)
                with open(sj, 'w') as f:
                    json.dump(s, f, ensure_ascii=False, indent=2); f.write('\n')
    elif ALL_SETTINGS:
        hk = "CREATE settings+INJECT"
        if not DRY:
            with open(sj, 'w') as f:
                json.dump({"hooks": {"SessionStart": [ENTRY]}}, f, ensure_ascii=False, indent=2); f.write('\n')
    else:
        hk = "no settings.json -> skip"
    print(f"{os.path.basename(p):<38} {sym:<16} {hk}")
