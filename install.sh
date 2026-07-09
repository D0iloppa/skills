#!/usr/bin/env bash
# skills/* 를 Claude Code 스킬 디렉토리로 심볼릭 링크한다.
# 정본은 이 repo. 링크만 걸므로 repo에서 편집하면 즉시 반영된다.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CONFIG_DIR/skills"

mkdir -p "$DEST"

for skill in "$REPO_DIR"/skills/*/; do
  name="$(basename "$skill")"
  ln -sfn "${skill%/}" "$DEST/$name"
  echo "linked: $DEST/$name -> ${skill%/}"
done

echo "done. config dir: $CONFIG_DIR"
