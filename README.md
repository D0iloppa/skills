# claude-skills

범용 [Claude Code](https://claude.com/claude-code) 스킬 모음. 각 스킬은 `skills/<이름>/SKILL.md`
하위 폴더 하나로, 어느 환경에서든(특정 도메인 인프라에 의존하지 않고) 동작하도록 작성한다.

## 수록 스킬

| 스킬 | 설명 |
|------|------|
| [`doil-research`](skills/doil-research/) | 다중 출처 심층 리서치를 오케스트레이션(Opus 계획·판단 / Sonnet 서브에이전트 크롤링), raw-first 수집, 순차·세션간 이어받기(핸드오프 md) 방식으로 수행 |

## 설치

각 스킬을 개인 Claude Code 스킬 디렉토리로 심볼릭 링크한다.

```bash
git clone https://github.com/D0iloppa/claude-skills.git
cd claude-skills
./install.sh          # skills/* 를 <config>/skills/ 로 심볼릭 링크
```

`install.sh`는 `CLAUDE_CONFIG_DIR`(없으면 `~/.claude`)의 `skills/`에 각 스킬을 링크한다.
repo를 정본으로 두고 링크만 걸므로, 여기서 편집하면 즉시 반영된다.

## 새 스킬 추가

`skills/<이름>/SKILL.md`(+ 필요시 `references/`)를 만들고 커밋. `install.sh` 재실행이면 설치 끝.
