#!/usr/bin/env bash
# 이 repo의 스킬(서브모듈)을 Claude Code 스킬 디렉토리로 심볼릭 링크한다.
# 각 스킬은 독립 repo이며 여기에 서브모듈로 장착돼 있다.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CONFIG_DIR/skills"

# 서브모듈 내려받기(최초/갱신)
git -C "$REPO_DIR" submodule update --init --recursive

mkdir -p "$DEST"
for skill in "$REPO_DIR"/*/; do
  name="$(basename "$skill")"
  [ -f "${skill}SKILL.md" ] || continue   # SKILL.md 있는 디렉토리만 = 스킬
  ln -sfn "${skill%/}" "$DEST/$name"
  echo "linked: $DEST/$name -> ${skill%/}"
done

echo "done. config dir: $CONFIG_DIR"
