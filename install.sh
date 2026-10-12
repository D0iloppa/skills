#!/usr/bin/env bash
# 이 repo의 스킬(서브모듈)을 Claude Code 스킬 디렉토리로 심볼릭 링크한다.
# 각 스킬은 독립 repo이며 여기에 서브모듈로 장착돼 있다.
#
# 사용법:
#   ./install.sh                 # 기본: $CLAUDE_CONFIG_DIR(없으면 ~/.claude)에 링크 및 설치
#   ./install.sh --all-profiles  # ~ 아래 모든 Claude 프로필(settings.json 보유)에 링크
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 서브모듈 내려받기(최초/갱신)
git -C "$REPO_DIR" submodule update --init --recursive

link_into() { # $1 = target config dir
  local dest="$1/skills"
  mkdir -p "$dest"
  for skill in "$REPO_DIR"/*/; do
    local name
    name="$(basename "$skill")"
    [ -f "${skill}SKILL.md" ] || continue   # SKILL.md 있는 디렉토리만 = 스킬
    ln -sfn "${skill%/}" "$dest/$name"
    echo "linked: $dest/$name -> ${skill%/}"
  done
}

if [ "${1:-}" = "--all-profiles" ]; then
  found=0
  for cfg in "$HOME"/.claude "$HOME"/.claude-*; do
    [ -d "$cfg" ] || continue
    [ -f "$cfg/settings.json" ] || continue
    link_into "$cfg"
    found=$((found + 1))
  done
  echo "done. linked into $found profile(s)."
else
  CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  link_into "$CONFIG_DIR"
  echo "done. config dir: $CONFIG_DIR"
fi

# 각 스킬 디렉토리의 추가 설치 스크립트 실행 (DB 초기화, node_modules 설치 등)
for skill in "$REPO_DIR"/*/; do
  if [ -f "${skill}install.sh" ]; then
    echo "--- Setting up $(basename "$skill") ---"
    (cd "$skill" && bash "./install.sh" "$@")
  fi
done

