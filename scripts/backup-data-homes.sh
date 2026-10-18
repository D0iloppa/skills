#!/usr/bin/env bash
# backup-data-homes.sh — 스킬 데이터 홈을 일관성 있게 백업하고 gpg 공개키로 암호화해 DAS에 보관한다.
#
# 대상(존재하지 않는 홈은 건너뜀):
#   doil-health    ~/.doil-health      (건강 — 암호화 필수. spool/ 은 제외: HAE 수신 임시 파일, raw/ 에 원본 사본이 남는다)
#   doil-portfolio ~/.doil-portfolio
#   doytale        ~/.doytale          (data/ 만)
#   sun-sang       ~/.sun-sang
#   doil-secretary ~/.doil-secretary
#   ai-echo        <skills>/ai-echo/mcp-server/data   (홈이 아니라 repo 안(.gitignore)에 있는 DB)
#   각 홈의 경로는 스킬이 쓰는 <NAME>_HOME 환경변수(SUNSANG_HOME, DOILSECRETARY_HOME, ...)가 있으면 그것을 따른다.
#
# 안전 규칙
#   - SQLite 는 파일 복사가 아니라 `sqlite3 .backup`(온라인 백업 API)으로 복사한다. dJinn 은 WAL 모드라
#     .db 만 복사하면 -wal 에 있는 최근 쓰기를 잃는다. 복사본은 PRAGMA integrity_check 를 통과해야 보관한다.
#   - 암호화 없이는 아무것도 쓰지 않는다(평문 폴백 없음). 수신자(gpg 공개키 지문)가 없으면 실제 실행은 거부(종료 코드 2).
#   - 평문 스테이징은 /dev/shm(메모리, 0700)에서만 하고 종료 시 항상 지운다. 보관 파일은 0600, 디렉터리는 0700.
#   - 같은 내용이면 새 파일을 만들지 않는다(멱등). 보존 정책은 최근 N개 + 월별 대표 M개.
#   - cron 등록은 하지 않는다. `--print-cron` 으로 줄만 출력한다.
#
# 사용법 (자세한 설명: skills/docs/new-skill-checklist.md 의 "백업" 절)
#   backup-data-homes.sh --dry-run             # 계획만 출력(아무것도 쓰지 않음)
#   backup-data-homes.sh                       # 실제 백업 (DOIL_BACKUP_GPG_RECIPIENT 필요)
#   backup-data-homes.sh --init-key            # 백업용 gpg 키 생성(대화형, 이미 있으면 지문만 출력)
#   backup-data-homes.sh --list                # 보관된 백업 목록
#   backup-data-homes.sh --verify <파일>       # 복호화(개인키 필요) + 매니페스트·무결성 검사(복원 리허설)
#   backup-data-homes.sh --print-cron          # crontab 한 줄 출력(등록은 하지 않음)
# 옵션: --dest DIR  --recipient FPR  --homes a,b  --keep-recent N  --keep-monthly M
# 환경: DOIL_BACKUP_DEST, DOIL_BACKUP_GPG_RECIPIENT(40자리 지문), DOIL_BACKUP_KEEP_RECENT(14),
#       DOIL_BACKUP_KEEP_MONTHLY(6), DOIL_BACKUP_TMPDIR(/dev/shm)
# 종료 코드: 0 성공 / 1 사용법·환경 오류 / 2 수신자 미설정(실제 실행 거부) / 3 일부 홈 실패
set -euo pipefail
umask 077

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SKILLS_ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

DEFAULT_DEST="/mnt/wsl/das/data/backup/data-homes"
DAS_ROOT="/mnt/wsl/das"
DAS_SENTINEL="$DAS_ROOT/.das-ok"
KEY_UID="doil-backup (data homes)"

DEST="${DOIL_BACKUP_DEST:-$DEFAULT_DEST}"
RECIPIENT="${DOIL_BACKUP_GPG_RECIPIENT:-}"
KEEP_RECENT="${DOIL_BACKUP_KEEP_RECENT:-14}"
KEEP_MONTHLY="${DOIL_BACKUP_KEEP_MONTHLY:-6}"
STAGE_BASE="${DOIL_BACKUP_TMPDIR:-/dev/shm}"
DRY=0
MODE=run
ONLY=""
VERIFY_FILE=""

# name|env var(홈 경로 오버라이드)|기본 경로|포함 하위 디렉터리(비면 전체)|제외 하위 경로(쉼표)
HOME_TABLE=(
  "doil-health|DOILHEALTH_HOME|$HOME/.doil-health||spool"
  "doil-portfolio|DOILPORTFOLIO_HOME|$HOME/.doil-portfolio||"
  "doytale|DOYTALE_HOME|$HOME/.doytale|data|"
  "sun-sang|SUNSANG_HOME|$HOME/.sun-sang||"
  "doil-secretary|DOILSECRETARY_HOME|$HOME/.doil-secretary||"
  "ai-echo|-|$SKILLS_ROOT/ai-echo/mcp-server/data||backup"
)
# 모든 홈에 공통으로 제외(재생성 가능·잡음). WAL/SHM/journal 은 .backup 이 일관된 본체로 대신한다.
COMMON_EXCLUDES=("node_modules/" ".git/" ".cache/" "cache/" "tmp/" "*.log" "*.sock" "*.pid" "*-wal" "*-shm" "*-journal")

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { local code="$1"; shift; printf 'ERROR: %s\n' "$*" >&2; exit "$code"; }

usage() { sed -n '2,/^set -euo/p' "$SELF" | sed '$d' | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- 인자
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --dest) DEST="${2:?--dest 값 필요}"; shift ;;
    --recipient) RECIPIENT="${2:?--recipient 값 필요}"; shift ;;
    --homes) ONLY="${2:?--homes 값 필요}"; shift ;;
    --keep-recent) KEEP_RECENT="${2:?}"; shift ;;
    --keep-monthly) KEEP_MONTHLY="${2:?}"; shift ;;
    --list) MODE=list ;;
    --verify) MODE=verify; VERIFY_FILE="${2:?--verify 파일 필요}"; shift ;;
    --init-key) MODE=init-key ;;
    --print-cron) MODE=print-cron ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die 1 "알 수 없는 인자: $1" ;;
  esac
  shift
done

case "$KEEP_RECENT" in ''|*[!0-9]*) die 1 "--keep-recent 는 1 이상의 정수" ;; esac
case "$KEEP_MONTHLY" in ''|*[!0-9]*) die 1 "--keep-monthly 는 0 이상의 정수" ;; esac
[ "$KEEP_RECENT" -ge 1 ] || die 1 "--keep-recent 는 1 이상이어야 한다(최신 백업은 항상 남긴다)"
case "$DEST" in *"'"*) die 1 "경로에 작은따옴표 사용 불가: $DEST" ;; esac

need() { command -v "$1" >/dev/null 2>&1 || die 1 "필요한 도구가 없다: $1"; }

# ---------------------------------------------------------------- 홈 해석
# resolve <row> → name root include exclude
resolve_row() {
  local row="$1" name envvar def inc exc root
  IFS='|' read -r name envvar def inc exc <<<"$row"
  root="$def"
  if [ "$envvar" != "-" ] && [ -n "${!envvar:-}" ]; then root="${!envvar}"; fi
  ROW_NAME="$name"; ROW_ROOT="$root"; ROW_INC="$inc"; ROW_EXC="$exc"
}

selected() { # 이름이 --homes 선택에 포함되는가
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

is_sqlite() { [ "$(head -c 15 "$1" 2>/dev/null || true)" = "SQLite format 3" ]; }

# sqlite_list <root> <include> → 포함 범위 안의 SQLite 파일의 root 기준 상대경로(줄 단위, 정렬)
sqlite_list() {
  local root="$1" inc="$2" base f
  local -a bases=()
  if [ -n "$inc" ]; then
    local s; for s in ${inc//,/ }; do [ -d "$root/$s" ] && bases+=("$root/$s"); done
  else
    bases=("$root")
  fi
  [ "${#bases[@]}" -gt 0 ] || return 0
  for base in "${bases[@]}"; do
    find "$base" \( -name node_modules -o -name .git \) -prune -o -type f \
      \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) -print0
  done | sort -z | while IFS= read -r -d '' f; do
    is_sqlite "$f" && printf '%s\n' "${f#"$root"/}"
  done
}

# ---------------------------------------------------------------- gpg
check_recipient() { # 0=사용 가능, 1=미설정, 2=키 문제
  [ -n "$RECIPIENT" ] || return 1
  [[ "$RECIPIENT" =~ ^[0-9A-Fa-f]{40}$ ]] || { RECIPIENT_MSG="수신자는 40자리 지문이어야 한다(이름·짧은 ID 금지: 여러 키로 암호화될 수 있다)"; return 2; }
  local colons
  colons="$(gpg --batch --no-tty --with-colons --list-keys "$RECIPIENT" 2>/dev/null)" || { RECIPIENT_MSG="키링에 그 지문이 없다"; return 2; }
  if ! awk -F: '($1=="pub"||$1=="sub") && $2 !~ /^[redi]$/ && $12 ~ /e/ {ok=1} END{exit ok?0:1}' <<<"$colons"; then
    RECIPIENT_MSG="암호화 가능한 유효 키(만료·폐기 아님)가 없다"; return 2
  fi
  return 0
}

latest_digest() { # 그 홈의 가장 최근 보관 파일의 내용 지문
  local dir="$DEST/$1" f
  [ -d "$dir" ] || return 0
  f="$(ls -1 "$dir" 2>/dev/null | grep -E "^$1-[0-9]{8}-[0-9]{6}-[0-9a-f]{12}\.tar\.gpg$" | sort | tail -n 1 || true)"
  [ -n "$f" ] || return 0
  f="${f%.tar.gpg}"; printf '%s' "${f##*-}"
}

# prune_plan <name> → 지울 파일 이름(줄 단위). 새 파일이 이미 있다고 보고 계산한다.
prune_plan() {
  local name="$1" dir="$DEST/$1" i=0 months_kept=0 f m
  local -a files=()
  declare -A seen=()
  [ -d "$dir" ] || return 0
  while IFS= read -r f; do files+=("$f"); done < <(ls -1 "$dir" 2>/dev/null | grep -E "^$name-[0-9]{8}-[0-9]{6}-[0-9a-f]{12}\.tar\.gpg$" | sort -r || true)
  for f in "${files[@]+"${files[@]}"}"; do
    i=$((i + 1)); m="${f#"$name"-}"; m="${m:0:6}"
    if [ "$i" -le "$KEEP_RECENT" ]; then seen[$m]=1; continue; fi
    if [ -z "${seen[$m]:-}" ] && [ "$months_kept" -lt "$KEEP_MONTHLY" ]; then seen[$m]=1; months_kept=$((months_kept + 1)); continue; fi
    printf '%s\n' "$f"
  done
}

# ---------------------------------------------------------------- 모드: init-key / print-cron / list / verify
if [ "$MODE" = init-key ]; then
  need gpg
  existing="$(gpg --batch --no-tty --with-colons --fingerprint --list-keys "$KEY_UID" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}' || true)"
  if [ -z "$existing" ]; then
    log "백업용 gpg 키를 만든다(passphrase 입력 프롬프트가 뜬다). 개인키는 복원 때만 필요하다."
    gpg --quick-generate-key "$KEY_UID" default default never
    existing="$(gpg --batch --no-tty --with-colons --fingerprint --list-keys "$KEY_UID" | awk -F: '/^fpr/{print $10; exit}')"
  else
    log "이미 키가 있다(새로 만들지 않음)."
  fi
  log "지문: $existing"
  log "  → export DOIL_BACKUP_GPG_RECIPIENT=$existing   (crontab 에는 --print-cron 출력 사용)"
  log "개인키 보관(필수, 복원은 개인키 없이는 불가능하다):"
  log "  gpg --export-secret-keys --armor $existing > <오프라인 매체>/doil-backup-secret.asc"
  log "  키가 이 서버 하나에만 있으면 서버 손실 때 백업도 못 연다. 위 파일을 서버 밖(비밀번호 관리자·USB)에 둘 것."
  exit 0
fi

if [ "$MODE" = print-cron ]; then
  fpr="${RECIPIENT:-<FINGERPRINT-40hex>}"
  log "# crontab -e 에 붙여 넣는다(이 스크립트는 등록하지 않는다). DAS 미마운트 시 건너뛰도록 sentinel 확인."
  log "30 3 * * * [ -e /DEVELOP/.das-ok ] && DOIL_BACKUP_GPG_RECIPIENT=$fpr $SELF >> \"\$HOME/.cache/doil-backup.log\" 2>&1"
  exit 0
fi

if [ "$MODE" = list ]; then
  for row in "${HOME_TABLE[@]}"; do
    resolve_row "$row"; selected "$ROW_NAME" || continue
    d="$DEST/$ROW_NAME"
    [ -d "$d" ] || { log "$ROW_NAME: (보관 없음)"; continue; }
    log "$ROW_NAME:"
    ls -l --time-style=long-iso "$d" 2>/dev/null | awk '$NF ~ /\.tar\.gpg$/ {printf "  %s %s %10d  %s\n", $6, $7, $5, $NF}'
  done
  exit 0
fi

if [ "$MODE" = verify ]; then
  need gpg; need tar; need sqlite3; need sha256sum
  [ -f "$VERIFY_FILE" ] || die 1 "파일이 없다: $VERIFY_FILE"
  [ -d "$STAGE_BASE" ] || die 1 "스테이징 위치가 없다: $STAGE_BASE"
  VS="$(mktemp -d "$STAGE_BASE/doil-backup-verify.XXXXXX")"
  trap 'rm -rf "$VS"' EXIT
  log "복호화(개인키 passphrase 를 물을 수 있다)..."
  gpg --decrypt "$VERIFY_FILE" | tar -x -C "$VS"
  (cd "$VS" && sha256sum --quiet -c MANIFEST.sha256) || die 3 "매니페스트 해시 불일치"
  log "매니페스트 해시: 일치"
  bad=0
  while IFS= read -r -d '' f; do
    if is_sqlite "$f"; then
      r="$(sqlite3 -readonly "$f" 'PRAGMA integrity_check;' 2>&1 | head -n 1)"
      if [ "$r" = ok ]; then log "  sqlite ok: ${f#"$VS"/}"; else log "  sqlite FAIL: ${f#"$VS"/} ($r)"; bad=1; fi
    fi
  done < <(find "$VS" -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) -print0)
  [ "$bad" -eq 0 ] || die 3 "SQLite 무결성 실패"
  log "VERIFY OK: $VERIFY_FILE"
  exit 0
fi

# ---------------------------------------------------------------- 모드: run (백업 / dry-run)
need sqlite3; need gpg; need tar; need rsync; need sha256sum; need flock; need find

# 환경 점검 — 틀리면 dry-run 도 실패시킨다(환경 오류). 수신자 미설정은 "아직 설정 전"이라 PENDING 으로 보고한다.
case "$DEST" in
  "$DAS_ROOT"/*) [ -e "$DAS_SENTINEL" ] || die 1 "DAS 센티널($DAS_SENTINEL)이 없다 — 마운트 확인 전에는 쓰지 않는다" ;;
esac
if [ -e "$DEST" ]; then
  [ -d "$DEST" ] && [ -w "$DEST" ] || die 1 "보관 위치가 디렉터리가 아니거나 쓸 수 없다: $DEST"
else
  anc="$DEST"; while [ ! -e "$anc" ]; do anc="$(dirname "$anc")"; done
  [ -d "$anc" ] && [ -w "$anc" ] || die 1 "보관 위치를 만들 수 없다($anc 쓰기 불가): $DEST"
fi
[ -d "$STAGE_BASE" ] && [ -w "$STAGE_BASE" ] || die 1 "스테이징 위치를 쓸 수 없다: $STAGE_BASE (DOIL_BACKUP_TMPDIR)"

PENDING=0
RECIPIENT_MSG=""
rc=0; check_recipient || rc=$?
case "$rc" in
  0) RECIPIENT_STATE="사용 가능(지문 ${RECIPIENT:0:8}…${RECIPIENT: -8})" ;;
  1) RECIPIENT_STATE="미설정"; PENDING=$((PENDING + 1)) ;;
  *) RECIPIENT_STATE="문제: $RECIPIENT_MSG"; PENDING=$((PENDING + 1)) ;;
esac

log "== backup-data-homes $( [ "$DRY" -eq 1 ] && echo '[DRY-RUN: 아무것도 쓰지 않는다]' || echo '[실행]' )"
log "dest:      $DEST $( [ -d "$DEST" ] && echo '(있음)' || echo '(없음 → 실행 시 0700 으로 생성)' )"
log "staging:   $STAGE_BASE (평문, 종료 시 삭제)"
log "recipient: $RECIPIENT_STATE"
log "retention: 최근 $KEEP_RECENT 개 + 월별 대표 $KEEP_MONTHLY 개"
log ""

if [ "$DRY" -eq 0 ]; then
  [ "$rc" -eq 0 ] || die 2 "암호화 수신자가 준비되지 않았다(${RECIPIENT_MSG:-DOIL_BACKUP_GPG_RECIPIENT 미설정}). 평문으로는 쓰지 않는다. 먼저: $SELF --init-key"
  mkdir -p -m 700 "$DEST"
  LOCK_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}"; mkdir -p "$LOCK_DIR"
  exec 9>"$LOCK_DIR/doil-backup-data-homes.lock"
  flock -n 9 || die 1 "다른 백업이 실행 중이다"
  STAGE=""
  cleanup() { [ -n "$STAGE" ] && rm -rf "$STAGE"; return 0; }
  trap cleanup EXIT
fi

n_ok=0; n_skip_missing=0; n_unchanged=0; n_fail=0; n_dry=0

backup_one() { # 현재 ROW_* 변수 사용
  local name="$ROW_NAME" root="$ROW_ROOT" inc="$ROW_INC" exc="$ROW_EXC"
  local -a dbs=()
  local rel f

  while IFS= read -r rel; do [ -n "$rel" ] && dbs+=("$rel"); done < <(sqlite_list "$root" "$inc")
  # 제외 하위 경로의 DB 는 대상이 아니다
  if [ -n "$exc" ]; then
    local -a kept=(); local e skip
    for rel in "${dbs[@]+"${dbs[@]}"}"; do
      skip=0; for e in ${exc//,/ }; do case "$rel" in "$e"/*) skip=1 ;; esac; done
      [ "$skip" -eq 0 ] && kept+=("$rel")
    done
    dbs=("${kept[@]+"${kept[@]}"}")
  fi

  if [ "$DRY" -eq 1 ]; then
    local size; size="$(du -sk "$root" 2>/dev/null | cut -f1)"
    log "[$name] 대상: $root (약 ${size:-?} KiB)${inc:+, 포함: $inc}${exc:+, 제외: $exc}"
    log "  SQLite ${#dbs[@]}개 → sqlite3 .backup + integrity_check 후 보관:"
    for rel in "${dbs[@]+"${dbs[@]}"}"; do
      local wal=""; [ -s "$root/$rel-wal" ] && wal=" (WAL $(stat -c %s "$root/$rel-wal") B — 파일 복사였다면 유실될 양)"
      log "    - $rel$wal"
    done
    local ld; ld="$(latest_digest "$name")"
    log "  최근 보관 지문: ${ld:-(없음)} — 실행 시 내용 지문이 같으면 새 파일을 만들지 않는다"
    local p; p="$(prune_plan "$name" || true)"
    if [ -n "$p" ]; then log "  보존 정책상 삭제될 파일:"; sed 's/^/    - /' <<<"$p"; else log "  삭제될 파일: 없음"; fi
    n_dry=$((n_dry + 1)); return 0
  fi

  # ---- 실제 실행 (이 함수는 `if ! backup_one` 으로 불려 set -e 가 꺼진다 → 중요 명령마다 명시적으로 실패 처리)
  for rel in "${dbs[@]+"${dbs[@]}"}"; do
    case "$rel" in *"'"*) log "[$name] FAIL: 작은따옴표가 든 경로는 지원하지 않는다: $rel"; return 1 ;; esac
  done
  STAGE="$(mktemp -d "$STAGE_BASE/doil-backup.XXXXXX")" || return 1
  local content="$STAGE/$name"; mkdir -p "$content" || return 1

  # 1) 비-SQLite 파일 복사(rsync 필터: 제외 규칙이 먼저, 그다음 포함 하위 디렉터리, 나머지 제외)
  local filter="$STAGE/.filter" p e
  : > "$filter"
  for rel in "${dbs[@]+"${dbs[@]}"}"; do printf -- '- /%s\n' "$rel" >> "$filter"; done
  for p in "${COMMON_EXCLUDES[@]}"; do printf -- '- %s\n' "$p" >> "$filter"; done
  if [ -n "$exc" ]; then for e in ${exc//,/ }; do printf -- '- /%s/\n' "$e" >> "$filter"; done; fi
  if [ -n "$inc" ]; then
    for e in ${inc//,/ }; do printf -- '+ /%s/***\n' "$e" >> "$filter"; done
    printf -- '- /*\n' >> "$filter"
  fi
  rsync -a --filter="merge $filter" "$root/" "$content/" || { log "[$name] FAIL: rsync"; return 1; }

  # 2) SQLite: 온라인 백업 → 단일 파일화(journal_mode=DELETE, -wal/-shm 제거) → 무결성 검사
  local out
  for rel in "${dbs[@]+"${dbs[@]}"}"; do
    mkdir -p "$content/$(dirname "$rel")" || return 1
    sqlite3 -readonly "$root/$rel" -cmd '.timeout 15000' ".backup main '$content/$rel'" \
      || { log "[$name] FAIL: .backup 실패: $rel"; return 1; }
    sqlite3 "$content/$rel" 'PRAGMA journal_mode=DELETE;' >/dev/null \
      || { log "[$name] FAIL: journal_mode 변경 실패: $rel"; return 1; }
    rm -f "$content/$rel-wal" "$content/$rel-shm"
    out="$(sqlite3 -readonly "$content/$rel" 'PRAGMA integrity_check;' 2>&1 | head -n 1)"
    [ "$out" = ok ] || { log "[$name] FAIL: integrity_check=$out ($rel)"; return 1; }
  done

  # 3) 매니페스트와 내용 지문(이름+해시만, 시각·소유자 제외)
  ( cd "$STAGE" && find "$name" -type f -print0 | sort -z | xargs -0 -r sha256sum > MANIFEST.sha256 ) \
    || { log "[$name] FAIL: 매니페스트 생성"; return 1; }
  local digest; digest="$(sha256sum "$STAGE/MANIFEST.sha256" | cut -c1-12)"
  if [ "$(latest_digest "$name")" = "$digest" ]; then
    log "[$name] 변경 없음(지문 $digest) — 건너뜀"
    n_unchanged=$((n_unchanged + 1))
  else
    mkdir -p -m 700 "$DEST/$name" || return 1
    local ts file partial; ts="$(date +%Y%m%d-%H%M%S)"
    file="$DEST/$name/$name-$ts-$digest.tar.gpg"; partial="$file.partial"
    if ! tar --sort=name --owner=0 --group=0 --numeric-owner -C "$STAGE" -cf - "$name" MANIFEST.sha256 \
         | gpg --batch --no-tty --yes --trust-model always --cipher-algo AES256 --encrypt --recipient "$RECIPIENT" -o "$partial"; then
      rm -f "$partial"; log "[$name] FAIL: tar|gpg"; return 1
    fi
    # 평문이 새지 않았는지: 공개키 암호화 패킷이 있어야 한다
    if ! gpg --batch --no-tty --list-packets "$partial" 2>/dev/null | grep -q '^:pubkey enc packet:'; then
      rm -f "$partial"; log "[$name] FAIL: 암호화 패킷을 확인하지 못했다"; return 1
    fi
    [ -s "$partial" ] || { rm -f "$partial"; log "[$name] FAIL: 빈 출력"; return 1; }
    chmod 600 "$partial" && mv "$partial" "$file" || { rm -f "$partial"; log "[$name] FAIL: 확정(mv)"; return 1; }
    log "[$name] 저장: $file ($(stat -c %s "$file") B, DB ${#dbs[@]}개)"
    n_ok=$((n_ok + 1))
  fi

  # 4) 보존 정책(이 홈의 규칙에 맞는 이름만 건드린다)
  local old; while IFS= read -r old; do
    [ -n "$old" ] || continue
    rm -f -- "$DEST/$name/$old"; log "[$name] 보존 정책으로 삭제: $old"
  done < <(prune_plan "$name" || true)

  rm -rf "$STAGE"; STAGE=""
  return 0
}

for row in "${HOME_TABLE[@]}"; do
  resolve_row "$row"
  selected "$ROW_NAME" || continue
  if [ ! -d "$ROW_ROOT" ]; then
    log "[$ROW_NAME] 건너뜀: $ROW_ROOT 없음"
    n_skip_missing=$((n_skip_missing + 1)); continue
  fi
  if ! backup_one; then
    n_fail=$((n_fail + 1)); [ -n "${STAGE:-}" ] && { rm -rf "$STAGE"; STAGE=""; }
  fi
done

log ""
if [ "$DRY" -eq 1 ]; then
  log "SUMMARY(dry-run): 대상 홈 ${n_dry}개, 없어서 건너뜀 ${n_skip_missing}개, 아무것도 쓰지 않았다"
  [ "$PENDING" -eq 0 ] || log "PENDING: 실제 실행 전에 해결할 것 ${PENDING}건 — 수신자(암호화 키): $RECIPIENT_STATE  → $SELF --init-key"
  log "dry-run OK"
  exit 0
fi
log "SUMMARY: 저장 ${n_ok}, 변경 없음 ${n_unchanged}, 없어서 건너뜀 ${n_skip_missing}, 실패 ${n_fail}"
[ "$n_fail" -eq 0 ] || exit 3
exit 0
