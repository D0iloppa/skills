#!/usr/bin/env bash
# test-register-new-skills.sh — register-new-skills.sh 격리 시험.
# 임시 HOME · 가짜 claude/gh · 임시 git repo 에서 dry-run, apply, 멱등, 충돌, GitHub/서브모듈, 롤백, 사용법 오류를 검증한다.
# 실제 HOME·실제 .claude.json·mcp-shared.json·GitHub·실제 데이터 홈은 읽지도 쓰지도 않는다(끝에서 실제 파일 해시가 그대로인지 확인).
# 사용법: bash scripts/test-register-new-skills.sh [--keep]     (종료 코드 0 = 전부 통과)
set -uo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
TARGET="$(dirname "$SELF")/register-new-skills.sh"
KEEP=0; [ "${1:-}" = "--keep" ] && KEEP=1

REAL_HOME="$(getent passwd "$(id -u)" | cut -d: -f6)"
real_sum() { # 실제 환경에 이 스크립트의 흔적이 있는가(읽기 전용). 실행 중인 Claude 세션이 .claude.json 을 수시로 다시 쓰므로
             # 파일 전체 해시 대신 "신규 스킬 항목·백업 파일·링크·데이터 홈·mcp-shared.json" 만 본다.
  { python3 - "$REAL_HOME" <<'PY'
import glob, json, os, sys
home = sys.argv[1]; names = {"doil-health", "doil-portfolio", "doytale"}; hit = []
for f in sorted(glob.glob(home + "/.claude*/.claude.json") + glob.glob(home + "/.claude.json")):
    try:
        m = json.load(open(f)).get("mcpServers") or {}
    except Exception:
        continue
    hit += [f + ":" + n for n in sorted(names & set(m))]
print("registered:", hit)
PY
    ls "$REAL_HOME"/.claude*/.claude.json.bak-regnewskills-* "$REAL_HOME"/.config/void-launcher/*.bak-regnewskills-* 2>/dev/null
    for n in doil-health doil-portfolio doytale; do ls -d "$REAL_HOME"/.claude*/skills/"$n" 2>/dev/null; done
    sha256sum "$REAL_HOME/.config/void-launcher/mcp-shared.json" 2>/dev/null
    ls -ld "$REAL_HOME/.doil-health" 2>&1 | sed 's/[0-9:]\{5\}//'; } | sha256sum | cut -d' ' -f1
}
REAL_BEFORE="$(real_sum)"

T="$(mktemp -d "${TMPDIR:-/tmp}/rns-test.XXXXXX")"
cleanup() { [ "$KEEP" -eq 1 ] && { echo "임시 폴더 유지: $T"; return; }; rm -rf -- "$T"; }
trap cleanup EXIT

PASS=0; FAILN=0
check() { # 이름 조건(0=통과)
  if [ "$2" -eq 0 ]; then PASS=$((PASS + 1)); else FAILN=$((FAILN + 1)); printf 'FAIL: %s\n' "$1"; [ -n "${3:-}" ] && printf '      %s\n' "$3"; fi
}
t_true()  { local n="$1"; shift; "$@" >/dev/null 2>&1; check "$n" $?; }
t_false() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then check "$n" 1; else check "$n" 0; fi; }
t_eq()    { [ "$2" = "$3" ]; check "$1" $? "기대=[$2] 실제=[$3]"; }
has()     { grep -qF -- "$1" "$T/out"; }
t_has()   { has "$2"; check "$1" $? "출력에 [$2] 없음"; }
t_nohas() { if has "$2"; then check "$1" 1 "출력에 [$2] 있음"; else check "$1" 0; fi; }
pj()      { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(eval(sys.argv[2]))' "$1" "$2"; }

# ---------------------------------------------------------------- 가짜 환경
export HOME="$T/home"; mkdir -p "$HOME/.config/void-launcher" "$T/bin" "$T/remotes" "$T/run"
export XDG_RUNTIME_DIR="$T/run" RNS_TEST_LOG="$T/calls.log" FAKE_GH_REMOTES="$T/remotes"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset DOILHEALTH_HOME DOILPORTFOLIO_HOME DOYTALE_HOME CLAUDE_CONFIG_DIR
: > "$RNS_TEST_LOG"
mkdir -p "$T/real/DOIL/skills/scripts" "$T/real/DOIL/doytale/skill"
ln -s "$T/real" "$T/DEVELOP"                                  # /DEVELOP -> 실제 위치 (규칙 재현)
AGG="$T/real/DOIL/skills"; REG="$T/DEVELOP/DOIL"
export RNS_SKILLS_DIR="$AGG" RNS_DOIL_ROOT="$T/real/DOIL" RNS_REGISTER_ROOT="$REG" RNS_GH_URL_BASE="$T/remotes"
export PATH="$T/bin:$PATH"

gitinit() { git -C "$1" init -q && git -C "$1" symbolic-ref HEAD refs/heads/main; }
gitcommit() { git -C "$1" add -A && git -C "$1" commit -q -m "${2:-init}"; }

mk_server() { # <dir> <name>
  mkdir -p "$1/mcp-server/src"
  cat > "$1/mcp-server/src/index.js" <<JS
const fs = require("fs"); fs.writeFileSync((process.env.HOME || "/nonexistent") + "/.probe-touched", "1");
const send = (m) => process.stdout.write(JSON.stringify(m) + "\n");
require("readline").createInterface({ input: process.stdin }).on("line", (l) => {
  let m; try { m = JSON.parse(l); } catch { return; }
  if (m.method === "initialize") send({ jsonrpc: "2.0", id: m.id, result: { protocolVersion: "2025-03-26", capabilities: { tools: {} }, serverInfo: { name: "$2", version: "0" } } });
  else if (m.method === "tools/list") send({ jsonrpc: "2.0", id: m.id, result: { tools: [{ name: "x_status", inputSchema: { type: "object" } }, { name: "x_get", inputSchema: { type: "object" } }] } });
});
JS
}
mk_install() { # <dir> <name> <ENVVAR> <기본홈 상대> <표지 상대> <djinn 0/1>
  cat > "$1/install.sh" <<SH
#!/usr/bin/env bash
set -e
SKILL_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
echo "install \$SKILL_DIR cfg=\${CLAUDE_CONFIG_DIR:-<unset>}" >> "\$RNS_TEST_LOG"
mkdir -p "\$SKILL_DIR/mcp-server/node_modules/@modelcontextprotocol/sdk"
if [ "$6" = 1 ]; then
  d="\$SKILL_DIR/mcp-server/node_modules/@d0iloppa/djinn"; mkdir -p "\$d"
  echo '{"name":"@d0iloppa/djinn","version":"0.2.0","main":"index.js"}' > "\$d/package.json"
  echo 'class DJinn { clearCache() {} } module.exports = { DJinn };' > "\$d/index.js"
  echo '{"packages":{"node_modules/@d0iloppa/djinn":{"resolved":"git+ssh://x/djinn.git#e4c751b"}}}' > "\$SKILL_DIR/mcp-server/node_modules/.package-lock.json"
fi
mkdir -p "\$CLAUDE_CONFIG_DIR/skills"; ln -sfn "\$SKILL_DIR" "\$CLAUDE_CONFIG_DIR/skills/\$(basename "\$SKILL_DIR")"
home="\${$3:-\$HOME/$4}"; mkdir -p -m 700 "\$home"; mkdir -p "\$(dirname "\$home/$5")"
case "$5" in *.db) : > "\$home/$5"; chmod 600 "\$home/$5" ;; *) mkdir -p "\$home/$5" ;; esac
SH
  chmod +x "$1/install.sh"
}
mk_skill() { # <dir> <name> <ENVVAR> <기본홈> <표지> <djinn> [initdb 있음]
  mkdir -p "$1/mcp-server"
  printf -- '---\nname: %s\n---\n' "$2" > "$1/SKILL.md"
  mk_server "$1" "$2"; mk_install "$1" "$2" "$3" "$4" "$5" "$6"; set -- "$1" "$2" "$3" "$4" "$5" "$6" "${7:-}"
  if [ "$6" = 1 ]; then
    echo '{"name":"x","dependencies":{"@d0iloppa/djinn":"git+https://x/djinn.git#e4c751b"}}' > "$1/mcp-server/package.json"
    echo '{"packages":{"node_modules/@d0iloppa/djinn":{"resolved":"git+ssh://x/djinn.git#e4c751b"}}}' > "$1/mcp-server/package-lock.json"
  else echo '{"name":"x"}' > "$1/mcp-server/package.json"; fi
  printf 'node_modules/\n' > "$1/.gitignore"
  if [ -n "$7" ]; then  # init-db.js 가 있는 스킬(health/portfolio): 데이터 홈·표지 생성
    mkdir -p "$1/mcp-server/scripts"
    cat > "$1/mcp-server/scripts/init-db.js" <<JS
const fs = require("fs"), path = require("path");
fs.appendFileSync(process.env.RNS_TEST_LOG, "initdb $2\n");
const home = process.env.$3 || path.join(process.env.HOME, "$4");
fs.mkdirSync(path.dirname(path.join(home, "$5")), { recursive: true, mode: 0o700 }); fs.chmodSync(home, 0o700);
fs.writeFileSync(path.join(home, "$5"), "", { mode: 0o600 });
JS
  fi
}
mk_skill "$AGG/doil-health"    doil-health    DOILHEALTH_HOME    .doil-health    data/health.db    0 yes; gitinit "$AGG/doil-health";    gitcommit "$AGG/doil-health"
mk_skill "$AGG/doil-portfolio" doil-portfolio DOILPORTFOLIO_HOME .doil-portfolio data/portfolio.db 1 yes; gitinit "$AGG/doil-portfolio"; gitcommit "$AGG/doil-portfolio"
gitinit "$T/real/DOIL/doytale"
mk_skill "$T/real/DOIL/doytale/skill" doytale DOYTALE_HOME .doytale drafts 0; gitcommit "$T/real/DOIL/doytale"

# 집계 repo: README + 사용자의 dirty doil-secretary 서브모듈 포인터(건드리면 안 됨)
gitinit "$AGG"; echo "# skills" > "$AGG/README.md"
mkdir -p "$AGG/doil-secretary"; gitinit "$AGG/doil-secretary"; echo a > "$AGG/doil-secretary/a"; gitcommit "$AGG/doil-secretary" a
git -C "$AGG" add README.md doil-secretary 2>/dev/null
git -C "$AGG" commit -q -m base
echo b > "$AGG/doil-secretary/b"; gitcommit "$AGG/doil-secretary" b; echo junk > "$AGG/doil-secretary/untracked-junk"   # 포인터 어긋남 + untracked = dirty
SEC_INDEX_BEFORE="$(git -C "$AGG" ls-files -s doil-secretary)"
SEC_STATUS_BEFORE="$(git -C "$AGG" status --porcelain -- doil-secretary)"

# 가짜 claude (mcp add/remove/list/get — 실제 CLI 와 같은 JSON 모양을 .claude.json 에 쓴다)
cat > "$T/bin/claude" <<'SH'
#!/usr/bin/env bash
echo "claude $* [CFG=${CLAUDE_CONFIG_DIR:-}]" >> "$RNS_TEST_LOG"
exec python3 - "$@" <<'PY'
import json, os, sys
a = sys.argv[1:]
cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~")
f = os.path.join(cfg, ".claude.json")
d = json.load(open(f)) if os.path.exists(f) else {}
if a[:2] == ["mcp", "add"]:
    i = a.index("--"); name = a[a.index("-s") + 2] if "-s" in a else a[2]
    cmd = a[i + 1:]
    if name in d.setdefault("mcpServers", {}):
        print("MCP server %s already exists in user config" % name, file=sys.stderr); sys.exit(1)
    d["mcpServers"][name] = {"type": "stdio", "command": cmd[0], "args": cmd[1:], "env": {}}
    json.dump(d, open(f, "w"), indent=2); print("Added stdio MCP server %s" % name)
elif a[:2] == ["mcp", "remove"]:
    name = a[-1]
    if name not in d.get("mcpServers", {}):
        print("No MCP server found with name: %s" % name, file=sys.stderr); sys.exit(1)
    del d["mcpServers"][name]; json.dump(d, open(f, "w"), indent=2); print("Removed MCP server %s" % name)
elif a[:2] == ["mcp", "list"]:
    print("Checking MCP server health...")
    for n, s in d.get("mcpServers", {}).items():
        ok = all(os.path.exists(x) for x in s.get("args", []) if x.endswith(".js"))
        print("%s: %s %s - %s" % (n, s["command"], " ".join(s.get("args", [])), "✓ Connected" if ok else "✗ Failed to connect"))
else:
    sys.exit(2)
PY
SH
# 가짜 gh (auth status / repo view / repo create) — 원격은 $FAKE_GH_REMOTES 아래 bare repo
cat > "$T/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$RNS_TEST_LOG"
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view")
    if [ -d "$FAKE_GH_REMOTES/$3.git" ]; then cat "$FAKE_GH_REMOTES/$3.git/visibility" 2>/dev/null || echo PRIVATE; exit 0; fi
    echo "GraphQL: Could not resolve to a Repository with the name '$3'. (repository)" >&2; exit 1 ;;
  "repo create")
    repo="$3"; shift 3; src=""; push=0; vis=PUBLIC
    while [ $# -gt 0 ]; do case "$1" in --source) src="$2"; shift ;; --push) push=1 ;; --private) vis=PRIVATE ;; esac; shift; done
    [ -d "$FAKE_GH_REMOTES/$repo.git" ] && { echo "already exists" >&2; exit 1; }
    mkdir -p "$FAKE_GH_REMOTES/$repo.git" && git init -q --bare "$FAKE_GH_REMOTES/$repo.git" && echo "$vis" > "$FAKE_GH_REMOTES/$repo.git/visibility"
    if [ -n "$src" ]; then git -C "$src" remote add origin "$FAKE_GH_REMOTES/$repo.git"; [ "$push" = 1 ] && git -C "$src" push -q -u origin main; fi
    exit 0 ;;
esac
exit 2
SH
chmod +x "$T/bin/claude" "$T/bin/gh"

# HOME: 프로필 + mcp-shared.json
mkprofile() { # <이름> <mcpServers JSON> [settings 0/1]
  mkdir -p "$HOME/$1/skills"
  python3 - "$HOME/$1/.claude.json" "$2" <<'PY'
import json, sys
json.dump({"numStartups": 7, "oauthAccount": {"emailAddress": "x@y"}, "projects": {"/p": {"allowedTools": ["a"]}}, "mcpServers": json.loads(sys.argv[2])}, open(sys.argv[1], "w"), indent=2)
PY
  [ "${3:-1}" = 1 ] && echo '{}' > "$HOME/$1/settings.json"
  ln -s "$REG/skills/sun-sang" "$HOME/$1/skills/sun-sang"
}
SS='{"sun-sang":{"type":"stdio","command":"node","args":["/x/sun-sang.js"],"env":{}},"colab":{"command":"uvx","args":["c"]}}'
mkprofile .claude "$SS"; mkprofile .claude-wellconn '{"ai-echo":{"type":"stdio","command":"node","args":["/x/ai.js"],"env":{}}}'
mkprofile .claude-anon "$SS"; mkprofile .claude-doil-console '{"other":{"command":"x","args":[]}}' 0
mkdir -p "$HOME/.claude-acctA/skills"
cat > "$HOME/.config/void-launcher/mcp-shared.json" <<'EOF'
{
  "_comment": "공통 MCP 정의. 한글 주석도 보존돼야 한다.",
  "_excludeProfiles": [".claude-anon", ".claude-persist-VOID"],
  "mcpServers": {
    "colab-mcp": {
      "command": "uvx",
      "args": ["git+https://github.com/googlecolab/colab-mcp"],
      "timeout": 30000,
      "env": {
        "BROWSER": "/x/open %s"
      }
    }
  }
}
EOF
chmod 664 "$HOME/.config/void-launcher/mcp-shared.json"
mkdir -p "$T/orig"; cp -a "$HOME" "$T/orig/home"
SHARED="$HOME/.config/void-launcher/mcp-shared.json"

RNS() { bash "$TARGET" "$@" >"$T/out" 2>&1; RC=$?; [ -n "${RNS_DEBUG:-}" ] && { echo "--- RNS $* → rc=$RC"; grep -E "\[FAIL\]|\[WARN\]|ERROR" "$T/out"; }; return 0; }
snap_home() { ( cd "$HOME" && { find . -type f -exec sha256sum {} +; find . -type l -printf 'L %p -> %l\n'; find . -type d -printf 'D %p %m\n'; } | sort | sha256sum | cut -d' ' -f1 ); }
snap_repos() { for d in "$AGG" "$AGG/doil-health" "$AGG/doil-portfolio" "$T/real/DOIL/doytale"; do echo "$d $(git -C "$d" rev-parse HEAD) $(git -C "$d" status --porcelain | sha256sum)"; done | sha256sum | cut -d' ' -f1; }
calls() { grep -c -- "$1" "$RNS_TEST_LOG" || true; }
entry() { echo "$REG/$1/mcp-server/src/index.js"; }

# ================================================================ 시험
echo "== T0 전제"
t_true "스크립트 문법" bash -n "$TARGET"
t_true "스크립트에 doil-secretary 를 add 하는 명령이 없다" bash -c "! grep -nE 'submodule add[^#]*doil-secretary|git add[^#]*doil-secretary' '$TARGET'"

echo "== T1 dry-run (기본) — 아무것도 쓰지 않는다"
H0="$(snap_home)"; R0="$(snap_repos)"; C0="$(wc -l < "$RNS_TEST_LOG")"
RNS
t_eq "dry-run 종료 0" 0 "$RC"
t_has "DRY-RUN 표시" "[DRY-RUN"
t_has "할 일 18건(설치 3 + .claude.json 6 + 링크 6 + void 3)" "해야 할 일 18"
t_nohas "범위 밖 프로필(anon) 미포함" "claude-anon/"
t_nohas "범위 밖 프로필(console) 미포함" "claude-doil-console/"
t_eq "HOME 전체 불변(dry-run)" "$H0" "$(snap_home)"
t_eq "repo 전체 불변(dry-run)" "$R0" "$(snap_repos)"
t_eq "dry-run 은 claude/gh/install 을 쓰기 모드로 호출하지 않는다" "$C0" "$(wc -l < "$RNS_TEST_LOG")"
t_false "데이터 홈이 만들어지지 않았다" test -e "$HOME/.doil-health"
t_false "프로브가 HOME 을 건드리지 않았다(.probe-touched)" test -e "$HOME/.probe-touched"
RNS --rollback
t_eq "롤백 dry-run 종료 0" 0 "$RC"; t_has "롤백: 이미 등록 없음 → 할 일 0" "해야 할 일 0"
t_eq "HOME 불변(롤백 dry-run)" "$H0" "$(snap_home)"
RNS --with-github
t_eq "--with-github dry-run 종료 0" 0 "$RC"; t_has "b 단계 TODO(repo 생성)" "gh repo create D0iloppa/doil-health --private"
t_has "c 단계 TODO(서브모듈, b 이후)" "submodule add -b main $T/remotes/D0iloppa/doil-health.git doil-health"
t_nohas "doytale 는 GitHub 대상이 아니다" "gh repo create D0iloppa/doytale"
t_eq "repo 불변(--with-github dry-run)" "$R0" "$(snap_repos)"
t_eq "gh 는 읽기 호출만(create 0)" 0 "$(calls 'gh repo create')"

echo "== T2 --apply"
RNS --apply
t_eq "apply 종료 0" 0 "$RC"
t_has "요약: 실패 0" "실패 0"
t_eq "install.sh 3회" 3 "$(calls '^install ')"
t_false "install.sh 의 CLAUDE_CONFIG_DIR 은 실제 프로필이 아니라 임시 폴더" grep -E "^install .*cfg=$HOME" "$RNS_TEST_LOG"
for P in .claude .claude-wellconn; do
  F="$HOME/$P/.claude.json"
  for S in doil-health:skills/doil-health doil-portfolio:skills/doil-portfolio doytale:doytale/skill; do
    n="${S%%:*}"; r="${S#*:}"
    t_eq "$P: $n 항목이 기존 형태와 같다" "{'type': 'stdio', 'command': 'node', 'args': ['$REG/$r/mcp-server/src/index.js'], 'env': {}}" "$(pj "$F" "d['mcpServers']['$n']")"
    t_eq "$P: $n 링크 → /DEVELOP 형태 경로" "$REG/$r" "$(readlink "$HOME/$P/skills/$n")"
  done
  t_eq "$P: 기존 서버·다른 키 보존" "$(python3 -c "
import json;o=json.load(open('$T/orig/home/$P/.claude.json'));n=json.load(open('$F'))
for k in ('doil-health','doil-portfolio','doytale'): n['mcpServers'].pop(k,None)
print(o==n)")" "True"
  t_eq "$P: 백업 1개(파일당 1회)" 1 "$(ls "$HOME/$P"/.claude.json.bak-regnewskills-* 2>/dev/null | wc -l)"
  t_true "$P: 백업 = 원본" cmp "$T/orig/home/$P/.claude.json" "$(ls "$HOME/$P"/.claude.json.bak-regnewskills-* | head -n1)"
  t_eq "$P: 백업 권한 유지" "$(stat -c %a "$T/orig/home/$P/.claude.json")" "$(stat -c %a "$(ls "$HOME/$P"/.claude.json.bak-regnewskills-* | head -n1)")"
  t_eq "$P: 기존 스킬 링크 보존" "$REG/skills/sun-sang" "$(readlink "$HOME/$P/skills/sun-sang")"
done
for P in .claude-anon .claude-doil-console; do
  t_true "$P: 범위 밖 — .claude.json 불변" cmp "$T/orig/home/$P/.claude.json" "$HOME/$P/.claude.json"
  t_eq "$P: 범위 밖 — 링크 없음" 1 "$(ls "$HOME/$P/skills" 2>/dev/null | wc -l)"
done
t_false ".claude-acctA(.claude.json 없음)에 링크 없음" test -e "$HOME/.claude-acctA/skills/doil-health"
t_eq "mcp-shared.json: 3개 추가" "['colab-mcp', 'doil-health', 'doil-portfolio', 'doytale']" "$(pj "$SHARED" "list(d['mcpServers'])")"
t_eq "mcp-shared.json: _comment·_excludeProfiles 보존" "True" "$(python3 -c "
import json;o=json.load(open('$T/orig/home/.config/void-launcher/mcp-shared.json'));n=json.load(open('$SHARED'))
print(all(o[k]==n[k] for k in ('_comment','_excludeProfiles')) and o['mcpServers']['colab-mcp']==n['mcpServers']['colab-mcp'])")"
t_eq "mcp-shared.json: 항목 형태" "{'type': 'stdio', 'command': 'node', 'args': ['$(entry skills/doil-health)'], 'env': {}}" "$(pj "$SHARED" "d['mcpServers']['doil-health']")"
t_true "mcp-shared.json: 백업 = 원본" cmp "$T/orig/home/.config/void-launcher/mcp-shared.json" "$(ls "$SHARED".bak-regnewskills-* | head -n1)"
t_eq "mcp-shared.json: 권한 유지" "664" "$(stat -c %a "$SHARED")"
t_eq "데이터 홈 3곳 700" "700 700 700" "$(stat -c %a "$HOME/.doil-health" "$HOME/.doil-portfolio" "$HOME/.doytale" | tr '\n' ' ' | sed 's/ $//')"
t_eq "claude mcp list: 프로필 2개만" 2 "$(calls 'claude mcp list')"
t_eq "claude mcp add 6회" 6 "$(calls 'claude mcp add')"
t_has "검증: Connected" "claude mcp list → Connected"
t_has "검증: 임시 홈 stdio tools/list" "tools=2"
t_false "프로브가 HOME 을 건드리지 않았다(.probe-touched)" test -e "$HOME/.probe-touched"
t_eq "doil-secretary 인덱스 포인터 불변" "$SEC_INDEX_BEFORE" "$(git -C "$AGG" ls-files -s doil-secretary)"
t_eq "doil-secretary dirty 상태 불변" "$SEC_STATUS_BEFORE" "$(git -C "$AGG" status --porcelain -- doil-secretary)"

echo "== T3 멱등 — 두 번째 --apply 는 아무것도 바꾸지 않는다"
H1="$(snap_home)"; I1="$(calls '^install ')"; A1="$(calls 'claude mcp add')"
RNS --apply
t_eq "2회차 종료 0" 0 "$RC"; t_has "수행 0" "수행 0"
t_eq "HOME 불변(백업 파일 포함)" "$H1" "$(snap_home)"
t_eq "install.sh 재실행 없음" "$I1" "$(calls '^install ')"
t_eq "claude mcp add 재실행 없음" "$A1" "$(calls 'claude mcp add')"
RNS
t_has "dry-run: 할 일 없음" "할 일 없음"

echo "== T4 충돌 — 다른 내용·실제 폴더는 덮어쓰지 않는다"
mkprofile .claude-conf '{"sun-sang":{"command":"node","args":["/x"]},"doil-health":{"type":"stdio","command":"node","args":["/elsewhere/index.js"],"env":{}}}'
rm -f "$HOME/.claude-conf/skills/sun-sang"
mkdir -p "$HOME/.claude-conf/skills/doil-portfolio/keep"; ln -s /elsewhere "$HOME/.claude-conf/skills/doytale"
cp "$HOME/.claude-conf/.claude.json" "$T/conf.before"
RNS --apply --profiles .claude-conf --only claude,links,verify
t_eq "충돌 → 종료 3(검증 불일치)" 3 "$RC"
t_has "충돌 안내" "충돌"
t_eq "다른 내용의 기존 항목 유지" "/elsewhere/index.js" "$(pj "$HOME/.claude-conf/.claude.json" "d['mcpServers']['doil-health']['args'][0]")"
t_true "실제 폴더 보존" test -d "$HOME/.claude-conf/skills/doil-portfolio/keep"
t_eq "다른 링크 유지" "/elsewhere" "$(readlink "$HOME/.claude-conf/skills/doytale")"
t_eq "충돌 없는 항목(doil-portfolio, doytale)은 등록됨" "True True" "$(python3 -c "
import json;m=json.load(open('$HOME/.claude-conf/.claude.json'))['mcpServers'];print('doil-portfolio' in m, 'doytale' in m)")"
RNS --apply --force --profiles .claude-conf --only claude,links,verify
t_eq "--force 후에도 실제 폴더는 못 덮어써 종료 3" 3 "$RC"
t_eq "--force: 다른 항목 교체" "$(entry skills/doil-health)" "$(pj "$HOME/.claude-conf/.claude.json" "d['mcpServers']['doil-health']['args'][0]")"
t_eq "--force: 다른 링크 교체" "$REG/doytale/skill" "$(readlink "$HOME/.claude-conf/skills/doytale")"
t_true "--force 에도 실제 폴더 보존" test -d "$HOME/.claude-conf/skills/doil-portfolio/keep"
t_eq "--force: 다른 키 보존" "7" "$(pj "$HOME/.claude-conf/.claude.json" "d['numStartups']")"
rm -rf "$HOME/.claude-conf"

echo "== T5a 설치 부분 상태 — node_modules 정상·데이터 홈 없음이면 npm ci 대신 init-db 만"
mv "$HOME/.doil-health" "$T/home-health.moved"
I2="$(calls '^install ')"; D2="$(calls '^initdb ')"
RNS --only install
t_has "dry-run: init-db 만 할 일" "doil-health: node $REG/skills/doil-health/mcp-server/scripts/init-db.js"
t_nohas "dry-run: install.sh 전체는 아님" "doil-health: bash"
RNS --apply --only install
t_eq "init-db 경로 종료 0" 0 "$RC"
t_eq "install.sh 는 재실행되지 않음" "$I2" "$(calls '^install ')"
t_eq "init-db 1회" $((D2 + 1)) "$(calls '^initdb ')"
t_true "데이터 홈 복구" test -e "$HOME/.doil-health/data/health.db"
RNS --apply --only install --force
t_eq "--force 는 install.sh 전체 재실행(3개)" $((I2 + 3)) "$(calls '^install ')"

echo "== T5 설치 검증(dJinn 드리프트)"
P="$AGG/doil-portfolio/mcp-server/node_modules/.package-lock.json"; cp "$P" "$T/lock.bak"
echo '{"packages":{"node_modules/@d0iloppa/djinn":{"resolved":"git+ssh://x/OTHER.git#0000"}}}' > "$P"
RNS --only install
t_eq "드리프트 dry-run 종료 0" 0 "$RC"; t_has "DRIFT 이면 install 이 할 일" "doil-portfolio: bash $REG/skills/doil-portfolio/install.sh"
t_has "이유 표시" "dJinn 검증 실패"
cp "$T/lock.bak" "$P"
RNS --only install
t_has "복구 후 정상" "doil-portfolio: 설치 정상 (djinn 0.2.0 clearCache:function lock==installed)"

echo "== T6 GitHub·서브모듈"
echo SECRET > "$AGG/doil-portfolio/ledger.db"; git -C "$AGG/doil-portfolio" add -f ledger.db; git -C "$AGG/doil-portfolio" commit -q -m "oops db"
RNS --apply --only github
t_eq "개인 데이터 파일이 추적되면 push 거부 → 종료 3" 3 "$RC"
t_has "거부 사유" "개인 데이터로 보이는 파일이 추적 중"
t_false "그 repo 는 만들어지지 않았다" test -d "$T/remotes/D0iloppa/doil-portfolio.git"
t_true "다른 repo(doil-health)는 만들어졌다" test -d "$T/remotes/D0iloppa/doil-health.git"
git -C "$AGG/doil-portfolio" reset -q --hard HEAD~1
RNS --apply --only github,submodule
t_eq "github+submodule apply 종료 0" 0 "$RC"
for n in doil-health doil-portfolio; do
  t_eq "$n: origin" "$T/remotes/D0iloppa/$n.git" "$(git -C "$AGG/$n" remote get-url origin)"
  t_eq "$n: push 됨(원격 main == HEAD)" "$(git -C "$AGG/$n" rev-parse HEAD)" "$(git --git-dir="$T/remotes/D0iloppa/$n.git" rev-parse refs/heads/main)"
  t_eq "$n: private" PRIVATE "$(cat "$T/remotes/D0iloppa/$n.git/visibility")"
  t_eq "$n: 서브모듈 gitlink(160000)" 160000 "$(git -C "$AGG" ls-files -s "$n" | awk '{print $1}')"
done
t_eq "repo create 는 repo 당 1회(재시도 포함 총 2회)" 2 "$(calls 'gh repo create')"
t_false "doytale 는 repo 를 만들지 않는다" test -d "$T/remotes/D0iloppa/doytale.git"
t_eq ".gitmodules 항목 2개" "doil-health doil-portfolio" "$(git -C "$AGG" config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}' | tr '\n' ' ' | sed 's/ $//')"
t_eq "서브모듈 커밋 2개" "2" "$(git -C "$AGG" log --format=%s | grep -c '^add doil-.* submodule$')"
for n in doil-health doil-portfolio; do
  t_eq "$n 커밋은 .gitmodules 와 그 경로만 담는다" ".gitmodules $n" "$(git -C "$AGG" show --name-only --format= "$(git -C "$AGG" log --format=%H --grep="^add $n submodule$")" | sort | tr '\n' ' ' | sed 's/ $//')"
done
t_eq "doil-secretary 를 건드린 커밋은 기반 커밋 1개뿐" 1 "$(git -C "$AGG" log --format=%H -- doil-secretary | wc -l)"
t_eq "doil-secretary 인덱스 포인터 불변" "$SEC_INDEX_BEFORE" "$(git -C "$AGG" ls-files -s doil-secretary)"
t_eq "doil-secretary dirty 상태 불변" "$SEC_STATUS_BEFORE" "$(git -C "$AGG" status --porcelain -- doil-secretary)"
t_eq "인덱스에 남은 staged 변경 없음" "" "$(git -C "$AGG" diff --cached --name-only)"
t_eq "집계 repo 는 push 하지 않는다(원격 없음)" "" "$(git -C "$AGG" remote)"
RNS --apply --only github,submodule
t_eq "멱등: 2회차 종료 0" 0 "$RC"; t_has "멱등: 수행 0" "수행 0"; t_eq "멱등: repo create 추가 호출 없음" 2 "$(calls 'gh repo create')"
RNS --with-github
t_has "dry-run: 이미 서브모듈" "이미 서브모듈로 장착됨"; t_has "dry-run: 이미 repo 있음" "GitHub repo 이미 있음"
git -C "$AGG/doil-health" remote remove origin
RNS --apply --only github
t_eq "repo 는 있고 origin 만 없으면 origin 복구(새 repo 만들지 않음)" "$T/remotes/D0iloppa/doil-health.git" "$(git -C "$AGG/doil-health" remote get-url origin)"
t_eq "origin 복구는 repo create 를 호출하지 않는다" 2 "$(calls 'gh repo create')"
git -C "$AGG/doil-health" remote set-url origin /some/other.git
RNS --apply --only github
t_has "다른 origin 은 경고하고 그대로 둔다" "origin 이 다른 URL"
t_eq "다른 origin 유지" "/some/other.git" "$(git -C "$AGG/doil-health" remote get-url origin)"
git -C "$AGG/doil-health" remote set-url origin "$T/remotes/D0iloppa/doil-health.git"
echo PUBLIC > "$T/remotes/D0iloppa/doil-health.git/visibility"
RNS --only github
t_has "PUBLIC repo 경고" "PRIVATE 이 아니다"
echo PRIVATE > "$T/remotes/D0iloppa/doil-health.git/visibility"

echo "== T7 롤백"
H2="$(snap_home)"
RNS --rollback
t_eq "롤백 dry-run 종료 0" 0 "$RC"; t_has "롤백 할 일 15건(.claude.json 6 + 링크 6 + void 3)" "해야 할 일 15"
t_eq "롤백 dry-run: HOME 불변" "$H2" "$(snap_home)"
RNS --rollback --apply
t_eq "롤백 apply 종료 0" 0 "$RC"; t_has "롤백 검증: 실패 0" "실패 0"
for P in .claude .claude-wellconn; do
  t_eq "$P: .claude.json 이 등록 전과 같다" True "$(python3 -c "
import json;print(json.load(open('$T/orig/home/$P/.claude.json'))==json.load(open('$HOME/$P/.claude.json')))")"
  t_false "$P: 신규 링크 제거" test -L "$HOME/$P/skills/doil-health"
  t_eq "$P: 기존 sun-sang 링크는 남김" "$REG/skills/sun-sang" "$(readlink "$HOME/$P/skills/sun-sang")"
done
t_true "mcp-shared.json 이 원본과 바이트 동일" cmp "$T/orig/home/.config/void-launcher/mcp-shared.json" "$SHARED"
t_true "롤백은 데이터 홈을 지우지 않는다" test -d "$HOME/.doil-portfolio/data"
t_true "롤백은 node_modules 를 지우지 않는다" test -d "$AGG/doil-health/mcp-server/node_modules"
t_eq "롤백은 서브모듈을 지우지 않는다" 160000 "$(git -C "$AGG" ls-files -s doil-health | awk '{print $1}')"
H3="$(snap_home)"
RNS --rollback --apply
t_eq "롤백 멱등: 종료 0" 0 "$RC"; t_has "롤백 멱등: 수행 0" "수행 0"; t_eq "롤백 멱등: HOME 불변" "$H3" "$(snap_home)"
RNS --apply
t_eq "롤백 후 재등록 종료 0" 0 "$RC"; t_has "재등록 후 실패 0" "실패 0"

echo "== T8 사용법·환경 오류"
for args in "--only bogus" "--rollback --only install" "--rollback --with-github" "--bogus" "--dry-run --apply" "--skills nope" "--only" "--profiles /nonexistent"; do
  # shellcheck disable=SC2086
  RNS $args; t_eq "종료 1: $args" 1 "$RC"
done
H4="$(snap_home)"
RNS --apply --only links; RC0=$RC; ok_apply=$RC
RNS_REGISTER_ROOT="$T/no-such-root" RNS --apply
t_eq "등록 경로 접두가 어긋나면 --apply 는 종료 1" 1 "$RC"
RNS_REGISTER_ROOT="$T/no-such-root" RNS
t_eq "같은 상황 dry-run 은 종료 0 + PEND" 0 "$RC"; t_has "PEND 안내" "같은 곳을 가리키지 않는다"
t_eq "오류 경로는 아무것도 바꾸지 않는다" "$H4" "$(snap_home)"
NOCLAUDE="$(dirname "$(command -v node)"):/usr/bin:/bin"
PATH="$NOCLAUDE" RNS --apply --only claude
t_eq "claude CLI 없으면 --apply 종료 1" 1 "$RC"
PATH="$NOCLAUDE" RNS --only claude
t_eq "claude CLI 없어도 dry-run 종료 0" 0 "$RC"; t_has "claude 없음 PEND" "claude CLI 가 PATH 에 없다"
mv "$SHARED" "$SHARED.gone"; RNS --only void; t_eq "mcp-shared.json 없으면 dry-run 종료 0" 0 "$RC"; t_has "없음 PEND" "mcp-shared.json 이 없다"; mv "$SHARED.gone" "$SHARED"

echo "== T9 실제 환경 무접촉"
t_eq "실제 환경에 흔적 없음(신규 항목·백업·링크·mcp-shared·~/.doil-health 불변)" "$REAL_BEFORE" "$(real_sum)"

echo ""
echo "RESULT: PASS $PASS, FAIL $FAILN"
[ "$FAILN" -eq 0 ]
