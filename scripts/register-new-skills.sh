#!/usr/bin/env bash
# register-new-skills.sh — 신규 스킬(doil-health, doil-portfolio, doytale)을 사용자 환경에 등록한다.
# 근거: skills/docs/new-skill-checklist.md (등록 5곳 중 4·5번 + 설치·repo·검증). 기본은 DRY-RUN(아무것도 쓰지 않는다).
#
# 단계(알파벳이 --only 약칭)
#   a install    각 스킬 install.sh 실행(npm ci, DB 초기화, 데이터 홈 0700). 이미 정상이면 건너뜀. node_modules 는 정상인데 데이터 홈만
#                없으면 npm ci 없이 init-db 만 한다(정상 설치를 네트워크 재설치로 날리지 않음). 스킬 링크는 e 단계가 건다.
#   b github     GitHub private repo 생성 + push(gh). 이미 있으면 건너뜀. doil-health·doil-portfolio만(doytale는 Doytale repo 안).
#   c submodule  집계 repo(skills)에 서브모듈로 장착 + 커밋(.gitmodules·그 경로만). doil-secretary 포인터는 건드리지 않는다. push 안 함.
#   d claude     Claude 프로필 .claude.json 에 MCP 등록(claude mcp add -s user). 고치기 전에 .claude.json 백업.
#   e links      프로필 skills/<이름> 심링크(/DEVELOP/... 경로, 기존 스킬 링크와 같은 형태).
#   f void       ~/.config/void-launcher/mcp-shared.json 에 항목 추가(백업) + `void mcp sync` 안내.
#   g verify     등록 검증(JSON·링크·mcp-shared·임시 홈 stdio tools/list, --apply 일 때는 claude mcp list 의 Connected 까지).
#   기본 단계: a d e f g   (--with-github 를 주면 b c 도 포함)
#
# 사용법(전부 한 줄)
#   register-new-skills.sh                       # = --dry-run: 할 일 목록만 출력, 아무것도 쓰지 않음(종료 0)
#   register-new-skills.sh --apply               # 실제 적용(멱등: 다시 실행해도 이미 된 것은 건너뜀)
#   register-new-skills.sh --apply --with-github # GitHub repo 생성·push + 서브모듈 장착까지
#   register-new-skills.sh --only claude,links   # 지정 단계만(이름 또는 a~g, 쉼표 구분). 실행 순서는 항상 a→g
#   register-new-skills.sh --rollback            # 등록 제거 계획(d e f 만: .claude.json 항목·심링크·mcp-shared 항목). --apply 와 함께 실제 제거
#
# 옵션: --profiles a,b   대상 프로필(~/ 아래 이름 또는 절대경로). 기본: 기존 스킬(sun-sang/ai-echo)이 등록된 프로필 중
#                        mcp-shared.json 의 _excludeProfiles 를 뺀 것. 롤백은 항목이 있는 모든 ~/.claude* 프로필.
#       --skills x,y     대상 스킬(doil-health,doil-portfolio,doytale 중). 기본 전부.
#       --force          이미 있는 다른 내용(충돌)을 교체한다. 기본은 그대로 두고 경고.
# 종료 코드: 0 성공(dry-run 은 항상 0) / 1 사용법·환경 오류 / 3 --apply 중 실패 또는 검증 불일치
#
# 이 스크립트가 하지 않는 것: DOBIS mcp.json·console 설정(통합 배포 스크립트 몫), 데이터 삭제, 롤백 때의 repo·서브모듈·node_modules 제거.
# 시험용 환경변수: RNS_SKILLS_DIR(집계 repo), RNS_DOIL_ROOT, RNS_REGISTER_ROOT(기본 /DEVELOP/DOIL), RNS_GH_OWNER(D0iloppa),
#                  RNS_GH_URL_BASE(https://github.com), RNS_VOID_SHARED(~/.config/void-launcher/mcp-shared.json)
set -uo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SKILLS_DIR="${RNS_SKILLS_DIR:-$(cd "$(dirname "$SELF")/.." && pwd)}"       # 집계 repo 실제 경로
DOIL_ROOT="${RNS_DOIL_ROOT:-$(dirname "$SKILLS_DIR")}"                      # 스킬 폴더들의 실제 부모
REG_ROOT="${RNS_REGISTER_ROOT:-/DEVELOP/DOIL}"                              # 등록에 박는 경로 접두(기존 스킬과 같은 규칙)
GH_OWNER="${RNS_GH_OWNER:-D0iloppa}"
GH_URL_BASE="${RNS_GH_URL_BASE:-https://github.com}"
VOID_SHARED="${RNS_VOID_SHARED:-$HOME/.config/void-launcher/mcp-shared.json}"
NEVER_ADD="doil-secretary"                                                  # 사용자 것(dirty 포인터). 어떤 단계도 건드리지 않는다.
BAK_TAG="bak-regnewskills"

# name|DOIL_ROOT 기준 상대 경로|데이터 홈 환경변수|기본 데이터 홈(HOME 기준)|준비 표지(홈 기준)|GitHub 대상(1/0)
SKILL_TABLE=(
  "doil-health|skills/doil-health|DOILHEALTH_HOME|.doil-health|data/health.db|1"
  "doil-portfolio|skills/doil-portfolio|DOILPORTFOLIO_HOME|.doil-portfolio|data/portfolio.db|1"
  "doytale|doytale/skill|DOYTALE_HOME|.doytale|drafts|0"
)
# 체크리스트 1-3: 설치본 dJinn 이 핀(0.2.0 + clearCache)과 락파일대로인지
DJINN_CHECK_JS='
const p = require("@d0iloppa/djinn/package.json"); const { DJinn } = require("@d0iloppa/djinn");
const l = require("./package-lock.json").packages["node_modules/@d0iloppa/djinn"];
const m = require("./node_modules/.package-lock.json").packages["node_modules/@d0iloppa/djinn"];
const same = l.resolved === m.resolved, cc = typeof DJinn.prototype.clearCache;
console.log("djinn " + p.version + " clearCache:" + cc + " " + (same ? "lock==installed" : "DRIFT"));
process.exit(same && cc === "function" ? 0 : 1);'
# 임시 홈에서 MCP 서버를 띄워 initialize + tools/list (운영 데이터 홈 미접촉, LLM 호출 없음)
PROBE_JS='
const { spawn } = require("child_process");
const [entry, envName, home] = process.argv.slice(1);
const c = spawn(process.execPath, [entry], { env: { PATH: process.env.PATH, HOME: home, [envName]: home }, cwd: home, stdio: ["pipe", "pipe", "ignore"] });
let buf = ""; const waiting = {};
c.stdout.on("data", (d) => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); if (!l.trim()) continue; let m; try { m = JSON.parse(l); } catch { continue; } if (m.id && waiting[m.id]) waiting[m.id](m); } });
c.on("error", (e) => { console.log("FAIL " + e.message); process.exit(1); });
const rpc = (id, method, params) => new Promise((r) => { waiting[id] = r; c.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n"); });
const t = setTimeout(() => { console.log("FAIL 20초 안에 응답 없음"); c.kill("SIGKILL"); process.exit(1); }, 20000);
(async () => {
  const i = await rpc(1, "initialize", { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "rns-probe", version: "0" } });
  c.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  const r = await rpc(2, "tools/list", {}); clearTimeout(t); c.kill("SIGTERM");
  console.log("OK server=" + ((i.result && i.result.serverInfo && i.result.serverInfo.name) || "?") + " tools=" + r.result.tools.length); process.exit(0);
})().catch((e) => { console.log("FAIL " + e.message); process.exit(1); });'

# JSON 보조(python3): .claude.json·mcp-shared.json 의 mcpServers 항목 상태 판정과 mcp-shared.json 편집(서식 보존)
read -r -d '' PYLIB <<'PY' || true
import json, os, shutil, sys

def load(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)

def same(s, entry):
    if not isinstance(s, dict) or set(s) - {"type", "command", "args", "env"}:
        return False
    if s.get("type", "stdio") != "stdio" or s.get("command") != "node" or (s.get("env") or {}) != {}:
        return False
    a = s.get("args")
    if not isinstance(a, list) or len(a) != 1 or not isinstance(a[0], str):
        return False
    return a[0] == entry or os.path.realpath(a[0]) == os.path.realpath(entry)

def enc(v, ind=0):  # 기존 mcp-shared.json 서식: 2칸 들여쓰기, 스칼라 배열은 한 줄
    if isinstance(v, dict):
        if not v:
            return "{}"
        items = [" " * (ind + 2) + json.dumps(k, ensure_ascii=False) + ": " + enc(x, ind + 2) for k, x in v.items()]
        return "{\n" + ",\n".join(items) + "\n" + " " * ind + "}"
    if isinstance(v, list):
        if all(not isinstance(x, (dict, list)) for x in v):
            return "[" + ", ".join(json.dumps(x, ensure_ascii=False) for x in v) + "]"
        return "[\n" + ",\n".join(" " * (ind + 2) + enc(x, ind + 2) for x in v) + "\n" + " " * ind + "]"
    return json.dumps(v, ensure_ascii=False)

def write(p, d):
    tmp = "%s.tmp-rns-%d" % (p, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(enc(d) + "\n")
    shutil.copymode(p, tmp)
    os.replace(tmp, p)

cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "state":                       # FILE NAME ENTRY -> nofile|badjson|absent|same|differs
    p, name, entry = args
    if not os.path.exists(p):
        print("nofile"); sys.exit(0)
    try:
        d = load(p)
    except Exception:
        print("badjson"); sys.exit(0)
    s = (d.get("mcpServers") or {}).get(name) if isinstance(d, dict) else None
    print("absent" if s is None else ("same" if same(s, entry) else "differs"))
elif cmd == "has-any":                   # FILE NAME... -> yes|no
    p, names = args[0], args[1:]
    try:
        m = load(p).get("mcpServers") or {}
    except Exception:
        m = {}
    print("yes" if any(n in m for n in names) else "no")
elif cmd == "excludes":                  # FILE -> _excludeProfiles 한 줄씩
    try:
        for x in load(args[0]).get("_excludeProfiles") or []:
            print(x)
    except Exception:
        pass
elif cmd == "fmt":                       # FILE -> identical|differs (재직렬화가 원문과 같은가)
    with open(args[0], encoding="utf-8") as f:
        s = f.read()
    print("identical" if enc(json.loads(s)) + "\n" == s else "differs")
elif cmd == "set":                       # FILE NAME ENTRY
    p, name, entry = args
    d = load(p)
    d.setdefault("mcpServers", {})[name] = {"type": "stdio", "command": "node", "args": [entry], "env": {}}
    write(p, d)
elif cmd == "del":                       # FILE NAME
    p, name = args
    d = load(p)
    (d.get("mcpServers") or {}).pop(name, None)
    write(p, d)
else:
    sys.exit(2)
PY
pyj() { python3 -c "$PYLIB" "$@"; }

# ---------------------------------------------------------------- 출력·집계
N_OK=0; N_TODO=0; N_DONE=0; N_FAIL=0; N_WARN=0; N_CONFLICT=0
TODOS=(); PENDING=(); BACKUPS=(); WARNINGS=()
CUR_STEP=""
log()  { printf '%s\n' "$*"; }
ok()   { N_OK=$((N_OK + 1)); log "  [ OK ] $*"; }
info() { log "  [INFO] $*"; }
warn() { N_WARN=$((N_WARN + 1)); WARNINGS+=("[$CUR_STEP] $*"); log "  [WARN] $*"; }
fail() { N_FAIL=$((N_FAIL + 1)); log "  [FAIL] $*"; }
pend() { PENDING+=("[$CUR_STEP] $*"); log "  [PEND] $*"; }
die()  { local code="$1"; shift; printf 'ERROR: %s\n' "$*" >&2; exit "$code"; }
head_() { CUR_STEP="$1"; shift; log ""; log "== [$CUR_STEP] $*"; }

# act <설명> <명령...>: dry-run 이면 할 일로 기록, --apply 면 실행한다.
act() {
  local desc="$1"; shift
  if [ "$APPLY" -eq 1 ]; then
    log "  [RUN ] $desc"
    if "$@"; then N_DONE=$((N_DONE + 1)); return 0; fi
    fail "$desc"; return 1
  fi
  N_TODO=$((N_TODO + 1)); TODOS+=("[$CUR_STEP] $desc"); log "  [TODO] $desc"
  local tag="${desc%%: *}"   # "프로필/스킬" 또는 "스킬" — 요약용 그룹 키
  TODO_N[$CUR_STEP]=$(( ${TODO_N[$CUR_STEP]:-0} + 1 ))
  case "$tag" in
    */*) TODO_WHAT[$CUR_STEP]="${TODO_WHAT[$CUR_STEP]:-}${TODO_WHAT[$CUR_STEP]:+ }${tag##*/}"; TODO_WHERE[$CUR_STEP]="${TODO_WHERE[$CUR_STEP]:-}${TODO_WHERE[$CUR_STEP]:+ }${tag%%/*}" ;;
    *)   TODO_WHAT[$CUR_STEP]="${TODO_WHAT[$CUR_STEP]:-}${TODO_WHAT[$CUR_STEP]:+ }$tag" ;;
  esac
}
uniq_words() { printf '%s\n' $1 | awk '!s[$0]++' | paste -sd, - | sed 's/,/, /g'; }

# 검증 불일치: --apply 면 실패, dry-run 이면 "적용 전 상태" 정보
vmiss() { if [ "$APPLY" -eq 1 ]; then fail "$*"; else info "미충족(적용 전): $*"; fi; }

declare -A TODO_N=() TODO_WHAT=() TODO_WHERE=() BACKED=()
TS="$(date +%Y%m%d-%H%M%S)"
backup_file() { # 같은 실행에서 파일당 한 번. 이미 있는 백업 이름은 덮어쓰지 않는다.
  local f="$1" b n=0
  [ -n "${BACKED[$f]:-}" ] && return 0
  [ -e "$f" ] || return 0
  b="$f.$BAK_TAG-$TS"
  while [ -e "$b" ]; do n=$((n + 1)); b="$f.$BAK_TAG-$TS-$n"; done
  ( umask 077; cp -p -- "$f" "$b" ) || { log "    backup 실패: $f"; return 1; }
  BACKED[$f]="$b"; BACKUPS+=("$b"); log "    backup: $b"
}

# ---------------------------------------------------------------- 인자
APPLY=0; MODE_GIVEN=""; ROLLBACK=0; WITH_GH=0; FORCE=0; ONLY=""; PROFILES_OPT=""; SKILLS_OPT=""
usage() { sed -n '2,/^set -uo/p' "$SELF" | sed '$d' | sed 's/^# \{0,1\}//'; }
needval() { [ "$1" -ge 2 ] || die 1 "$2 에 값이 필요하다"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) [ "$MODE_GIVEN" = apply ] && die 1 "--dry-run 과 --apply 는 함께 쓸 수 없다"; MODE_GIVEN=dry; APPLY=0 ;;
    --apply)   [ "$MODE_GIVEN" = dry ] && die 1 "--dry-run 과 --apply 는 함께 쓸 수 없다"; MODE_GIVEN=apply; APPLY=1 ;;
    --rollback) ROLLBACK=1 ;;
    --with-github) WITH_GH=1 ;;
    --force) FORCE=1 ;;
    --only) needval $# --only; ONLY="$2"; shift ;;
    --profiles) needval $# --profiles; PROFILES_OPT="$2"; shift ;;
    --skills) needval $# --skills; SKILLS_OPT="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die 1 "알 수 없는 인자: $1" ;;
  esac
  shift
done

norm_step() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    a|install) echo install ;; b|github) echo github ;; c|submodule) echo submodule ;;
    d|claude) echo claude ;;  e|links|link) echo links ;; f|void) echo void ;; g|verify) echo verify ;;
    *) return 1 ;;
  esac
}
STEP_ORDER=(install github submodule claude links void verify)
declare -A STEP_LETTER=([install]=a [github]=b [submodule]=c [claude]=d [links]=e [void]=f [verify]=g)
declare -A SEL=()
if [ -n "$ONLY" ]; then
  IFS=',' read -r -a _tok <<<"$ONLY"
  for t in "${_tok[@]}"; do
    s="$(norm_step "$t")" || die 1 "알 수 없는 단계: '$t' (a install, b github, c submodule, d claude, e links, f void, g verify)"
    SEL[$s]=1
  done
else
  if [ "$ROLLBACK" -eq 1 ]; then
    for s in claude links void verify; do SEL[$s]=1; done
  else
    for s in install claude links void verify; do SEL[$s]=1; done
    if [ "$WITH_GH" -eq 1 ]; then SEL[github]=1; SEL[submodule]=1; fi
  fi
fi
if [ "$ROLLBACK" -eq 1 ]; then
  [ "$WITH_GH" -eq 0 ] || die 1 "--rollback 은 GitHub·서브모듈을 되돌리지 않는다(--with-github 와 함께 쓸 수 없다)"
  for s in install github submodule; do
    [ -z "${SEL[$s]:-}" ] || die 1 "--rollback 은 d claude, e links, f void, g verify 만 지원한다('$s' 불가)"
  done
fi
sel() { [ -n "${SEL[$1]:-}" ]; }

# 대상 스킬
SKILLS=()
for row in "${SKILL_TABLE[@]}"; do
  n="${row%%|*}"
  if [ -n "$SKILLS_OPT" ]; then case ",$SKILLS_OPT," in *",$n,"*) ;; *) continue ;; esac; fi
  SKILLS+=("$row")
done
if [ -n "$SKILLS_OPT" ]; then
  IFS=',' read -r -a _sk <<<"$SKILLS_OPT"
  for t in "${_sk[@]}"; do
    found=0; for row in "${SKILL_TABLE[@]}"; do [ "${row%%|*}" = "$t" ] && found=1; done
    [ "$found" -eq 1 ] || die 1 "알 수 없는 스킬: $t (doil-health, doil-portfolio, doytale)"
  done
fi
[ "${#SKILLS[@]}" -gt 0 ] || die 1 "대상 스킬이 없다"

parse_row() { # 전역 S_* 설정
  IFS='|' read -r S_NAME S_REL S_ENV S_HOMEREL S_MARK S_GH <<<"$1"
  S_REAL="$DOIL_ROOT/$S_REL"; S_REG="$REG_ROOT/$S_REL"
  S_ENTRY_REAL="$S_REAL/mcp-server/src/index.js"; S_ENTRY_REG="$S_REG/mcp-server/src/index.js"
  if [ -n "${!S_ENV:-}" ]; then S_HOME="${!S_ENV}"; else S_HOME="$HOME/$S_HOMEREL"; fi
  if [ "$(readlink -f "$S_REG" 2>/dev/null || echo X1)" = "$(readlink -f "$S_REAL" 2>/dev/null || echo X2)" ]; then S_RUN="$S_REG"; else S_RUN="$S_REAL"; fi
}

# ---------------------------------------------------------------- 환경 점검
command -v python3 >/dev/null 2>&1 || die 1 "필요한 도구가 없다: python3"
command -v node >/dev/null 2>&1 || die 1 "필요한 도구가 없다: node"
[ -d "$SKILLS_DIR" ] || die 1 "집계 repo 폴더가 없다: $SKILLS_DIR"
if [ "$(readlink -f "$REG_ROOT" 2>/dev/null || echo X1)" != "$(readlink -f "$DOIL_ROOT" 2>/dev/null || echo X2)" ]; then
  msg="등록 경로 접두($REG_ROOT)가 실제 스킬 위치($DOIL_ROOT)와 같은 곳을 가리키지 않는다 — /DEVELOP 심링크 확인"
  if [ "$APPLY" -eq 1 ]; then die 1 "$msg"; else PENDING+=("[환경] $msg"); fi
fi
HAVE_CLAUDE=0; command -v claude >/dev/null 2>&1 && HAVE_CLAUDE=1
HAVE_GH=0; command -v gh >/dev/null 2>&1 && HAVE_GH=1
if [ "$APPLY" -eq 1 ]; then
  if { sel claude || sel verify; } && [ "$HAVE_CLAUDE" -eq 0 ]; then die 1 "claude CLI 가 없다(d·g 단계)"; fi
  if { sel github || sel submodule; } && [ "$HAVE_GH" -eq 0 ] && sel github; then die 1 "gh CLI 가 없다(b 단계)"; fi
  if { sel github || sel submodule; }; then command -v git >/dev/null 2>&1 || die 1 "git 이 없다"; fi
  LOCK_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}"; mkdir -p "$LOCK_DIR"
  command -v flock >/dev/null 2>&1 && { exec 9>"$LOCK_DIR/register-new-skills.lock"; flock -n 9 || die 1 "다른 register-new-skills 가 실행 중이다"; }
fi

# ---------------------------------------------------------------- 프로필 범위
PROFILES=(); PROFILE_NOTE=""
discover_profiles() {
  local cfg name excl
  if [ -n "$PROFILES_OPT" ]; then
    local t; IFS=',' read -r -a _pp <<<"$PROFILES_OPT"
    for t in "${_pp[@]}"; do
      case "$t" in /*) cfg="$t" ;; *) cfg="$HOME/${t#"$HOME/"}" ;; esac
      [ -d "$cfg" ] || die 1 "프로필 디렉터리가 없다: $cfg"
      PROFILES+=("$cfg")
    done
    PROFILE_NOTE="--profiles 로 지정"
  elif [ "$ROLLBACK" -eq 1 ]; then
    for cfg in "$HOME"/.claude "$HOME"/.claude-*; do [ -d "$cfg" ] && PROFILES+=("$cfg"); done
    PROFILE_NOTE="롤백: ~/.claude* 전부(항목이 같은 것만 제거)"
  else
    excl=""; [ -f "$VOID_SHARED" ] && excl="$(pyj excludes "$VOID_SHARED")"
    for cfg in "$HOME"/.claude "$HOME"/.claude-*; do
      [ -d "$cfg" ] && [ -f "$cfg/.claude.json" ] || continue
      name="$(basename "$cfg")"
      if printf '%s\n' "$excl" | grep -qxF -- "$name"; then continue; fi
      [ "$(pyj has-any "$cfg/.claude.json" sun-sang ai-echo)" = yes ] || continue
      PROFILES+=("$cfg")
    done
    PROFILE_NOTE="기존 스킬(sun-sang/ai-echo)이 등록된 프로필 중 mcp-shared.json _excludeProfiles 제외"
  fi
}
needs_profiles() { sel claude || sel links || { sel verify; }; }
if needs_profiles; then discover_profiles; fi

# ---------------------------------------------------------------- 공통 판정
module_check() { # 설치가 정상이면 M_WHY="" , 아니면 이유. S_DJINN 에 dJinn 검증 한 줄(전역 — 서브셸로 부르지 말 것)
  local m="$S_REAL/mcp-server" out
  M_WHY=""; S_DJINN=""
  [ -f "$S_ENTRY_REAL" ] || { M_WHY="진입점 없음: $S_ENTRY_REAL"; return 0; }
  [ -d "$m/node_modules/@modelcontextprotocol/sdk" ] || { M_WHY="mcp-server/node_modules 없음"; return 0; }
  if grep -q '@d0iloppa/djinn' "$m/package.json" 2>/dev/null; then
    out="$(cd "$m" && node -e "$DJINN_CHECK_JS" 2>&1)" || { M_WHY="dJinn 검증 실패(npm ci 필요): $(printf '%s' "$out" | tail -n 1)"; return 0; }
    S_DJINN="$out"
  fi
  return 0
}
install_ready() { # 설치 정상 + 데이터 홈 준비 표지까지. 실패 이유는 S_WHY
  module_check
  [ -z "$M_WHY" ] || { S_WHY="$M_WHY"; return 1; }
  [ -e "$S_HOME/$S_MARK" ] || { S_WHY="데이터 홈 미초기화($S_HOME/$S_MARK 없음)"; return 1; }
  S_WHY=""; return 0
}
link_state() { # <링크 경로> → absent|same|other|conflict
  local l="$1"
  if [ -L "$l" ]; then
    if [ "$(readlink "$l")" = "$S_REG" ] || [ "$(readlink -f "$l")" = "$(readlink -f "$S_REAL")" ]; then echo same; else echo other; fi
  elif [ -e "$l" ]; then echo conflict
  else echo absent; fi
}
cj() { printf '%s/.claude.json' "$1"; }

# ================================================================ a install
run_install() {
  local tmpcfg rc
  tmpcfg="$(mktemp -d)" || return 1
  # install.sh 는 항상 $CLAUDE_CONFIG_DIR/skills 에 링크를 건다 → 임시 폴더로 흡수하고 링크는 e 단계가 일관되게 건다.
  ( cd "$S_REAL" && CLAUDE_CONFIG_DIR="$tmpcfg" bash "$S_RUN/install.sh" ); rc=$?
  rm -rf -- "$tmpcfg"
  [ "$rc" -eq 0 ] || { log "    install.sh 종료 코드 $rc"; return 1; }
  install_ready || { log "    설치 후 검증 실패: $S_WHY"; return 1; }
}
run_initdb() { # node_modules 가 정상일 때 install.sh 의 마지막 단계(DB·데이터 홈 초기화, 멱등)만 한다 — 네트워크 npm ci 로 정상 설치를 날리지 않는다
  ( cd "$S_REAL/mcp-server" && node scripts/init-db.js ) || return 1
  install_ready || { log "    초기화 후 검증 실패: $S_WHY"; return 1; }
}
fix_home_mode() { chmod 700 "$S_HOME"; }
step_install() {
  head_ a "스킬 설치(install.sh: npm ci·DB 초기화·데이터 홈)"
  local row
  for row in "${SKILLS[@]}"; do
    parse_row "$row"
    if install_ready && [ "$FORCE" -eq 0 ]; then
      ok "$S_NAME: 설치 정상${S_DJINN:+ ($S_DJINN)}, 데이터 홈 준비됨($S_HOME)"
    else
      [ -z "${S_WHY:-}" ] || info "$S_NAME: ${S_WHY}"
      if [ "$FORCE" -eq 0 ] && [ -z "$M_WHY" ] && [ -f "$S_REAL/mcp-server/scripts/init-db.js" ]; then
        act "$S_NAME: node $S_RUN/mcp-server/scripts/init-db.js  (node_modules 정상 → npm ci 생략, DB·데이터 홈 0700 초기화만)" run_initdb
      elif [ -f "$S_REAL/install.sh" ]; then
        act "$S_NAME: bash $S_RUN/install.sh  (npm ci·init-db·데이터 홈 0700; 스킬 링크는 임시 폴더로 흡수)" run_install
      else
        fail "$S_NAME: install.sh 가 없다($S_REAL)"; continue
      fi
    fi
    if [ -d "$S_HOME" ]; then
      local mode; mode="$(stat -c %a "$S_HOME")"
      if [ "$mode" = 700 ]; then ok "$S_NAME: 데이터 홈 권한 700"; else warn "$S_NAME: 데이터 홈 권한이 $mode 이다($S_HOME)"; act "$S_NAME: chmod 700 $S_HOME" fix_home_mode; fi
    else
      info "$S_NAME: 데이터 홈($S_HOME)은 위 단계가 만든다"
    fi
  done
}

# ================================================================ b github
declare -A B_PLANNED=()
GH_VIS=""; GH_ERR=""
gh_repo_state() { # GH_STATE=exists|missing|unknown 와 GH_VIS/GH_ERR 를 전역으로 설정(서브셸로 부르지 말 것)
  local out rc
  GH_VIS=""; GH_ERR=""
  out="$(gh repo view "$GH_OWNER/$1" --json visibility -q .visibility 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then GH_VIS="$out"; GH_STATE=exists
  elif printf '%s' "$out" | grep -qiE 'Could not resolve to a Repository|HTTP 404|not found'; then GH_STATE=missing
  else GH_ERR="$out"; GH_STATE=unknown; fi
}
tracked_secrets() { # 개인 데이터 파일이 추적되고 있는가
  git -C "$1" ls-files | grep -E '(^|/)(secrets|raw|data)/|\.(db|db-wal|db-shm|key|env|pem)$|(^|/)\.env' | head -n 5
}
do_gh_create_push() { gh repo create "$GH_OWNER/$S_NAME" --private --source "$S_REAL" --remote origin --push; }
do_gh_create_then_push() { gh repo create "$GH_OWNER/$S_NAME" --private && git -C "$S_REAL" push -u origin main; }
do_add_origin() { git -C "$S_REAL" remote add origin "$1"; }
step_github() {
  head_ b "GitHub private repo 생성·push(gh)"
  if [ "$HAVE_GH" -eq 0 ]; then pend "gh CLI 가 없다 — 이 단계를 건너뜀"; return 0; fi
  if ! gh auth status >/dev/null 2>&1; then pend "gh 인증이 안 돼 있다(gh auth login) — 이 단계를 건너뜀"; return 0; fi
  local row url origin branch dirty sec st
  for row in "${SKILLS[@]}"; do
    parse_row "$row"
    if [ "$S_GH" != 1 ]; then info "$S_NAME: 별도 repo 없음(Doytale repo 안의 skill/) — 건너뜀"; continue; fi
    if [ "$S_NAME" = "$NEVER_ADD" ]; then continue; fi
    url="$GH_URL_BASE/$GH_OWNER/$S_NAME.git"
    [ -d "$S_REAL/.git" ] || { fail "$S_NAME: git repo 가 아니다($S_REAL)"; continue; }
    gh_repo_state "$S_NAME"; st="$GH_STATE"
    origin="$(git -C "$S_REAL" remote get-url origin 2>/dev/null || true)"
    if [ "$st" = unknown ]; then fail "$S_NAME: gh repo view 실패 — ${GH_ERR:-네트워크/인증 확인}"; continue; fi
    if [ "$st" = exists ]; then
      ok "$S_NAME: GitHub repo 이미 있음($GH_OWNER/$S_NAME, $GH_VIS) — 만들지도 push 하지도 않는다"
      [ "$GH_VIS" = PRIVATE ] || warn "$S_NAME: repo 가 PRIVATE 이 아니다($GH_VIS) — 건강·원장 스킬이면 비공개로 바꿀 것"
      if [ -z "$origin" ]; then act "$S_NAME: git remote add origin $url" do_add_origin "$url"
      elif [ "$origin" != "$url" ]; then warn "$S_NAME: origin 이 다른 URL 이다($origin ≠ $url) — 그대로 둠"; fi
      continue
    fi
    # repo 없음 → 만들고 push. 안전 점검 먼저.
    branch="$(git -C "$S_REAL" symbolic-ref --short HEAD 2>/dev/null || true)"
    if [ "$branch" != main ]; then fail "$S_NAME: 현재 브랜치가 main 이 아니다('$branch') — push 하지 않음"; continue; fi
    sec="$(tracked_secrets "$S_REAL")"
    if [ -n "$sec" ]; then fail "$S_NAME: 개인 데이터로 보이는 파일이 추적 중이라 push 하지 않는다: $(printf '%s' "$sec" | tr '\n' ' ')"; continue; fi
    dirty="$(git -C "$S_REAL" status --porcelain | wc -l)"
    [ "$dirty" -eq 0 ] || warn "$S_NAME: 커밋되지 않은 변경 ${dirty}건 — push 에 포함되지 않는다(필요하면 먼저 커밋)"
    if [ -z "$origin" ]; then
      act "$S_NAME: gh repo create $GH_OWNER/$S_NAME --private --source $S_REAL --remote origin --push" do_gh_create_push
    elif [ "$origin" = "$url" ]; then
      act "$S_NAME: gh repo create $GH_OWNER/$S_NAME --private; git push -u origin main" do_gh_create_then_push
    else
      fail "$S_NAME: origin 이 이미 다른 URL 이다($origin) — 수동 확인 필요"; continue
    fi
    [ "$APPLY" -eq 1 ] || B_PLANNED[$S_NAME]=1
  done
}

# ================================================================ c submodule
do_submodule_add() {
  git -C "$SKILLS_DIR" submodule add -b main "$1" "$S_NAME" || return 1
  # 경로를 명시한 커밋: 다른 staged 변경·doil-secretary 포인터는 건드리지 않는다.
  git -C "$SKILLS_DIR" commit -q -m "add $S_NAME submodule" -- .gitmodules "$S_NAME" || return 1
}
step_submodule() {
  head_ c "집계 repo 서브모듈 장착(doil-secretary 포인터 제외, push 안 함)"
  command -v git >/dev/null 2>&1 || { pend "git 이 없다"; return 0; }
  git -C "$SKILLS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { pend "$SKILLS_DIR 가 git repo 가 아니다"; return 0; }
  local row url mode origin head rhead
  for row in "${SKILLS[@]}"; do
    parse_row "$row"
    if [ "$S_GH" != 1 ]; then info "$S_NAME: 서브모듈 대상 아님(Doytale repo 안의 skill/)"; continue; fi
    if [ "$S_NAME" = "$NEVER_ADD" ]; then continue; fi
    url="$GH_URL_BASE/$GH_OWNER/$S_NAME.git"
    mode="$(git -C "$SKILLS_DIR" ls-files -s -- "$S_NAME" | awk 'NR==1{print $1}')"
    if [ "$mode" = 160000 ]; then ok "$S_NAME: 이미 서브모듈로 장착됨"; continue; fi
    if [ -n "$mode" ]; then fail "$S_NAME: 집계 repo 에 일반 파일로 추적 중이다 — 수동 정리 필요"; continue; fi
    if [ -n "$(git -C "$SKILLS_DIR" status --porcelain -- .gitmodules)" ]; then
      fail "$S_NAME: .gitmodules 에 커밋되지 않은 변경이 있어 건드리지 않는다"; continue
    fi
    if [ -n "${B_PLANNED[$S_NAME]:-}" ]; then
      act "$S_NAME: git -C $SKILLS_DIR submodule add -b main $url $S_NAME  + 커밋(.gitmodules·$S_NAME 만)  [b 이후]" do_submodule_add "$url"
      continue
    fi
    # b 가 이미 끝난 상태(또는 b 를 안 돌림): 원격이 있고 push 돼 있어야 한다.
    origin="$(git -C "$S_REAL" remote get-url origin 2>/dev/null || true)"
    if [ "$origin" != "$url" ]; then pend "$S_NAME: origin 이 $url 이 아니다('${origin:-없음}') — 먼저 b 단계(--with-github)"; continue; fi
    head="$(git -C "$S_REAL" rev-parse HEAD 2>/dev/null || true)"
    rhead="$(git -C "$S_REAL" ls-remote origin refs/heads/main 2>/dev/null | awk 'NR==1{print $1}')"
    if [ -z "$rhead" ]; then pend "$S_NAME: 원격 main 을 볼 수 없다(push 안 됨/네트워크) — 먼저 b 단계"; continue; fi
    if [ "$head" != "$rhead" ]; then pend "$S_NAME: 로컬 HEAD($head)가 원격 main($rhead)과 다르다 — 먼저 push"; continue; fi
    act "$S_NAME: git -C $SKILLS_DIR submodule add -b main $url $S_NAME  + 커밋(.gitmodules·$S_NAME 만)" do_submodule_add "$url"
  done
  info "집계 repo push 와 README 수록 표 갱신은 이 스크립트가 하지 않는다: git -C $SKILLS_DIR push"
}

# ================================================================ d claude
claude_add() { # <profile> <name> <entry>
  local cfg="$1" name="$2" entry="$3"
  backup_file "$(cj "$cfg")" || return 1
  CLAUDE_CONFIG_DIR="$cfg" claude mcp add -s user "$name" -- node "$entry" || return 1
  [ "$(pyj state "$(cj "$cfg")" "$name" "$entry")" = same ] || { log "    등록 후 .claude.json 내용이 기대와 다르다"; return 1; }
}
claude_replace() {
  local cfg="$1" name="$2" entry="$3"
  backup_file "$(cj "$cfg")" || return 1
  CLAUDE_CONFIG_DIR="$cfg" claude mcp remove -s user "$name" || return 1
  claude_add "$cfg" "$name" "$entry"
}
claude_remove() {
  local cfg="$1" name="$2" entry="$3"
  backup_file "$(cj "$cfg")" || return 1
  CLAUDE_CONFIG_DIR="$cfg" claude mcp remove -s user "$name" || return 1
  [ "$(pyj state "$(cj "$cfg")" "$name" "$entry")" = absent ] || { log "    제거 후에도 항목이 남아 있다"; return 1; }
}
step_claude() {
  head_ d "Claude 프로필 .claude.json MCP 등록(claude mcp $( [ "$ROLLBACK" -eq 1 ] && echo remove || echo add ) -s user)"
  [ "$HAVE_CLAUDE" -eq 1 ] || pend "claude CLI 가 PATH 에 없다 — --apply 는 거부된다(상태 판정은 JSON 직접 읽기로 계속)"
  log "  프로필 ${#PROFILES[@]}개 ($PROFILE_NOTE):"
  local cfg row st
  for cfg in "${PROFILES[@]+"${PROFILES[@]}"}"; do log "    - $cfg"; done
  [ "$APPLY" -eq 0 ] || { local n; n="$(pgrep -u "$(id -u)" -x claude 2>/dev/null | wc -l)"; [ "$n" -eq 0 ] || warn "실행 중인 claude 프로세스 ${n}개 — .claude.json 은 Claude Code 가 수시로 다시 쓴다(백업을 남기며, 덮어써지면 다시 실행하면 복구된다)"; }
  for cfg in "${PROFILES[@]+"${PROFILES[@]}"}"; do
    for row in "${SKILLS[@]}"; do
      parse_row "$row"
      st="$(pyj state "$(cj "$cfg")" "$S_NAME" "$S_ENTRY_REG")"
      local tag; tag="$(basename "$cfg")/$S_NAME"
      case "$st" in
        badjson) warn "$tag: .claude.json 을 읽을 수 없다(손상?) — 건드리지 않음"; continue ;;
      esac
      if [ "$ROLLBACK" -eq 1 ]; then
        case "$st" in
          nofile|absent) N_OK=$((N_OK + 1)) ;;
          same) act "$tag: CLAUDE_CONFIG_DIR=$cfg claude mcp remove -s user $S_NAME  (.claude.json 백업 후)" claude_remove "$cfg" "$S_NAME" "$S_ENTRY_REG" ;;
          differs) warn "$tag: 항목이 우리가 넣은 것과 다르다 — 사용자 항목으로 보고 그대로 둠" ;;
        esac
        continue
      fi
      case "$st" in
        same) ok "$tag: 이미 등록됨" ;;
        nofile|absent)
          [ -f "$S_ENTRY_REAL" ] || { fail "$tag: 진입점이 없다($S_ENTRY_REAL)"; continue; }
          if [ "$APPLY" -eq 1 ] && ! sel install; then module_check; [ -z "$M_WHY" ] || { fail "$tag: 설치가 안 돼 있다($M_WHY) — 먼저 --only install"; continue; }; fi
          act "$tag: CLAUDE_CONFIG_DIR=$cfg claude mcp add -s user $S_NAME -- node $S_ENTRY_REG  (.claude.json 백업 후)" claude_add "$cfg" "$S_NAME" "$S_ENTRY_REG" ;;
        differs)
          if [ "$FORCE" -eq 1 ]; then act "$tag: 다른 내용의 기존 항목 교체(remove → add, --force)" claude_replace "$cfg" "$S_NAME" "$S_ENTRY_REG"
          else warn "$tag: 충돌 — 같은 이름의 다른 항목이 이미 있다. 그대로 둠(교체하려면 --force)"; N_CONFLICT=$((N_CONFLICT + 1)); fi ;;
      esac
    done
  done
}

# ================================================================ e links
do_link() { mkdir -p "$1/skills" && ln -sfn "$S_REG" "$1/skills/$S_NAME"; }
do_unlink() { rm -f -- "$1/skills/$S_NAME"; }
step_links() {
  head_ e "스킬 심링크 <프로필>/skills/<이름> → $REG_ROOT/..."
  info "skills/install.sh 를 쓰지 않는 이유: 그 스크립트는 git submodule update --init --recursive(사용자의 doil-secretary 포인터를 되돌릴 수 있음)와 모든 스킬의 install.sh 를 함께 실행한다. 여기서는 신규 스킬 링크만 건다."
  local cfg row st l tag
  for cfg in "${PROFILES[@]+"${PROFILES[@]}"}"; do
    for row in "${SKILLS[@]}"; do
      parse_row "$row"
      l="$cfg/skills/$S_NAME"; tag="$(basename "$cfg")/$S_NAME"
      st="$(link_state "$l")"
      if [ "$ROLLBACK" -eq 1 ]; then
        case "$st" in
          absent) N_OK=$((N_OK + 1)) ;;
          same) act "$tag: rm $l  (심링크만 지움, 대상 폴더는 그대로)" do_unlink "$cfg" ;;
          other) warn "$tag: 다른 곳을 가리키는 링크라 그대로 둠($(readlink "$l"))" ;;
          conflict) warn "$tag: 링크가 아닌 파일/폴더라 그대로 둠" ;;
        esac
        continue
      fi
      case "$st" in
        same) ok "$tag: 링크 정상" ;;
        absent) act "$tag: ln -sfn $S_REG $l" do_link "$cfg" ;;
        other)
          if [ "$FORCE" -eq 1 ]; then act "$tag: 다른 곳을 가리키던 링크($(readlink "$l")) 교체(--force)" do_link "$cfg"
          else warn "$tag: 충돌 — 다른 곳을 가리키는 링크($(readlink "$l")). 그대로 둠(교체하려면 --force)"; N_CONFLICT=$((N_CONFLICT + 1)); fi ;;
        conflict) warn "$tag: 충돌 — 링크가 아닌 파일/폴더가 이미 있다. 건드리지 않음"; N_CONFLICT=$((N_CONFLICT + 1)) ;;
      esac
    done
  done
}

# ================================================================ f void
shared_set() { backup_file "$VOID_SHARED" && pyj set "$VOID_SHARED" "$1" "$2"; }
shared_del() { backup_file "$VOID_SHARED" && pyj del "$VOID_SHARED" "$1"; }
step_void() {
  head_ f "void mcp-shared.json($VOID_SHARED)"
  if [ ! -f "$VOID_SHARED" ]; then pend "mcp-shared.json 이 없다 — void 미설정이면 건너뜀(있다면 경로 확인)"; return 0; fi
  if [ "$(pyj state "$VOID_SHARED" _none_ x)" = badjson ]; then warn "mcp-shared.json 을 읽을 수 없다(손상?) — 건드리지 않음"; return 0; fi
  [ "$(pyj fmt "$VOID_SHARED")" = identical ] || warn "mcp-shared.json 서식이 이 스크립트의 직렬화와 달라 키 순서·들여쓰기가 바뀔 수 있다(내용은 보존, 백업 남김)"
  local row st
  for row in "${SKILLS[@]}"; do
    parse_row "$row"
    st="$(pyj state "$VOID_SHARED" "$S_NAME" "$S_ENTRY_REG")"
    if [ "$ROLLBACK" -eq 1 ]; then
      case "$st" in
        absent) N_OK=$((N_OK + 1)) ;;
        same) act "$S_NAME: mcp-shared.json 에서 '$S_NAME' 항목 제거(백업 후)" shared_del "$S_NAME" ;;
        differs) warn "$S_NAME: mcp-shared.json 항목이 우리가 넣은 것과 다르다 — 그대로 둠" ;;
      esac
      continue
    fi
    case "$st" in
      same) ok "$S_NAME: 이미 등록됨" ;;
      absent) act "$S_NAME: mcp-shared.json 에 '$S_NAME' 추가 → node $S_ENTRY_REG  (백업 후)" shared_set "$S_NAME" "$S_ENTRY_REG" ;;
      differs)
        if [ "$FORCE" -eq 1 ]; then act "$S_NAME: mcp-shared.json 의 다른 내용 항목 교체(--force)" shared_set "$S_NAME" "$S_ENTRY_REG"
        else warn "$S_NAME: 충돌 — 같은 이름의 다른 항목이 있다. 그대로 둠(교체하려면 --force)"; N_CONFLICT=$((N_CONFLICT + 1)); fi ;;
    esac
  done
  log "  반영 안내(사용자가 직접 — 이 스크립트는 void 를 실행하지 않는다):"
  log "    void mcp list                 # 공유 MCP 정의 확인(읽기 전용)"
  log "    void mcp sync                 # 기본 dry-run: 어느 프로필에 무엇이 추가되는지 출력"
  log "    void mcp sync --apply         # 해당 프로필 세션이 없을 때 반영(void 가 .claude.json.bak-<시각>을 남긴다)"
  if [ "$ROLLBACK" -eq 1 ]; then log "    ※ void mcp sync 는 삭제하지 않는다 — 이미 동기화된 프로필의 항목은 d 단계(--rollback)가 제거한다"; fi
  log "    omni 프로필은 다음 void 런치부터 mcp-shared.json 을 자동 병합한다."
}

# ================================================================ g verify
step_verify() {
  head_ g "$( [ "$ROLLBACK" -eq 1 ] && echo '롤백 확인(등록이 남아 있지 않은가)' || echo '등록 검증(체크리스트 "등록 후 확인 방법")' )"
  local row st cfg l tmp out tag
  if [ "$ROLLBACK" -eq 1 ]; then
    local left=0
    for cfg in "${PROFILES[@]+"${PROFILES[@]}"}"; do
      for row in "${SKILLS[@]}"; do
        parse_row "$row"; tag="$(basename "$cfg")/$S_NAME"
        [ "$(pyj state "$(cj "$cfg")" "$S_NAME" "$S_ENTRY_REG")" != same ] || { left=1; vmiss "$tag: .claude.json 에 등록이 남아 있다"; }
        [ "$(link_state "$cfg/skills/$S_NAME")" != same ] || { left=1; vmiss "$tag: 링크가 남아 있다"; }
      done
    done
    if [ -f "$VOID_SHARED" ]; then
      for row in "${SKILLS[@]}"; do parse_row "$row"
        [ "$(pyj state "$VOID_SHARED" "$S_NAME" "$S_ENTRY_REG")" != same ] || { left=1; vmiss "$S_NAME: mcp-shared.json 에 항목이 남아 있다"; }
      done
    fi
    [ "$left" -eq 0 ] && ok "롤백 확인: 프로필 ${#PROFILES[@]}개 × 스킬 ${#SKILLS[@]}개 — .claude.json 등록·링크·mcp-shared 항목이 남아 있지 않다"
    return 0
  fi
  for row in "${SKILLS[@]}"; do
    parse_row "$row"
    module_check
    if [ -n "$M_WHY" ]; then vmiss "$S_NAME: $M_WHY"; continue; fi
    ok "$S_NAME: 진입점·node_modules${S_DJINN:+·$S_DJINN}"
    tmp="$(mktemp -d)" || { fail "$S_NAME: 임시 폴더 생성 실패"; continue; }
    out="$(node -e "$PROBE_JS" "$S_ENTRY_REAL" "$S_ENV" "$tmp" 2>&1)"
    rm -rf -- "$tmp"
    case "$out" in OK*) ok "$S_NAME: stdio 기동·tools/list ← 임시 홈($out)" ;; *) fail "$S_NAME: stdio 프로브 실패 — $out" ;; esac
    if [ -d "$S_HOME" ]; then
      local mode; mode="$(stat -c %a "$S_HOME")"
      [ "$mode" = 700 ] && ok "$S_NAME: 데이터 홈 700" || warn "$S_NAME: 데이터 홈 권한 $mode($S_HOME)"
      local loose; loose="$(find "$S_HOME" -maxdepth 3 -type f \( -name '*.db' -o -name '*.key' -o -name '.env' \) \( -perm /077 \) 2>/dev/null | head -n 3)"
      [ -z "$loose" ] || warn "$S_NAME: 그룹/기타 권한이 열린 DB·키 파일: $(printf '%s' "$loose" | tr '\n' ' ')"
    fi
  done
  local nreg nlink miss
  for cfg in "${PROFILES[@]+"${PROFILES[@]}"}"; do
    nreg=0; nlink=0; miss=""
    for row in "${SKILLS[@]}"; do
      parse_row "$row"; tag="$(basename "$cfg")/$S_NAME"
      st="$(pyj state "$(cj "$cfg")" "$S_NAME" "$S_ENTRY_REG")"
      if [ "$st" = same ]; then nreg=$((nreg + 1)); else miss="$miss $S_NAME:.claude.json=$st"; fi
      l="$(link_state "$cfg/skills/$S_NAME")"
      if [ "$l" = same ]; then nlink=$((nlink + 1)); else miss="$miss $S_NAME:링크=$l"; fi
    done
    if [ -z "$miss" ]; then ok "$(basename "$cfg"): ${#SKILLS[@]}개 스킬 .claude.json 등록·링크 일치"
    elif [ "$APPLY" -eq 1 ]; then fail "$(basename "$cfg"): .claude.json ${nreg}/${#SKILLS[@]}, 링크 ${nlink}/${#SKILLS[@]} —$miss"
    else info "$(basename "$cfg"): .claude.json ${nreg}/${#SKILLS[@]}, 링크 ${nlink}/${#SKILLS[@]} (적용 전)"; fi
    # 서버를 실제로 띄워 보는 확인 — 데이터 홈을 만들 수 있으므로 --apply 에서만
    if [ "$APPLY" -eq 1 ] && [ "$HAVE_CLAUDE" -eq 1 ]; then
      out="$(CLAUDE_CONFIG_DIR="$cfg" timeout 120 claude mcp list 2>&1)"; local rc=$?
      if [ "$rc" -ne 0 ] && [ -z "$out" ]; then warn "$(basename "$cfg"): claude mcp list 를 실행하지 못했다(rc=$rc)"; continue; fi
      for row in "${SKILLS[@]}"; do
        parse_row "$row"
        if printf '%s\n' "$out" | grep -E "^${S_NAME}:" | grep -q 'Connected'; then ok "$(basename "$cfg")/$S_NAME: claude mcp list → Connected"
        elif printf '%s\n' "$out" | grep -qE "^${S_NAME}:"; then fail "$(basename "$cfg")/$S_NAME: claude mcp list 에서 연결 실패"
        else fail "$(basename "$cfg")/$S_NAME: claude mcp list 에 항목이 없다"; fi
      done
    fi
  done
  if [ -f "$VOID_SHARED" ]; then
    miss=""
    for row in "${SKILLS[@]}"; do
      parse_row "$row"
      st="$(pyj state "$VOID_SHARED" "$S_NAME" "$S_ENTRY_REG")"
      [ "$st" = same ] || miss="$miss $S_NAME=$st"
    done
    if [ -z "$miss" ]; then ok "mcp-shared.json: ${#SKILLS[@]}개 스킬 항목 일치"
    elif [ "$APPLY" -eq 1 ]; then fail "mcp-shared.json:$miss"
    else info "mcp-shared.json: 항목 미등록 —$miss (적용 전)"; fi
  fi
  [ "$APPLY" -eq 1 ] || info "dry-run: claude mcp list(서버 실제 기동) 확인은 --apply 에서만 한다. 이후 새 Claude 세션에서 mcp__<이름>__* 도구가 보여야 한다."
  info "DOBIS(다중 사용자·사용자 구분 없음 → 등록하지 않기로 결정)와 console(mcp.advanced.json·tool-policy·재시작)은 이 스크립트 범위 밖이다."
}

# ================================================================ 실행
log "== register-new-skills $( [ "$ROLLBACK" -eq 1 ] && echo '[ROLLBACK] ' )$( [ "$APPLY" -eq 1 ] && echo '[APPLY: 실제 적용]' || echo '[DRY-RUN: 아무것도 쓰지 않는다]' )"
log "skills repo : $SKILLS_DIR"
log "등록 경로   : $REG_ROOT/...  (실제 $DOIL_ROOT)"
log "대상 스킬   : $(for r in "${SKILLS[@]}"; do printf '%s ' "${r%%|*}"; done)"
log "단계        : $(for s in "${STEP_ORDER[@]}"; do sel "$s" && printf '%s(%s) ' "$s" "${STEP_LETTER[$s]}"; done)"
log "제외(고정)  : $NEVER_ADD 포인터(사용자 것), DOBIS, console"
for s in "${STEP_ORDER[@]}"; do
  sel "$s" || continue
  case "$s" in
    install) step_install ;; github) step_github ;; submodule) step_submodule ;;
    claude) step_claude ;; links) step_links ;; void) step_void ;; verify) step_verify ;;
  esac
done

# ---------------------------------------------------------------- 요약
log ""
log "== 요약 $( [ "$APPLY" -eq 1 ] && echo '[APPLY]' || echo '[DRY-RUN]' ): 이미 충족 $N_OK, 해야 할 일 $N_TODO, 수행 $N_DONE, 실패 $N_FAIL, 경고 $N_WARN"
if [ "$APPLY" -eq 0 ]; then
  if [ "${#TODOS[@]}" -gt 0 ]; then
    log "할 일 목록(--apply 가 실행할 것, 명령 전문은 위 [TODO] 줄):"
    for s in "${STEP_ORDER[@]}"; do
      [ -n "${TODO_N[${STEP_LETTER[$s]}]:-}" ] || continue
      k="${STEP_LETTER[$s]}"
      line="  [$k] $s ${TODO_N[$k]}건 — 대상: $(uniq_words "${TODO_WHAT[$k]}")"
      [ -z "${TODO_WHERE[$k]:-}" ] || line="$line / 프로필: $(uniq_words "${TODO_WHERE[$k]}")"
      log "$line"
    done
  else
    if [ "$ROLLBACK" -eq 1 ]; then log "할 일 없음 — 제거할 등록이 없다."; else log "할 일 없음 — 이미 모두 등록돼 있다."; fi
  fi
fi
if [ "${#BACKUPS[@]}" -gt 0 ]; then
  log "백업 파일(되돌리려면 이것을 원래 이름으로 복사):"
  for b in "${BACKUPS[@]}"; do log "  - $b"; done
fi
if [ "${#PENDING[@]}" -gt 0 ]; then
  log "PENDING(실행 전에 풀어야 할 전제/결정 ${#PENDING[@]}건):"
  for p in "${PENDING[@]}"; do log "  - $p"; done
fi
if [ "$N_CONFLICT" -gt 0 ]; then log "충돌 ${N_CONFLICT}건은 건드리지 않았다(--force 로 교체)."; fi
if [ "$ROLLBACK" -eq 1 ]; then
  log "롤백이 남기는 것: node_modules·데이터 홈(건강·원장 데이터, 삭제하지 않음)·GitHub repo·서브모듈. 서브모듈 제거는 수동: git -C $SKILLS_DIR submodule deinit -f <이름> && git -C $SKILLS_DIR rm -f <이름>"
fi
if [ "$APPLY" -eq 1 ] && [ "$ROLLBACK" -eq 0 ]; then
  log "다음: 새 Claude 세션부터 반영된다. void: void mcp sync → void mcp sync --apply. console·DOBIS 는 통합 배포 스크립트."
fi
if [ "$APPLY" -eq 0 ]; then
  log "dry-run OK — 적용: $SELF $( [ "$ROLLBACK" -eq 1 ] && echo '--rollback ' )--apply${ONLY:+ --only $ONLY}$( [ "$WITH_GH" -eq 1 ] && echo ' --with-github' )"
  exit 0
fi
[ "$N_FAIL" -eq 0 ] || { log "FAIL ${N_FAIL}건 — 위 [FAIL] 줄 확인. 다시 실행해도 안전하다(멱등)."; exit 3; }
log "apply OK"
exit 0
