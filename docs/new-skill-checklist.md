# 신규 스킬 MCP 등록 체크리스트

작성 2026-10-18. 신규 스킬(doil-health, doil-portfolio, Doytale 제작 스킬)이 공통으로 쓰는 기반 문서다.
이 문서의 모든 "현재 상태"는 실제 파일을 열어 확인한 값이다. 확인하지 못한 것은 **[미확인]** 으로 적었다. 비밀 값은 쓰지 않았다.

- 1장 사전 준비(repo·서브모듈·dJinn 핀·설치 검증)
- 2장 등록 5곳(예시·검증·제거·반영 조건)
- 3장 반영 조건 요약과 적용 순서
- 4장 백업(데이터 홈 백업 설계·스크립트·복원·cron)
- 5장 console e2e(실행 결과와 재실행 절차)
- 6장 이번 조사에서 발견한 어긋남과 미해결

## 0. 한눈에 보기

등록 지점 5곳은 모두 수동이고, 서로 자동 동기화되지 않는다. 그래서 스킬마다 빠진 곳이 생긴다(아래 현황표).

| # | 지점 | 파일 | 무엇을 하나 | 반영 |
|---|------|------|-------------|------|
| 1 | DOBIS | `docker/agent/dobis/mcp.json` + `config.json`의 `DOBIS_ALLOWED_TOOLS` | doil.me 관리 콘솔 DOBIS 챗봇 | 새 세션부터 |
| 2 | doil-console MCP | `doil-console/config/mcp.advanced.json` | console advanced 챗봇이 띄울 MCP 서버 | 다음 실행부터(재시작 불필요) |
| 3 | doil-console 정책 | `doil-console/config/tool-policy.json` | default-deny 도구 허용(auto/confirm/deny) | **console 재시작 필요** |
| 4 | void | `~/.config/void-launcher/mcp-shared.json`(권장) 또는 `void-ai-launcher/lib/void-persistent/omniMcp.js` | void omni 프로필·일반 프로필 | 다음 void 런치/동기화 후 새 세션 |
| 5 | Claude 프로필 | `~/.claude*/.claude.json`(`claude mcp add -s user`/`void mcp sync`) + 스킬 심링크 | Claude Code CLI 세션과 console의 Skill 도구 | 새 세션부터 |

현재 등록 현황(2026-10-18, 파일을 직접 열어 확인):

| 스킬 | 1 DOBIS | 2 console MCP | 3 정책 | 4 void(하드코딩) | 5 `.claude.json` |
|------|:---:|:---:|:---:|:---:|:---:|
| sun-sang | O | O | O (22/22 일치) | O | O (5개 프로필) |
| ai-echo | O | O | O (29/29 일치, 정적 대조) | O | O (5개 프로필) |
| doil-secretary | O | O | **3개 누락** | O | **X (어느 프로필에도 없음)** |

doil-secretary는 5번이 비어 있어 Claude Code CLI 세션에는 `mcp__doil-secretary__*`가 보이지 않는다(이번 세션의 도구 목록에도 없다). 3번에는 서버가 내는 22개 도구 중 `sec_clear_cache`, `sec_complete`, `sec_memo_update`가 없어 console 챗봇에서는 default deny다. 신규 스킬은 이 두 가지 사고를 반복하지 않도록 6장 체크박스를 끝까지 채운다.

## 1. 사전 준비

### 1-1. 스킬 repo와 서브모듈 (README와 `.gitmodules`의 어긋남 확인)

확인한 사실(`/mnt/wsl/das/dev/DOIL/skills`):

- `.gitmodules`와 git 인덱스(mode 160000)에 서브모듈 **7개**: ai-echo, d-tools, doil-bootstrap, doil-research, doil-secretary, doil-supervise, sun-sang. 모두 `https://github.com/D0iloppa/<name>.git`, `branch = main`.
- README 표는 ai-echo와 doil-secretary를 "(로컬 폴더, 서브모듈 아님)"이라고 쓰지만 **사실이 아니다**. 둘 다 서브모듈이다(각 폴더에 `.git` 파일, `git submodule status`에 나옴). README는 d-tools와 explain-diff를 아예 수록하지 않는다.
- `explain-diff`는 서브모듈이 아니라 집계 repo에 파일이 직접 커밋된 평범한 폴더다. 즉 지금은 두 방식이 섞여 있다. **기본은 서브모듈**이다.
- doil-secretary 서브모듈은 `feat/console-calendar-memo` 브랜치(a31499e, origin에 push됨)를 가리키고, 폴더 안 `.claude/`가 ignore되지 않아 `git status`에 ` ?`가 뜬다. ai-echo는 브랜치가 아니라 detached(8b6a8db)다.
- 이 문서를 쓰는 동안 집계 repo에 `doil-health/`(docs만 있는 untracked 폴더)가 생겼다. 서브모듈로 붙이려면 독립 repo를 먼저 만들고 그 repo를 이 경로에 clone하거나, 폴더를 치운 뒤 `git submodule add`를 한다(이미 있는 비-repo 폴더에는 add가 거부된다).

신규 스킬 repo 절차:

```bash
# 1) 독립 repo 생성(원격은 사용자가 만든다). 건강·포트폴리오는 비공개 repo 권장(코드엔 데이터가 없지만 SKILL.md에 개인 맥락이 들어갈 수 있다).
# 2) 집계 repo에 장착
cd /mnt/wsl/das/dev/DOIL/skills
git submodule add https://github.com/D0iloppa/<skill>.git <skill>
git commit -m "add <skill> submodule"
# 3) README 수록 표에 한 줄 추가(이번에 ai-echo/secretary 행의 '서브모듈 아님'도 같이 바로잡는다)
```

스킬 폴더 템플릿은 sun-sang/doil-secretary를 따른다: `SKILL.md`(있어야 `install.sh`가 스킬로 인식), `mcp-server/{package.json,package-lock.json,src/,scripts/init-db.js,init/init.sql}`, `install.sh`, `.gitignore`(데이터가 repo 안에 생기는 사고를 막는 안전망: `mcp-server/data/` 등 — doil-secretary의 `.gitignore` 참고). 데이터는 repo 밖의 **데이터 홈**(`~/.<name>`, `<NAME>_HOME` 환경변수로 오버라이드)에 둔다. 이 관례는 sun-sang(`SUNSANG_HOME`)과 doil-secretary(`DOILSECRETARY_HOME`)가 쓰며, 새 스킬의 변수 이름도 같은 규칙(이름에서 하이픈 제거·대문자 + `_HOME`)을 권한다 **[미확인: 신규 스킬이 실제로 쓰는 이름]**. 백업 스크립트와 5장 e2e 검증이 이 변수 이름에 기댄다.

### 1-2. dJinn 핀 권고 (Second-Look)

현재 상태(`mcp-server/package.json`·`package-lock.json`):

| 스킬 | package.json 핀 | 락파일 버전 | **실제 설치된 node_modules** |
|------|----------------|------------|------------------------------|
| sun-sang, ai-echo, doil-supervise | `3eacee5` | 0.1.2 | 0.1.2 |
| doil-secretary | `e4c751b` | 0.2.0 | **0.1.2 (핀과 다름)** |

dJinn repo(`/mnt/wsl/das/dev/DOIL/djinn`, main) 관련 커밋:

| 커밋 | 날짜 | 내용 |
|------|------|------|
| `3eacee5` | 2026-06-29 | 0.1.2. legacy `DJinn.define()` API 시대 |
| `f4c53a0` | 2026-07-18 | 0.2.0 코드 리뷰 조치: **`define()` 컬렉션 이름·where/orderBy/인덱스 JSON 경로 검증(SQL 보간 차단)**, `_` 접두 네임스페이스를 MCP 도구에서 제외 외 8건 |
| `e4c751b` | 2026-08-13 | `DJinn.clearCache()` 공개 API(+`djinn_clear_cache` 도구). 외부 프로세스가 같은 DB 파일을 바꿨을 때 낡은 캐시가 다음 `put()`의 merge 기반이 되어 외부 변경을 조용히 되돌리는 사고의 탈출구 |
| `011a18f` | 2026-10-16 | 0.3.0 `SnapshotDriver`(DB를 행당 JSON 파일 트리로 export/import, git 공유용). 추가형 변경 |

**Recommendation:** 신규 스킬은 dJinn `e4c751b374240f58267c6cafbab704b381672b31`(0.2.0 + `clearCache`)에 핀한다. `package.json`에 `git+https://github.com/D0iloppa/dJinn.git#e4c751b374240f58267c6cafbab704b381672b31`, 설치는 `npm ci`.

**Why (brief):** (1) 3eacee5에는 0.2.0 보안 수정(f4c53a0)이 없고, 건강 데이터는 한 번 새면 되돌릴 수 없다. (2) 스킬 MCP 서버는 Claude 세션·DOBIS·console마다 **별도 프로세스**로 뜨므로 건강 DB도 같은 파일을 여러 프로세스가 연다. `clearCache`가 없으면 secretary가 겪은 "낡은 캐시가 외부 변경을 되돌리는" 사고가 난다. (3) 이미 한 스킬(secretary)이 쓰는 커밋이라 핀 종류가 늘지 않는다. (4) HEAD(011a18f)의 SnapshotDriver는 소비하는 스킬이 없고, "git 공유용 JSON 트리"는 건강 데이터에 오히려 위험하다.

**Second look:**
- 레퍼런스 렌즈 → kept. 기존 4개 의존 중 가장 최근 기능을 요구한 스킬이 e4c751b를 골랐다. 단 사실 확인에서 **설치본이 핀과 다른** 것이 드러났다(설치된 dJinn은 4개 모두 0.1.2이고, 그중 secretary만 핀이 e4c751b라 어긋난다). 실제로 secretary의 `sec_clear_cache`는 이 서버 환경에서 `djinn.clearCache is not a function`으로 실패한다(secretary node_modules에서 `typeof DJinn.prototype.clearCache === 'undefined'` 실측).
- 도전자 렌즈(Erich Gamma의 관점) → kept, 검증 단계 추가. 경계와 공개 계약: 0.2.0부터 컬렉션 이름은 `^[a-zA-Z_][a-zA-Z0-9_]*$`, JSON 경로 세그먼트는 유니코드 문자·숫자·`_`만 되고 위반하면 throw한다. 신규 스킬은 컬렉션·필드 이름에 하이픈·점·공백을 쓰지 않는다. `_` 접두 컬렉션은 dJinn이 자동 생성하는 MCP 도구에서 빠지지만 이 스킬들은 MCP 도구를 손으로 만들어 영향이 없다. 프리모템: (a) 핀 커밋이 사라지면 설치가 깨진다 → dJinn repo는 로컬(`/DEVELOP/DOIL/djinn`)과 GitHub 두 곳에 있고 e4c751b는 main 이력에 있다. 태그를 달아 두는 것은 사용자 repo 변경이라 제안만 한다. (b) 락파일의 `resolved`가 `git+ssh://`라 SSH 키가 없는 새 머신·CI에서 설치가 실패한다. (c) **`npm install`이 기존 node_modules를 그대로 두어 핀이 안 먹는 일이 실제로 발생**했다. (d) 0.2.0이 `sqlite-vec` 네이티브 의존을 추가했다. `require`는 `attach()` 시점으로 미뤄져(리뷰 5번) 안 쓰면 로드 실패가 없지만, 설치 때는 바이너리를 받아야 한다 **[미확인: 오프라인 설치 실측]**. 운영: dJinn은 better-sqlite3 평문 DB라 DB 자체는 암호화되지 않는다. 그래서 4장의 백업 암호화가 필수고 데이터 홈은 0700, DB는 0600이어야 한다.
- 재적합 렌즈(Andrej Karpathy의 관점) → kept. 새 핀을 만들지 않고 검증된 기존 커밋을 재사용한다. 0.3.0 상향, 구 핀 3개 스킬 일괄 상향, dJinn 태그 생성은 이번 범위가 아니다.
- 수정: 이름 붙일 수 있는 문제 = **설치본/락 드리프트(installed-vs-pinned drift)**. 아래 1-3의 설치 검증을 체크리스트에 넣었다. 핀 자체는 그대로다.

### 1-3. MCP 서버 설치 검증 (등록 전에 한다)

```bash
cd /mnt/wsl/das/dev/DOIL/skills/<skill>/mcp-server
npm ci                                   # npm install 이 아니라 ci: 락파일대로 node_modules 를 다시 만든다
node -e 'const p=require("@d0iloppa/djinn/package.json");const {DJinn}=require("@d0iloppa/djinn");
 console.log("djinn",p.version,"clearCache:",typeof DJinn.prototype.clearCache)'   # 기대: djinn 0.2.0 clearCache: function
node -e 'const l=require("./package-lock.json").packages["node_modules/@d0iloppa/djinn"];
 const m=require("./node_modules/.package-lock.json").packages["node_modules/@d0iloppa/djinn"];
 console.log(l.resolved===m.resolved?"lock==installed":"DRIFT",l.resolved.slice(-8),m.resolved.slice(-8))'
```

위 `npm ci`와 검증은 **지금 `doil-secretary`에도 필요한 수리**다(이번에는 쓰기 범위 밖이라 하지 않았다): `cd /mnt/wsl/das/dev/DOIL/skills/doil-secretary/mcp-server && npm ci`.

등록 전 공통 프로브(아래 2장 모든 검증이 이것을 쓴다): `config/mcp.advanced.json`의 그 서버 항목을 **임시 데이터 홈**으로 기동해 `tools/list`를 부르고 정책과 대조한다. LLM 호출 없음, 운영 데이터 홈 미접촉. 아래 코드를 `probe-mcp.cjs`로 저장해 쓴다(sun-sang·secretary로 검증 완료).

```js
"use strict";
// 사용: node probe-mcp.cjs <서버이름> <데이터홈_환경변수>   예) node probe-mcp.cjs doil-health DOILHEALTH_HOME
// config/mcp.advanced.json 의 그 서버 항목(command/args)을 그대로 임시 데이터 홈으로 기동해 initialize + tools/list 를 호출하고,
// tools/list 이름을 config/tool-policy.json 과 대조한다(목록에 없으면 default deny). LLM 호출 없음, 운영 데이터 홈 미접촉.
const { spawn } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const CONSOLE = process.env.DOIL_CONSOLE_DIR || "/DEVELOP/DOIL/doil-console";
const [name, homeEnv] = process.argv.slice(2);
if (!name || !homeEnv) { console.error("usage: probe-mcp.cjs <server> <HOME_ENV>"); process.exit(1); }
const entry = JSON.parse(fs.readFileSync(path.join(CONSOLE, "config/mcp.advanced.json"), "utf8")).mcpServers[name];
if (!entry) { console.error(`FAIL: config/mcp.advanced.json 에 '${name}' 항목이 없다`); process.exit(1); }
const spec = JSON.parse(fs.readFileSync(path.join(CONSOLE, "config/tool-policy.json"), "utf8")).mcp[name];
const home = fs.mkdtempSync(path.join(os.tmpdir(), `probe-${name}-`));
const child = spawn(entry.command === "${DOIL_CONSOLE_NODE_COMMAND}" ? process.execPath : entry.command, entry.args,
  { env: { PATH: process.env.PATH, HOME: process.env.HOME, ...(entry.env || {}), [homeEnv]: home }, stdio: ["pipe", "pipe", "inherit"] });
let buf = ""; const waiting = {};
child.stdout.on("data", (d) => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const m = JSON.parse(buf.slice(0, i)); buf = buf.slice(i + 1); if (m.id && waiting[m.id]) waiting[m.id](m); } });
const rpc = (id, method, params) => new Promise((r) => { waiting[id] = r; child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n"); });
const timer = setTimeout(() => { console.error("FAIL: 20초 안에 응답 없음"); child.kill("SIGKILL"); fs.rmSync(home, { recursive: true, force: true }); process.exit(1); }, 20000);
(async () => {
  const init = await rpc(1, "initialize", { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "probe", version: "0" } });
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  const tools = (await rpc(2, "tools/list", {})).result.tools.map((t) => t.name);
  clearTimeout(timer); child.kill("SIGTERM");
  console.log(`server=${init.result.serverInfo.name} tools=${tools.length} temp-home-created=${fs.existsSync(path.join(home, "data"))}`);
  if (!spec) { console.log(`정책: config/tool-policy.json 에 mcp.${name} 블록이 없다 → 전부 default deny`); }
  else {
    const kind = (n) => (spec.deny || []).includes(n) ? "deny" : (spec.confirm || []).includes(n) ? "confirm" : (spec.auto || []).includes(n) ? "auto" : "UNLISTED(=deny)";
    const by = {}; for (const n of tools) (by[kind(n)] ||= []).push(n);
    for (const [k, v] of Object.entries(by)) console.log(`  ${k}: ${v.length}${k.startsWith("UNLISTED") ? "  -> " + v.join(", ") : ""}`);
    const stale = [...(spec.auto || []), ...(spec.confirm || []), ...(spec.deny || [])].filter((n) => !tools.includes(n));
    console.log(`  정책에만 있고 서버에 없는 이름: ${stale.length ? stale.join(", ") : "없음"}`);
  }
  fs.rmSync(home, { recursive: true, force: true });
})().catch((e) => { console.error("FAIL:", e.message); fs.rmSync(home, { recursive: true, force: true }); process.exit(1); });
```

사용: `node probe-mcp.cjs doil-health DOILHEALTH_HOME`(1·2번 등록 뒤, 3번 정책 전에는 "UNLISTED(=deny)"가 정상).

## 2. 등록 5곳

### 2-1. DOBIS — `mcp.json` + `config.json`

- 파일: `/mnt/wsl/das/dev/DOIL/docker/agent/dobis/mcp.json`, 같은 폴더 `config.json`(둘 다 `/mnt/wsl/das/dev/DOIL/docker` git repo가 추적한다).
- **주의**: `worker.py:108-112`의 `DOBIS_ALLOWED_TOOLS`는 *기본값*일 뿐이다. 실제 값은 `config.json`의 같은 키가 덮어쓴다(`worker.py:68` 우선순위 `_DEFAULTS < config.json < env`, `.env`에 "config.json 이 단일 소스, 새 MCP 서버는 mcp.json + config.json 두 곳만 갱신"이라는 주석, `.env`의 `DOBIS_ALLOWED_TOOLS`는 의도적으로 미설정). 두 값은 이미 어긋나 있다: `config.json`에는 `ToolSearch`·`mcp__ubiq__*`가 있고 `worker.py` 기본값에는 없다. **`worker.py`만 고치면 아무 일도 일어나지 않는다.**
- `worker.py`에 `mcp-shared.json` 병합용 상수(`SHARED_MCP_CANDIDATES`, `MERGED_MCP_CONFIG`, 43~50행)가 있지만 사용처가 없다(grep 결과 정의 2줄뿐). DOBIS는 `mcp.json`을 직접 고쳐야 한다.

현재 형식(sun-sang, 그대로):

```json
"sun-sang": {
  "type": "stdio",
  "command": "node",
  "args": ["/DEVELOP/DOIL/skills/sun-sang/mcp-server/src/index.js"],
  "env": {}
}
```

`config.json`의 `DOBIS_ALLOWED_TOOLS`는 공백 구분 문자열이고 서버마다 `mcp__<서버이름>__*`가 한 토큰이다(현재 `... mcp__sun-sang__* mcp__ai-echo__* mcp__doil-secretary__* ...`).

추가:

```bash
cd /mnt/wsl/das/dev/DOIL/docker/agent/dobis
cp mcp.json mcp.json.bak-<태그>-$(date +%H%M%S); cp config.json config.json.bak-<태그>-$(date +%H%M%S)   # 이 폴더의 기존 관례(.bak-<태그>-<시각>)
python3 - <<'EOF'
import json
NAME="doil-health"                       # 서버 이름 = 도구 접두 mcp__<NAME>__
p="mcp.json"; d=json.load(open(p))
d["mcpServers"][NAME]={"type":"stdio","command":"node","args":[f"/DEVELOP/DOIL/skills/{NAME}/mcp-server/src/index.js"],"env":{}}
json.dump(d,open(p,"w"),indent=2,ensure_ascii=False); open(p,"a").write("\n")
p="config.json"; c=json.load(open(p)); tok=f"mcp__{NAME}__*"
if tok not in c["DOBIS_ALLOWED_TOOLS"].split(): c["DOBIS_ALLOWED_TOOLS"]+=" "+tok
json.dump(c,open(p,"w"),indent=2,ensure_ascii=False); open(p,"a").write("\n")
EOF
git -C /mnt/wsl/das/dev/DOIL/docker diff --stat -- agent/dobis/mcp.json agent/dobis/config.json
```

(들여쓰기·키 순서가 바뀌면 diff가 커진다. 그럴 때는 파이썬 대신 손으로 한 줄씩 넣는다.)

확인:

```bash
python3 -c 'import json;print("mcp.json OK" if "doil-health" in json.load(open("mcp.json"))["mcpServers"] else "MISSING")'
python3 -c 'import json;print("allowed OK" if "mcp__doil-health__*" in json.load(open("config.json"))["DOBIS_ALLOWED_TOOLS"].split() else "MISSING")'
node probe-mcp.cjs doil-health DOILHEALTH_HOME      # 서버가 실제로 뜨고 tools/list 가 나오는지
# 실사용: DOBIS 챗에서 /reload → 새 세션에서 읽기 도구 하나를 부르게 한다. [미확인: DOBIS 챗 e2e는 인증이 필요해 이번에 실행하지 않았다]
```

제거: `mcp.json`에서 그 키를 지우고, `config.json`의 `mcp__<이름>__*` 토큰을 지운 뒤 DOBIS 챗에서 `/reload`. 이미 떠 있는 상주 세션은 기존 도구를 들고 있다가 유휴 3600초(`SESSION_IDLE`, `worker.py:85`) 뒤 정리된다. 백업 `.bak-*` 파일로 되돌려도 된다.

반영 조건: 워커 재시작은 필요 없다. 세션을 띄울 때마다 `--strict-mcp-config --mcp-config mcp.json --allowedTools <config.json 값>`을 새로 넘긴다(`worker.py:807-811`). `config.json`은 콘솔 `/reload`(`worker.py:2744`)로 다시 읽고, 이미 떠 있는 상주 세션은 새 세션부터 반영된다(`reload()` 주석). 시크릿이 필요한 서버는 `mcp.json`에 쓰지 말고 `.env`로 상속시킨다(ubiq 선례: `.env`의 토큰, `mcp.json`은 git 추적 대상). 스킬 MCP는 비밀이 필요 없다.

### 2-2. doil-console — `config/mcp.advanced.json`

- 파일: `/mnt/wsl/das/dev/DOIL/doil-console/config/mcp.advanced.json`(git 추적, 현재 17개 서버. 문서의 "14개"는 오래된 숫자). 형식은 DOBIS `mcp.json`과 같고 sun-sang 항목이 글자 그대로 같다:

```json
"sun-sang": {
  "type": "stdio",
  "command": "node",
  "args": ["/DEVELOP/DOIL/skills/sun-sang/mcp-server/src/index.js"],
  "env": {}
}
```

- 규칙: 값에 비밀을 쓰지 않는다. 필요하면 `"KEY": "${KEY}"` 자리표시자를 두고 값은 `runtime/mcp.env`(0600, git 제외)에 둔다. runner는 `mcp.env`에서만 확장하고 `process.env`는 읽지 않는다(`agent-runner.js` `expandValue`). 스킬 MCP는 `env: {}`다. 서버는 console의 Node가 PATH 맨 앞이라 `node`로 쓴다. 데이터 홈은 runner가 `HOME`을 넘기므로 `~/.<name>` 기본값이 그대로 풀린다.
- 생성 스크립트 `scripts/install-advanced-runtime.sh --force`는 DOBIS `mcp.json`에서 이 파일을 *통째로 다시 만든다*(npx 핀도 `~/.npm/_npx` 캐시의 최신으로 바꿀 수 있다: 현재 playwright 0.0.81, notion-mcp-server 2.5.2). 그래서 이번 등록은 **손으로 한 항목만 추가**하고, DOBIS `mcp.json`(2-1)을 먼저 맞춰 두면 다음 `--force` 때 같은 결과가 나온다.

추가: 위 JSON 블록(서버 이름·경로만 바꿔)을 `mcpServers`에 넣는다.

확인:

```bash
cd /mnt/wsl/das/dev/DOIL/doil-console
python3 -m json.tool config/mcp.advanced.json >/dev/null && echo "JSON OK"
node probe-mcp.cjs doil-health DOILHEALTH_HOME                       # 항목 그대로 기동 + tools/list (이 파일을 읽는다)
bash scripts/install-advanced-runtime.sh                              # --force 없이: 멱등. 스킬 심링크(2-5b) + 없는 mcp.env 변수 이름 보고
SCRATCH=<임시디렉터리> E2E_SERVER=doil-health E2E_TOOL=<읽기 도구> E2E_HOME_ENV=DOILHEALTH_HOME node e2e-advanced-skill-mcp.cjs   # 5장: 실제 claude로 1회 호출
```

제거: 항목을 지운다(`git checkout -- config/mcp.advanced.json`도 된다). 3번 정책 블록과 함께 지운다.

반영 조건: **재시작 불필요.** runner가 실행(메시지 처리)마다 이 파일을 읽어 `mcp.json`을 새로 렌더링한다(`server/llm/agent-runner.js:540`). 다만 MCP 서버 코드 경로를 "쓰기 금지 경로"로 묶는 `mcpProtectedPaths`는 gate 생성(서비스 시작) 때 한 번만 계산된다(`server/tool-gate.js:101`). 새 경로가 보호 목록에 들어가는 것은 재시작 뒤지만, `/DEVELOP/DOIL/skills`는 정책의 `forbidden_write_roots`에 이미 있어 틈은 없다. 정책이 없는 동안 도구는 모델에게 보여도 default deny다(fail-closed).

### 2-3. doil-console — `config/tool-policy.json` (default deny, 쓰기 툴은 confirm으로 시작)

- 파일: `doil-console/config/tool-policy.json`(git 추적). 최상위 `default: "deny"`, 서버별 블록은 `mcp.<서버이름>`.
- 판정 순서 deny > confirm > auto. 목록에 없는 도구(서버가 나중에 새로 추가한 도구 포함)는 deny다. 도구 이름은 끝에 `*` 하나만 허용하고 `auto`에 맨 `*`는 쓸 수 없다. `high`는 반드시 `confirm`의 부분집합, `elevated`는 `confirm`∩`high`의 부분집합(`server/tool-policy.js` `validateToolPolicy`). 형식이 틀리면 로드가 throw하고 gate가 만들어지지 않아 **advanced 모드 전체가 꺼진다**(passthrough는 영향 없음, `server/app.js:349-355`). 그러니 재시작 전에 아래 검증을 반드시 통과시킨다.
- AGENTS.md: "도구 정책은 default-deny이며 **완화하려면 사용자 확인이 필요하다**". 그래서 새 스킬은 **쓰기 도구를 전부 `confirm`으로 시작**하고, auto로 올리는 것은 사용자가 정한 뒤에 한다.

현재 형식(sun-sang, 그대로 — 정책이 `auto`/`confirm`을 가른 기준):

```json
"sun-sang": {
  "risk": "medium",
  "auto": ["ss_onboard_status", "ss_subject_list", "ss_concept_get", "ss_concept_list", "ss_concept_tree", "ss_docs_get", "ss_docs_list",
           "ss_log_list", "ss_status", "ss_review_candidates", "ss_mirror_status",
           "ss_subject_put", "ss_concept_link", "ss_concept_unlink", "ss_verify_record", "ss_log_add", "ss_docs_put", "ss_onboard_complete"],
  "confirm": ["ss_concept_del", "ss_mirror_config_set", "ss_mirror_sync", "ss_concept_put"],
  "high": ["ss_mirror_sync"]
}
```

(항목은 원본 그대로이고 읽기 쉽게 읽기/쓰기 줄로 나눴다. auto 18개 = 읽기 11 + append성 쓰기 7.) 기존 선례는 **append-only 쓰기는 auto, 덮어쓰기·삭제·외부 전송은 confirm**이고 `test/tool-policy.test.cjs:229-232`가 이를 못박는다(`ss_subject_put` auto, `ss_concept_put`·`sec_node_put`·`echo_guardrail_put` confirm). 신규 스킬은 이 선례보다 **더 보수적으로 시작**한다.

**건강 스킬 권고 (Recommendation / Why / Second look):**
- **Recommendation:** `doil-health` 블록은 `risk: "high"`, 상태·개수만 돌려주는 도구(`*_status`, `*_onboard_status` 류)만 `auto`, **쓰기 도구는 전부 `confirm`, 삭제·내보내기는 `confirm` + `high`**, 원문 기록을 돌려주는 읽기 도구는 사용자가 정하기 전까지 `confirm`(또는 `deny`)으로 둔다.
- **Why (brief):** console 챗봇은 도구 결과를 OmniRoute를 거쳐 외부 LLM에 보낸다. 건강 기록은 읽는 것만으로 PC 밖으로 나간다. 같은 이유로 2026-10-06에 decision 9가 notion-private 데이터의 djinn 읽기·검색 도구를 임시 deny했다(`docs/implementation-status.md:498`).
- **Second look:** 레퍼런스 렌즈 → kept(위 decision 9와 append-auto 선례를 근거로 보수적 쪽을 택함). 도전자 렌즈(Erich Gamma의 관점) → kept: 공개 계약은 "도구 이름 = 정책 키"라 스킬이 도구를 추가할 때마다 정책을 같이 고쳐야 한다(secretary가 실제로 3개 누락) → 6장 체크박스에 `probe`의 `UNLISTED` 0건을 넣었다. 프리모템: confirm 카드가 너무 잦으면 사용자가 무심코 허용 → 읽기를 집계형 도구로 쪼개 auto로 둘 수 있게 설계하도록 스킬 쪽에 권한다. 재적합 렌즈(Andrej Karpathy의 관점) → kept: 규칙은 위 두 줄(쓰기 confirm, 원문 읽기 confirm)뿐이고 새 정책 메커니즘은 만들지 않는다. 최종 정책 완화는 사용자 결정이다 **[미결: 사용자 확인 필요]**.

도구 이름은 스킬 MCP의 `tools/list`에서 가져온다(`probe-mcp.cjs`가 출력). 아래는 형식 예시일 뿐이다 **[미확인: 실제 doil-health 도구 이름 — 예시의 `hl_*`는 가짜]**:

```json
"doil-health": {
  "risk": "high",
  "auto": ["hl_status", "hl_onboard_status"],
  "confirm": ["hl_record_list", "hl_record_get", "hl_record_add", "hl_record_put", "hl_record_del", "hl_export"],
  "high": ["hl_record_del", "hl_export"]
}
```

확인:

```bash
cd /mnt/wsl/das/dev/DOIL/doil-console
node -e '
const {loadToolPolicy,decide}=require("./server/tool-policy");
const policy=loadToolPolicy();                         // 형식·불변식 검증 포함: 틀리면 throw
const ctx={policy,sandboxRoot:"/tmp",appRoot:process.cwd(),home:process.env.HOME,managedPath:()=>false,protectedRoots:[]};
for (const t of process.argv.slice(1)) { const r=decide("mcp__doil-health__"+t,{},ctx); console.log(t.padEnd(24),r.decision,r.risk||""); }
' hl_status hl_record_add hl_record_del hl_unknown_tool            # 기대: auto / confirm / confirm(high) / deny
node probe-mcp.cjs doil-health DOILHEALTH_HOME                    # UNLISTED(=deny) 가 0건이어야 한다
node --test test/tool-policy.test.cjs test/integration/tool-gate.test.cjs test/integration/agent-runner.test.cjs test/integration/system-mcp.test.cjs   # 이번 조사 시점 82/82 통과
```

그리고 `test/tool-policy.test.cjs`의 `MCP: reads auto, side effects confirm...` 블록(229-232행)에 같은 모양의 단정 몇 줄을 추가한다(auto 읽기 1, confirm 쓰기 1, deny 미등록 1).

제거: 블록을 지우고 재시작한다(`allowedToolNames`가 시작 때 한 번 계산되므로 재시작 전까지는 이전 목록이 `--allowedTools`에 남는다).

반영 조건: **console 재시작 필요.** 정책은 `createApp`에서 한 번 로드되고(`server/app.js:352`) `--allowedTools` 목록도 runner 생성 시 한 번 계산된다(`server/llm/agent-runner.js:282`). 재시작은 `systemctl --user restart doil-console`(사용자 systemd, 포트 4174)이다. 진행 중인 대화 작업을 끊고, 터미널 PTY는 `KillMode=process`라 살아남는다(`terminal-lifecycle.conf`). **이번 작업에서는 재시작하지 않았다.** 재시작 전까지 console 챗봇에서 이 스킬 도구는 deny다.

### 2-4. void — 하드코딩 목록이 아니라 `mcp-shared.json`을 권장

사실 확인:

- 하드코딩 목록: `void-ai-launcher/lib/void-persistent/omniMcp.js`의 `serverSpecs()`(94~123행): sun-sang(97), ai-echo(101), doil-secretary(105), void-notify(109), void-context(113), void-dispatch(117). 항목은 `{ name, entry: (skillsDir) => path.join(skillsDir, '<name>', 'mcp-server', 'src', 'index.js') }` 꼴이다.
- 이 목록은 **void-omni-persistent 프로필 런치 때 `--mcp-config` 인라인 JSON으로 주입**될 뿐 `.claude.json`을 건드리지 않는다. 스킬 루트는 `VOID_SKILLS_DIR` → `~/.claude/skills` → `/DEVELOP/DOIL/skills` 순으로 처음 *존재하는* 곳이라(73~78행), 보통 `~/.claude/skills/<이름>` **심링크(2-5b)가 없으면 항목이 조용히 빠진다**(fail-open: 그 서버만 빠지고 나머지는 주입된다).
- 테스트 `test/omniMcp.test.js`가 서버 이름 6종과 개수(6/7)를 단정한다(37~64, 142~181행). 하드코딩 항목을 추가하면 테스트도 고쳐야 한다.
- **void는 두 곳에 있다**: 설치된 `/usr/local/bin/void`는 `/home/doil/workspace/void-ai-launcher/bootstrap.js`를 실행한다. DAS 쪽 `/mnt/wsl/das/dev/DOIL/void-ai-launcher`는 별개 사본이다(inode·디바이스가 다름, 현재 HEAD a64413c와 `omniMcp.js` 내용은 같고 같은 미커밋 변경 포함). DAS 쪽만 고치면 설치된 void에는 반영되지 않는다. console은 DAS 쪽 경로(`/DEVELOP/DOIL/void-ai-launcher/lib/*.js`)를 쓴다.
- 이미 있는 확장점: `~/.config/void-launcher/mcp-shared.json`(현재 colab-mcp 1개). `resolveMcpServers`가 하드코딩 6종에 이 파일의 서버를 덧붙이고(이름이 겹치면 이 파일이 이긴다) omni 프로필 런치 때 주입된다. 일반 프로필은 `void mcp sync --apply`가 `.claude.json`에 병합한다(2-5a).

**Recommendation:** 신규 스킬은 `omniMcp.js`를 고치지 말고 `~/.config/void-launcher/mcp-shared.json`에 넣는다. **Why:** 코드·테스트·두 사본 동기화 없이 omni 프로필과 일반 프로필 둘 다 덮고, 개인 스킬 이름이 void repo 코드에 박히지 않는다. **Second look:** 레퍼런스 렌즈 → changed(초안은 `omniMcp.js` 6→9종 하드코딩이었으나 mcp-shared가 같은 일을 코드 변경 없이 하고 설치본/DAS 사본 이중 문제를 피한다). 도전자 렌즈(Erich Gamma의 관점) → kept: `mcp-shared.json`은 평문이고 모든 프로필의 `.claude.json`에 복사되므로 **비밀 값은 넣지 않는다**(스킬 MCP는 비밀 불필요). `void mcp sync`는 추가·갱신만 하고 **삭제하지 않는다**(제거 절차 필수). 프리모템: `.claude.json`은 Claude Code가 수시로 다시 쓰는 파일이라 실행 중인 프로필에 `--apply`하면 덮어써질 수 있다 → 해당 프로필의 세션이 없을 때 적용(void가 `.claude.json.bak-<시각>`을 남긴다). 재적합 렌즈(Andrej Karpathy의 관점) → kept: 새 메커니즘 없이 기존 확장점 하나만 쓴다.

추가(`mcp-shared.json`의 `mcpServers`에 한 항목):

```json
"doil-health": {
  "type": "stdio",
  "command": "node",
  "args": ["/DEVELOP/DOIL/skills/doil-health/mcp-server/src/index.js"],
  "env": {}
}
```

(하드코딩 방식이 꼭 필요하면: `serverSpecs()`에 `{ name: 'doil-health', entry: (skillsDir) => skillsDir && path.join(skillsDir, 'doil-health', 'mcp-server', 'src', 'index.js') }` 추가 + `test/omniMcp.test.js` 서버 목록·개수 갱신 + **설치된 void가 실행하는 사본**에 적용.)

확인:

```bash
void mcp list                  # 공유 MCP 정의 목록(읽기 전용)
void mcp sync                  # 기본 dry-run: 어느 프로필에 무엇이 추가/갱신될지 출력 (launcher.js:635-676)
```

**[미확인]** 이번 조사에서 `void mcp list`/`sync`를 실행하려 했으나 권한 분류기가 거부해 실행하지 못했다. 코드(`launcher.js` `handleMcpCli`, `lib/sharedMcpSync.js`)상 둘 다 읽기 전용(`sync`는 `--apply`가 있어야 쓴다)이다. 실행 결과는 통합 단계에서 확인한다.

제거: `mcp-shared.json`에서 그 키를 지운다. 이미 동기화된 프로필에서는 2-5a의 `claude mcp remove -s user <이름>`을 프로필마다 실행한다(sync는 지우지 않는다).

반영 조건: omni 프로필은 **다음 런치부터**(런치 시 파일을 읽는다). 일반 프로필은 `void mcp sync --apply` 후 **새 Claude Code 세션부터**.

### 2-5. Claude 프로필 `.claude.json`과 스킬 심링크

**a) `.claude.json`의 `mcpServers`** — 사용자 스코프(최상위 `mcpServers`)에 넣는다. 실제 항목(`~/.claude-wellconn/.claude.json`, sun-sang):

```json
"sun-sang": { "type": "stdio", "command": "node", "args": ["/DEVELOP/DOIL/skills/sun-sang/mcp-server/src/index.js"], "env": {} }
```

현재 등록: `.claude`, `.claude-anon`, `.claude-doil`, `.claude-wellconn`, `.claude-wellconn-user5`에 ai-echo·sun-sang(+doil-context). doil-secretary는 어디에도 없다. 방법 둘 중 하나:

```bash
# (1) 프로필 하나씩: CLAUDE_CONFIG_DIR 로 대상 프로필을 고르고 -s user 로 사용자 스코프에 쓴다
CLAUDE_CONFIG_DIR=$HOME/.claude-wellconn claude mcp add -s user doil-health -- node /DEVELOP/DOIL/skills/doil-health/mcp-server/src/index.js
# (2) 한 번에: 2-4의 mcp-shared.json 에 넣고 모든 '실사용' 프로필(로그인된 프로필)에 병합 — 먼저 dry-run
void mcp sync            # 확인
void mcp sync --apply    # 반영(원본은 .claude.json.bak-<시각>)
```

`claude mcp add`가 쓰는 JSON이 위 기존 항목과 **내용이 같음**을 임시 `CLAUDE_CONFIG_DIR`에서 실측했다(`add`→`list`→`remove`).

확인(프로필별): `CLAUDE_CONFIG_DIR=$HOME/.claude-wellconn claude mcp list` — 서버를 실제로 띄워 `✓ Connected`/`✘ Failed to connect`를 보여 준다(없는 경로로 시험하면 `✘ ... CONNECTION_CLOSED`). 또는 `python3 -c 'import json,os;print(list(json.load(open(os.path.expanduser("~/.claude-wellconn/.claude.json")))["mcpServers"]))'`.

제거(프로필별): `CLAUDE_CONFIG_DIR=$HOME/.claude-wellconn claude mcp remove -s user doil-health`.

반영 조건: **새 Claude Code 세션부터**(실행 중인 세션은 MCP 목록을 시작 때 읽는다). 재시작할 서비스는 없다.

**b) 스킬 심링크(Claude Code CLI용)** — `<profile>/skills/<이름> -> /DEVELOP/DOIL/skills/<이름>`:

| 방법 | 대상 | 비고 |
|------|------|------|
| `skills/install.sh` | 기본은 `$CLAUDE_CONFIG_DIR`(없으면 `~/.claude`) 한 곳. `--all-profiles`는 `settings.json`이 있는 프로필 전부 | `git submodule update --init --recursive`로 서브모듈을 기록된 커밋에 맞추고, `SKILL.md`가 있는 폴더마다 `ln -sfn`. 이어서 **모든 스킬의** `install.sh`(`npm install`·멱등 DB 초기화)를 실행한다 → 신규 스킬의 `install.sh`는 **`npm ci`로 바꿔 둘 것(1-3)** |
| `skills/scripts/link-and-hook-profiles.py` | `~/.claude`, `~/.claude-*` 전부(`settings.json` 없는 것 포함) | 심링크 외에 **모든 `settings.json`에 doil-secretary SessionStart 훅을 주입**한다(중복이면 건너뜀). 경로 `/DEVELOP/DOIL/skills`가 코드에 박혀 있다. `--dry-run`을 먼저(이번 조사에서 실행: 14개 프로필, 훅은 모두 already). `.claude-doil-console` 등 스킬이 필요 없는 프로필에도 링크를 만든다 |
| `doil-console/scripts/install-advanced-runtime.sh` | `doil-console/runtime/claude-config/skills/*` (console advanced runner 전용 프로필) | `--force` 없이도 매번 `SKILL.md` 폴더마다 `ln -sfn`하고 깨진 링크를 정리한다(멱등). 현재 8개 링크 |

권장: Claude Code 쪽은 `skills/install.sh --all-profiles`(훅 부작용 없음), console 쪽은 `install-advanced-runtime.sh`. `link-and-hook-profiles.py`는 훅 주입 부작용 때문에 새 스킬 링크 용도로는 쓰지 않는다.

console advanced 프로필은 `disableSkillShellExecution: true`로 돈다(`agent-runner.js` `hookSettings`). **SKILL.md 안의 인라인 셸 블록은 console 챗에서 실행되지 않는다** — 신규 스킬은 MCP 도구만으로 동작하도록 쓴다.

확인: `ls -l <profile>/skills/<이름>`(링크 대상이 `/DEVELOP/DOIL/skills/<이름>`인지), console은 `ls -l /mnt/wsl/das/dev/DOIL/doil-console/runtime/claude-config/skills/` — 작성기 자동완성 카탈로그는 30초 캐시(`server/skills-catalog.js` `CACHE_MS`)라 재시작 없이 보인다.

제거: `rm <profile>/skills/<이름>`(심링크만 지워진다. 대상 폴더는 그대로). console 쪽은 스킬 폴더를 치운 뒤 `install-advanced-runtime.sh`가 깨진 링크를 정리한다.

## 3. 반영 조건 요약과 적용 순서

| 지점 | 반영 조건 | 근거 |
|------|-----------|------|
| 1 DOBIS `mcp.json` | 새 세션부터. 워커 재시작 불필요 | `worker.py:807-811`(세션 spawn마다 `--mcp-config`), `SESSION_IDLE=3600` |
| 1 DOBIS `config.json` | `/reload` 후 새 세션부터 | `worker.py:162-165, 2744` |
| 2 console `mcp.advanced.json` | 다음 실행부터. 재시작 불필요(보호 경로 목록만 재시작 뒤) | `agent-runner.js:540`, `tool-gate.js:101`, `docs/widgets-runbook.md:30` |
| 3 console `tool-policy.json` | **console 재시작 필요** | `app.js:352`, `agent-runner.js:282` |
| 2-5b console 스킬 링크 | 다음 실행부터(CLI가 시작 때 스캔). 자동완성은 30초 캐시 | `skills-catalog.js` |
| 4·5a void/`.claude.json` | 다음 void 런치(omni) / `sync --apply` 후 새 Claude 세션 | `omniMcp.js`, `sharedMcpSync.js` |

**적용 순서(통합 단계):** (0) 1-2·1-3 설치 검증 → (1) `probe-mcp.cjs`로 도구 목록 확정 → (2) 2-1 DOBIS → (3) 2-2 console MCP + 2-5b console 링크 → (4) 2-3 정책(쓰기 confirm) → (5) 2-4/2-5 void·프로필·링크 → (6) 5장 e2e(재시작 전: 임시 하네스) → (7) **console 재시작은 마지막**(`docs/deploy-checklist-chatbot-platform.md`의 원칙. 사용자 승인 후) → (8) 재시작 후 라이브 smoke.
정책을 *먼저* 넣고 MCP 항목을 *나중에* 넣어도 되고 반대도 된다. 어느 쪽이든 정책이 로드되기 전에는 deny라 위험하지 않다.

**롤백:** 위 제거 절차를 역순으로. 설정 파일은 모두 git 추적(console)이거나 `.bak-*`(DOBIS, `.claude.json`)가 남는다.

## 4. 백업 (데이터 홈)

### 4-1. 무엇이 왜 위험한가 (실측)

- dJinn은 WAL 모드(`this.db.pragma('journal_mode = WAL')`, dJinn `src/db.js:28`)다. 지금 `~/.sun-sang/data/sunsang.db`는 **118,784 B**인데 `-wal`이 **1,075,352 B**다. `.db`만 복사하면 최근 쓰기를 거의 다 잃는다. 샌드박스에서 같은 상황을 만들어 재현했다: 연결이 열린 WAL DB의 본체만 복사하니 `no such table: m`이었고, `sqlite3 .backup`으로 만든 복사본에는 201행이 다 있었다.
- 백업이 전혀 없다: `~/.sun-sang`, `~/.doil-secretary`, ai-echo DB를 백업하는 cron·스크립트가 없다(crontab에는 DDNS·SSL뿐, DAS 이전 계획서도 "백업 정책 미정"). 홈랩 온톨로지의 DAS "백업 정책"도 `unknown`이다.
- ai-echo의 DB는 데이터 홈이 아니라 **스킬 repo 안**(`skills/ai-echo/mcp-server/data/echo.db`, `.gitignore`로 제외)에 있다. 이번에 같이 백업 대상에 넣었다.

### 4-2. 결정 (Second-Look)

**① 암호화 도구**
- **Recommendation:** GnuPG(`gpg` 2.2.19, 설치됨)의 **공개키 방식**. 수신자는 40자리 지문 하나. 아카이브 형식은 `tar` → `gpg --encrypt`(AES256). 평문 폴백 없음.
- **Why (brief):** `age`는 미설치이고 이 서버(Ubuntu 20.04)의 apt에 후보가 없어 바이너리를 따로 받아야 한다. gpg는 이미 있고 복원 도구로 어디서나 구할 수 있다. 공개키 방식은 cron에서 passphrase 없이 암호화되고, 개인키를 서버 밖에 두면 서버가 털려도 과거 백업은 열리지 않는다.
- **Second look:** 레퍼런스 렌즈 → kept(사용자의 saigon_rider 백업 리허설 문서가 "오프사이트 암호화 저장 + restore drill"을 요구 → `--verify` 모드를 만든 이유. `openssl enc`는 비대칭·인증 암호화가 없어 기각). 도전자 렌즈(Erich Gamma의 관점) → **changed**: 초안은 gpg 대칭(passphrase 파일)이었으나 passphrase를 같은 서버에 둬야 해 암호화 이득이 거의 없어 공개키로 바꿨다. 경계·계약: 형식은 표준 OpenPGP라 20년 뒤에도 풀린다. 프리모템: (a) **개인키 분실 = 백업 전부 무용** → `--init-key`가 개인키 export 절차를 안내하고 서버 밖 보관을 요구, (b) cron에서 pinentry/tty를 요구해 조용히 실패 → 공개키 + `--batch --no-tty`, (c) 이름·짧은 ID로 의도치 않은 다중 키 암호화 → 40자리 지문만 허용, (d) 키 만료·폐기 → 사용 불가 키는 거부하고 키는 `never`로 생성, (e) 평문 유출 → 쓴 뒤 `pubkey enc packet` 존재를 검사하고 실패하면 지운다. 운영: cron 계정 = 키링 계정(doil)이어야 한다. 재적합 렌즈(Andrej Karpathy의 관점) → kept: 수신자 모드 하나만 지원, 평문·대칭·age·openssl 병행 없음.

**② 보관 위치**
- **Recommendation:** `/mnt/wsl/das/data/backup/data-homes/<홈이름>/`(스크립트 기본값, `--dest`/`DOIL_BACKUP_DEST`로 변경).
- **Why (brief):** 원본 홈(`/home/doil`, `/dev/sdc`)과 다른 디스크(DAS `/dev/sdd1` ext4, 1.5T 여유, 소유자 doil, 쓰기 가능)다. 후보였던 `/mnt/wsl/das/drive/archive`는 존재하고 쓸 수 있지만(doil:doil 775, 비어 있음) console **드라이브 루트**(`DOIL_DRIVE_ROOT`) 안이라 SFTPGo·UUID 공유·미디어 제공 범위다. 암호문이라도 사용자용 파일 트리에 두지 않는다.
- **Second look:** 레퍼런스 렌즈 → **changed**(초안 `drive/archive` → `data/backup`). DAS 이전 계획서(`docker/ai-docs/das-migration-plan.md:61`)가 `$base/backup`을 데이터와 섞지 않으려 했고 `$base`(`/mnt/wsl/das`)는 root 소유라 만들 수 없어 `data/` 아래로 했다. 기존 cron은 `[ -e /DEVELOP/.das-ok ]` 센티널로 DAS 미마운트를 거른다 → 스크립트도 `/mnt/wsl/das/.das-ok`가 없으면 쓰지 않는다. 도전자 렌즈(Erich Gamma의 관점) → kept, 프리모템: (a) DAS 미마운트 시 마운트 지점 아래 루트 디스크에 조용히 쓰는 사고 → 센티널 검사, (b) **같은 DAS**(dev·drive와 같은 디스크)라 DAS 고장 시 소스 repo와 백업이 함께 사라진다. 원본 홈은 `/dev/sdc`라 일단 분리되지만 **오프사이트 사본은 여전히 없다**(DAS 계획서도 "두 번째 사본 위치 미정"). 암호문이라 PC A나 클라우드로 복사해도 안전하다 → 사용자 결정 **[미결]**, (c) 권한 → 디렉터리 0700, 파일 0600, 스테이징은 `/dev/shm` 0700. SMB 공유가 `drive`를 포함하는지는 **[미확인]**(그래서 `drive/` 밖으로 뺐다). 재적합 렌즈(Andrej Karpathy의 관점) → kept: 기본 위치 하나, 나머지는 `--dest`.

**③ 포함 범위와 보존**
- 포함: doil-health(필수 암호화), doil-portfolio, doytale(`data/` 만), **sun-sang·doil-secretary·ai-echo도 포함**. 이유: 셋 다 사용자 개인 데이터이고 복구 수단이 없으며(복사본 1.2~1.3 MB, 비용 거의 0), 같은 암호화 경로를 쓰므로 추가 모드가 없다. `secrets/`(Notion 키 암호문과 그 AES 키)도 포함한다 — 둘이 같이 있어야 복원이 되고 아카이브가 암호화돼 있다.
- 보존: **최근 14개 + 월별 대표 6개**(매일 cron 기준 2주 + 6개월). 새 파일이 이전과 같은 내용이면 만들지 않는다. Second look: 도전자 렌즈 → kept(늦게 발견되는 손상 시나리오에 월별 층이 필요, 비용은 월 1개), 재적합 렌즈 → kept(단일 개수로 줄이면 3주 뒤 발견되는 문제를 못 되돌림; 추가 코드 약 10줄).

### 4-3. 스크립트

`/mnt/wsl/das/dev/DOIL/skills/scripts/backup-data-homes.sh` (실행 권한 있음, 의존: sqlite3 3.31.1, gpg, rsync, tar, flock, sha256sum — 모두 설치됨 확인).

| 홈 | 기본 경로(`<NAME>_HOME`로 오버라이드) | 범위 |
|----|------------------------------------------|------|
| doil-health | `~/.doil-health` (`DOILHEALTH_HOME`) | 전체 |
| doil-portfolio | `~/.doil-portfolio` (`DOILPORTFOLIO_HOME`) | 전체 |
| doytale | `~/.doytale` (`DOYTALE_HOME`) | `data/` 만 |
| sun-sang | `~/.sun-sang` (`SUNSANG_HOME`) | 전체 |
| doil-secretary | `~/.doil-secretary` (`DOILSECRETARY_HOME`) | 전체 |
| ai-echo | `<skills>/ai-echo/mcp-server/data` | `backup/` 제외 |

없는 홈은 건너뛴다. 신규 3개의 환경변수 이름과 디렉터리 구조는 **[미확인]**이다(스킬이 아직 없음). 스킬의 실제 이름·구조가 정해지면 스크립트 상단 `HOME_TABLE`의 한 줄만 고친다. 공통 제외: `node_modules/ .git/ .cache/ cache/ tmp/ *.log *.sock *.pid *-wal *-shm *-journal`.

동작: 홈마다 ① 비-SQLite 파일은 rsync로 스테이징(심링크는 링크 그대로, 권한 보존) ② SQLite(헤더가 `SQLite format 3`인 `*.db/*.sqlite/*.sqlite3`)는 `sqlite3 -readonly ... .backup`(온라인 백업 API, 쓰는 중에도 일관)으로 복사 → `journal_mode=DELETE`로 단일 파일화 → `PRAGMA integrity_check`가 `ok`여야 함 ③ 이름+SHA-256 매니페스트의 지문(12자)을 만든다 ④ 최근 보관 파일과 지문이 같으면 건너뜀(멱등) ⑤ `tar | gpg --encrypt`를 `.partial`로 쓰고 `pubkey enc packet`을 확인한 뒤 `mv`(원자적) ⑥ 보존 정책 적용(규칙에 맞는 이름만 삭제). 홈 하나가 실패해도 나머지는 계속하고 종료 코드 3으로 끝난다.

| 명령(전부 한 줄) | 하는 일 |
|------|---------|
| `scripts/backup-data-homes.sh --dry-run` | 계획만 출력, 아무것도 쓰지 않음(dest도 만들지 않음) |
| `scripts/backup-data-homes.sh --init-key` | 백업용 gpg 키 생성(대화형 passphrase). 이미 있으면 지문만 출력. 개인키 export 절차 안내 |
| `DOIL_BACKUP_GPG_RECIPIENT=<지문> scripts/backup-data-homes.sh` | 실제 백업. 수신자 없으면 종료 코드 2로 거부(평문 안 씀) |
| `scripts/backup-data-homes.sh --list` | 보관 목록 |
| `scripts/backup-data-homes.sh --verify <파일>` | 복호화(개인키 필요)+매니페스트+SQLite 무결성 = 복원 리허설 |
| `scripts/backup-data-homes.sh --print-cron` | crontab 한 줄 출력(등록 안 함) |

옵션: `--dest DIR --recipient 지문 --homes a,b --keep-recent N --keep-monthly M`. 종료 코드: 0 성공 / 1 환경·사용법 오류 / 2 수신자 미설정 / 3 일부 홈 실패.

**처음 한 번(사용자 작업, 개인키는 서버 밖에):**

```bash
/mnt/wsl/das/dev/DOIL/skills/scripts/backup-data-homes.sh --init-key      # 키 생성 + 지문 출력 + 개인키 export 안내
# 출력된 gpg --export-secret-keys ... 를 실행해 개인키를 비밀번호 관리자·USB 등 서버 밖에 보관한다. 이 키가 없으면 복원 불가.
```

**복원:**

```bash
S=/mnt/wsl/das/dev/DOIL/skills/scripts/backup-data-homes.sh
$S --list                                              # 시점 고르기
$S --verify <파일>                                     # 먼저 리허설(임시 위치에서만 풀고 지운다)
mkdir -p ~/restore-tmp && gpg --decrypt <파일> | tar -x -C ~/restore-tmp     # 풀린 <홈이름>/ 확인
# 해당 스킬을 쓰는 세션·console 작업이 없을 때: mv ~/.<홈> ~/.<홈>.broken-$(date +%F) && cp -a ~/restore-tmp/<홈> ~/.<홈>
```

doytale는 `data/`만 보관하므로 홈 전체를 `mv`하지 말고 `~/.doytale/data`만 되돌린다. ai-echo는 홈이 아니라 `skills/ai-echo/mcp-server/data/`로 복원한다.

복원된 SQLite는 단일 파일(`journal_mode=DELETE`)이고 dJinn이 열 때 다시 WAL로 바꾼다. 복원 후 `~/restore-tmp`는 지운다(평문).

**cron 등록 방법(이번에는 등록하지 않았다):**

```bash
# 한 줄로 등록(이미 있으면 같은 스크립트의 줄을 교체, 멱등)
S=/mnt/wsl/das/dev/DOIL/skills/scripts/backup-data-homes.sh; L="$(DOIL_BACKUP_GPG_RECIPIENT=<지문40자리> $S --print-cron | grep -v '^#')"; ( crontab -l 2>/dev/null | grep -vF "$S"; echo "$L" ) | crontab -
```

`--print-cron`이 출력하는 줄은 `30 3 * * * [ -e /DEVELOP/.das-ok ] && DOIL_BACKUP_GPG_RECIPIENT=<지문> <스크립트> >> "$HOME/.cache/doil-backup.log" 2>&1`이다(지문을 주지 않고 `--print-cron`을 실행하면 자리표시자 `<FINGERPRINT-40hex>`가 들어가니 위처럼 지문을 같이 준다). cron 데몬은 active다. 로그 파일은 느리게 늘지만 비우는 장치가 없다. **실패 알림은 아직 없다**(종료 코드 3이 로그에만 남는다) — void-notify 연동은 후속 과제 **[미결]**.

### 4-4. 검증 결과

실제 환경 dry-run(2026-10-18, `scripts/backup-data-homes.sh --dry-run`): **종료 코드 0, 아무것도 쓰지 않음**(dest 미생성, `/dev/shm` 잔여 0).

```
dest: /mnt/wsl/das/data/backup/data-homes (없음 → 실행 시 0700 으로 생성)   recipient: 미설정
[doil-health] 건너뜀 ... 없음 / [doil-portfolio] 건너뜀 / [doytale] 건너뜀
[sun-sang]       SQLite 1개: data/sunsang.db (WAL 1075352 B — 파일 복사였다면 유실될 양)
[doil-secretary] SQLite 1개: data/secretary.db (WAL 1062992 B ...)
[ai-echo]        SQLite 1개: echo.db (WAL 543872 B ...), 제외: backup
SUMMARY(dry-run): 대상 홈 3개, 없어서 건너뜀 3개, 아무것도 쓰지 않았다
PENDING: 실제 실행 전에 해결할 것 1건 — 수신자(암호화 키): 미설정  → ... --init-key
dry-run OK
```

`PENDING`(수신자 미설정)은 환경 오류가 아니라 "아직 키를 만들기 전" 상태라 dry-run은 성공으로 끝나고, 실제 실행만 거부된다(종료 코드 2). 환경 오류(도구 없음, DAS 센티널 없음, dest 쓰기 불가)는 dry-run도 실패시킨다.

**추가로, 격리된 샌드박스에서 실제 실행까지 검증했다**(요청은 dry-run만이었으나 암호화·복원 경로는 dry-run으로 검증되지 않아서 했다. 가짜 HOME·임시 `GNUPGHOME`(테스트용 키)·임시 dest만 썼고 운영 홈·운영 키링·실제 dest에는 쓰지 않았다. 데이터는 합성 또는 스킬 `init-db.js`를 임시 홈에 실행한 것):

| 시험 | 결과 |
|------|------|
| dry-run(수신자 있음) | 아무것도 쓰지 않음, 종료 0 |
| 수신자 없이 실제 실행 | 종료 2, dest 미생성 |
| 실제 실행(연결이 열린 WAL DB) | 4개 홈 저장, 파일 0600·디렉터리 0700, `/dev/shm` 잔여 0 |
| 재실행(변경 없음) | 4개 모두 "변경 없음", 새 파일 0(**멱등**) |
| 데이터 1행 변경 후 | 그 홈만 새 아카이브, 나머지 건너뜀 |
| `--verify` | 복호화·매니페스트·`integrity_check` 통과 |
| 복원 비교 | WAL 안에만 있던 행 포함 201행 일치, `-wal`/`-shm` 없음, 심링크·`secrets/` 0700 보존 |
| 포함·제외 | doytale는 `data/`만(`cache/`·`other/` 없음), ai-echo는 `backup/` 제외 |
| 평문 누출 | 아카이브에서 평문 문자열 0건 |
| 손상 SQLite | 그 홈만 FAIL, 나머지 계속, 종료 3, `.partial`·스테이징 잔여 0 |
| 수신자 검증 | 짧은 ID·키링에 없는 지문 거부 |
| 보존 정책(KEEP 3 + 월 2, 합성 파일명) | 기대대로 삭제, 규칙에 안 맞는 파일은 그대로 |
| 동시 실행 | 잠금으로 거부(종료 1) |

미검증: 실제 데이터 홈에 대한 실제 백업(키가 없어 실행하지 않음), 신규 3개 스킬의 실제 구조, 대용량 데이터(`/dev/shm` 스테이징은 홈 크기 전체를 메모리에 두므로 수 GB 단위가 되면 `DOIL_BACKUP_TMPDIR`를 바꿔야 한다), 실패 알림.

## 5. console e2e

근거: `doil-console/docs/implementation-status.md:15`와 `:163`, `docs/deploy-checklist-chatbot-platform.md:29`는 "14개 MCP 서버를 붙인 e2e 미검증"이라고 쓴다. 건강 스킬의 console 챗 연동이 이 경로에 의존한다.

### 5-1. 결과

**PASS (2회 실행). 운영 서비스·운영 데이터는 바꾸지 않았다.**

방법: console의 시험용 하네스(`test/helpers/advanced-harness.cjs`)로 **임시 DB·임시 sandbox·임시 `CLAUDE_CONFIG_DIR`** 위에 실제 앱(tool-gate 포함)을 띄우고, 실제 `claude` CLI(2.1.302)와 실제 OmniRoute 프로필(`void-omni`, 모델 `claude/claude-sonnet-5`)로 advanced runner를 1번 실행한다. MCP 서버 정의는 **운영 `config/mcp.advanced.json`의 그 항목 그대로**이고 차이는 데이터 홈 환경변수를 임시 디렉터리로 돌린 것뿐이다. 스크립트는 5-3에 있다.

| 실행 | 서버·도구(정책) | 결과 |
|------|----------------|------|
| 1 | `sun-sang` / `ss_status`(auto, 읽기) | `availability: ready`, 6.3초, `tool_activity`: running → done, `tool_gate_audit`: `allow "Allowed by policy."`, 모델 답변 "빈 객체({}) 반환", 임시 데이터 홈에 `sunsang.db`가 생겨 MCP 프로세스가 실제로 떴음 |
| 2 | `doil-secretary` / `sec_status`(auto, 읽기) | 5.4초, running → done, `allow`, "노드 없음·연체 0건", 임시 홈에 `secretary.db` 생성 |

- LLM 비용: advanced runner 실행 **2회**(각 약 5~6초, 도구 1회).
- 운영에 영향 없음 확인: console 서비스 PID 28106·시작 시각(2026-10-17 00:15:19) 불변, 운영 DB의 `tool_gate_audit` 46행·`conversation_jobs` 38행 불변, console repo에서 내 실행으로 바뀐 파일 없음(최근 45분 안에 바뀐 파일은 동시에 진행 중인 다른 작업이 만든 `docs/design-music.md` 하나뿐), `~/.sun-sang`·`~/.doil-secretary`는 쓰지 않았다(WAL 수정 시각 불변). 재시작하지 않았고 라이브 서비스로 요청도 보내지 않았다.
- 같이 한 정적·무비용 확인:
  - **`tools/list` ↔ 정책 대조**(서버를 임시 홈으로 띄워 실측): sun-sang 22/22 일치(auto 18, confirm 4), doil-secretary 22개 중 **3개가 정책에 없음**(`sec_clear_cache`, `sec_complete`, `sec_memo_update` → default deny). ai-echo는 데이터 DB가 repo 안이라 서버를 띄우지 않고 소스를 정적 대조: 29/29 일치.
  - 기존 console 시험: `node --test test/tool-policy.test.cjs test/integration/agent-runner.test.cjs test/integration/system-mcp.test.cjs test/integration/tool-gate.test.cjs` → **82개 중 82 통과**(가짜 `claude`, 모델 호출 없음).
- 운영 감사 기록(읽기 전용 집계): 라이브 서비스는 2026-10-17 00:15:20에 "advanced runtime registered", advanced 작업 21건 성공·3건 실패. 스킬 MCP 호출은 `doil-secretary` confirm 3건(허용 2·거부 1, 2026-10-16)뿐이고 sun-sang·ai-echo·secretary 읽기(auto) 호출 기록은 없다 → **운영에서 스킬 MCP 읽기 경로가 실제로 쓰인 증거는 아직 없었다**. 이번 e2e가 그 첫 증거다.

### 5-2. 아직 검증되지 않은 것

- 서버 17개 중 이번에 e2e로 건드린 것은 2개(sun-sang, doil-secretary). 나머지 15개(playwright, orrery, notion, drec, doil-mcp, djinn, dgraph, ai-echo, void-*, ubiq, console 내장 3종)는 그대로 미검증이다. 문서의 "14개"는 오래된 숫자이고 `implementation-status.md:15,163`·`deploy-checklist-chatbot-platform.md:29`는 이번에 고치지 않았다(읽기 전용).
- 사용자 UI 경로(로그인·CSRF·기기 게이트·승인 카드): 실행하지 않았다. 라이브 서비스에 요청을 보내려면 로그인 세션이 필요하다.
- **confirm 쓰기 도구의 승인 카드 흐름**: 이번에는 auto 읽기만 확인했다. 건강 스킬은 쓰기 도구가 confirm으로 시작하므로 재시작 뒤 UI에서 한 번 확인해야 한다.
- 막힌 이유: 없음(하네스로 안전하게 실행됨). 다만 라이브 서비스로의 검증은 로그인 없이 불가능해 하지 않았다.

### 5-3. 재실행 절차와 스크립트(신규 스킬용)

```bash
# 사전: 등록 2-2(mcp.advanced.json)와 1-2·1-3(설치 검증) 완료. 정책(2-3)은 하네스가 현재 파일을 읽는다.
# 임시 디렉터리를 하나 만들어 SCRATCH 로 준다. 정책이 auto 인 읽기 도구 1개만 쓴다.
cd /mnt/wsl/das/dev/DOIL/doil-console
SCRATCH=<임시디렉터리> E2E_SERVER=doil-health E2E_TOOL=<읽기 도구> E2E_HOME_ENV=DOILHEALTH_HOME node <e2e-advanced-skill-mcp.cjs 경로>
```

기대 출력: `availability: {"state":"ready",...}`, `outcome: {"ok":true,...}`, `tool_activity`에 running→done, `tool_gate_audit`에 `allow`, `temp skill home created by the MCP process: true`. 정책이 `confirm`인 도구는 승인 카드를 기다리는데 이 하네스에는 승인자가 없어 **시간 초과로 끝나는 것이 정상**이다 — 그런 도구와 승인 흐름은 재시작 뒤 UI에서 확인한다. 그래서 건강 스킬은 `auto`인 상태·개수 도구(예: `*_status`)로 이 e2e를 한다. 한 번 실행에 LLM 1회가 든다.

```js
"use strict";
// Hermetic e2e (1 real LLM run): advanced runner -> real `claude` CLI -> real sun-sang MCP server (read tool ss_status)
// -> ToolPolicy/tool-gate hook. Everything is temporary: temp console DB, temp sandbox, temp CLAUDE_CONFIG_DIR and a
// TEMP data home for the skill (SUNSANG_HOME). The live service (127.0.0.1:4174), its DB and ~/.sun-sang are not touched.
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const REPO = "/mnt/wsl/das/dev/DOIL/doil-console";
const SERVER = process.env.E2E_SERVER || "sun-sang";
const TOOL = process.env.E2E_TOOL || "ss_status";
// 새 스킬은 E2E_HOME_ENV 로 데이터 홈 환경변수 이름을 준다(예: DOILHEALTH_HOME). 임시 디렉터리를 가리키게 해 운영 데이터 홈을 건드리지 않는다.
const HOME_ENV = process.env.E2E_HOME_ENV || { "sun-sang": "SUNSANG_HOME", "doil-secretary": "DOILSECRETARY_HOME" }[SERVER];
if (!HOME_ENV) throw new Error("E2E_HOME_ENV 필요(스킬의 데이터 홈 환경변수 이름)");
process.chdir(REPO); // like `npm test`
const { harness } = require(path.join(REPO, "test/helpers/advanced-harness.cjs"));
const { loadOmniRouteProfile } = require(path.join(REPO, "server/llm/omniroute-profile.js"));

(async () => {
  const tmp = fs.mkdtempSync(path.join(process.env.SCRATCH || os.tmpdir(), "e2e-"));
  const skillHome = path.join(tmp, "skill-home");
  // The REAL template entry, plus the data-home override as the only difference.
  const real = JSON.parse(fs.readFileSync(path.join(REPO, "config/mcp.advanced.json"), "utf8")).mcpServers[SERVER];
  if (!real) throw new Error(`server ${SERVER} not in config/mcp.advanced.json`);
  const template = path.join(tmp, "mcp.e2e.json");
  fs.writeFileSync(template, JSON.stringify({ mcpServers: { [SERVER]: { ...real, env: { ...(real.env || {}), [HOME_ENV]: skillHome } } } }, null, 2));

  const h = await harness({
    runnerOptions: {
      command: path.join(process.env.HOME, ".local/bin/claude"),
      environment: { PATH: process.env.PATH, HOME: process.env.HOME, DOIL_CONSOLE_LLM_OMNI_PROFILE: "void-omni" },
      profileLoader: loadOmniRouteProfile,
      mcpTemplatePath: template,
      idleMs: 120_000,
      hardCapMs: 300_000,
    },
  });
  const events = [];
  let outcome;
  try {
    const avail = await h.runner.checkAvailability();
    console.log("availability:", JSON.stringify(avail));
    if (avail.state !== "ready") throw new Error("runner not ready: " + JSON.stringify(avail));
    const { claim } = await h.createJob(`This is a connectivity test. Call the MCP tool ${TOOL} of the ${SERVER} server exactly once (no arguments), then answer in one short Korean sentence stating what it returned. Do not call any other tool except what is needed to load that tool.`);
    const started = Date.now();
    try {
      const result = await h.runner.run({ ...claim, model: "claude/claude-sonnet-5", effort: "low" }, { onDelta() {}, onEvent: (type, payload) => events.push({ type, payload }) }).promise;
      outcome = { ok: true, ms: Date.now() - started, text: String(result?.output?.text ?? JSON.stringify(result)).slice(0, 400) };
    } catch (error) {
      outcome = { ok: false, ms: Date.now() - started, code: error.code, message: String(error.message).slice(0, 300) };
    }
    const audit = h.runtime.db.prepare("SELECT tool, server, decision, reason FROM tool_gate_audit ORDER BY created_at").all();
    console.log("outcome:", JSON.stringify(outcome));
    console.log("tool_activity events:", JSON.stringify(events.filter((e) => e.type === "tool_activity").map((e) => ({ tool: e.payload.tool, server: e.payload.server, state: e.payload.state }))));
    console.log("tool_gate_audit:", JSON.stringify(audit));
    const dataDir = path.join(skillHome, "data");
    console.log("temp skill home created by the MCP process:", fs.existsSync(dataDir), fs.existsSync(dataDir) ? fs.readdirSync(dataDir).join(",") : "");
  } finally {
    await h.close();
    fs.rmSync(tmp, { recursive: true, force: true });
  }
})().catch((e) => { console.error("E2E ERROR:", e.message); process.exitCode = 1; });
```

## 6. 이번 조사에서 발견한 어긋남과 미해결

신규 스킬 등록 전에 사용자가 알아야 할 것(수정하지 않았다 — 쓰기 범위 밖):

1. **doil-secretary `node_modules`의 dJinn이 핀(e4c751b)이 아니라 0.1.2다.** `sec_clear_cache`가 이 환경에서 실패한다. 수리: `cd skills/doil-secretary/mcp-server && npm ci`. sun-sang·ai-echo·doil-supervise는 핀(3eacee5)과 설치가 일치한다.
2. **doil-secretary가 어떤 Claude 프로필 `.claude.json`에도 없다**(CLI 세션에서 MCP 도구 없음). DOBIS·console·void omni에는 있다.
3. **console 정책에 doil-secretary 도구 3개 누락**: `sec_clear_cache`, `sec_complete`, `sec_memo_update`(console 챗봇에서 deny). 쓰기 성격이라 추가한다면 confirm으로 시작하는 것이 이 문서의 원칙이다.
4. **README의 서브모듈 서술 오류**(1-1): ai-echo·doil-secretary는 서브모듈이고 d-tools·explain-diff가 표에 없다.
5. **void가 두 사본**(2-4): 설치된 `void`는 `~/workspace/void-ai-launcher`를 실행한다. DAS 사본과 따로 드리프트할 수 있다.
6. **`worker.py`의 `DOBIS_ALLOWED_TOOLS` 기본값이 `config.json`과 어긋남**(`ToolSearch`, `mcp__ubiq__*` 누락). 실제 영향은 없으나 혼동 소지(2-1).
7. **`link-and-hook-profiles.py`는 스킬 링크 외에 SessionStart 훅을 주입하고 경로가 박혀 있다**(2-5b).
8. **오프사이트 백업 사본·백업 실패 알림은 아직 없다**(4-2②, 4-3).
9. 문서 갱신 대상(읽기 전용이라 하지 않음): console `implementation-status.md:15,163`·`deploy-checklist-chatbot-platform.md:29`의 "14개 e2e 미검증"(이번 2개 확인, 서버는 17개).

체크박스(신규 스킬 1개당):

- [ ] 서브모듈 장착 + README 표 갱신(1-1)
- [ ] dJinn `e4c751b` 핀, `npm ci`, 설치 검증 `DRIFT` 없음(1-2, 1-3)
- [ ] 데이터 홈 환경변수 이름 확정 → 백업 `HOME_TABLE`·e2e `E2E_HOME_ENV`에 반영(1-1, 4-3)
- [ ] `probe-mcp.cjs`로 도구 목록 확정, 정책 `UNLISTED` 0건(2-3)
- [ ] 1 DOBIS `mcp.json` + `config.json` + `/reload`(2-1)
- [ ] 2 console `mcp.advanced.json`(2-2)
- [ ] 3 console `tool-policy.json`(쓰기 confirm) + 시험 추가(2-3)
- [ ] 4·5a `mcp-shared.json` + `void mcp sync`(또는 `claude mcp add -s user`)(2-4, 2-5a)
- [ ] 5b 스킬 심링크(Claude 프로필 + console `runtime/claude-config/skills`)(2-5b)
- [ ] 5장 하네스 e2e 통과
- [ ] (사용자 승인 후) console 재시작 → UI에서 읽기·confirm 쓰기 도구 확인
- [ ] 백업: 키 생성(`--init-key`)·개인키 서버 밖 보관·`--dry-run`·`--verify` 리허설·cron 등록
