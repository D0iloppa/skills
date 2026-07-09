# skills

[Claude Code](https://claude.com/claude-code) 스킬 **집계 repo**. 각 스킬은 **독립 repo**이며
여기에 **서브모듈**로 장착된다. 개별 스킬만 따로 clone/설치할 수도, 이 repo로 한 번에 받을 수도 있다.

## 수록 스킬

| 스킬 | repo | 설명 |
|------|------|------|
| [`doil-research`](https://github.com/D0iloppa/doil-research) | `D0iloppa/doil-research` | 다중 출처 심층 리서치 오케스트레이션(Opus 계획·판단 / Sonnet 서브에이전트 크롤링), raw-first 수집, 순차·세션간 이어받기(핸드오프 md) |
| [`doil-bootstrap`](https://github.com/D0iloppa/doil-bootstrap) | `D0iloppa/doil-bootstrap` | Doness 보일러플레이트 기반 신규 프로젝트 부트스트랩 — ① 범용 코어(클론·아키결정·문서/카파시 init·격리 repo) + ② 배선 층(공개 템플릿 + private 오버레이 스크립트 주입) |

## 설치

```bash
git clone --recurse-submodules https://github.com/D0iloppa/skills.git
cd skills
./install.sh          # 각 스킬(서브모듈)을 <config>/skills/ 로 심볼릭 링크
```

`install.sh`는 서브모듈을 내려받은 뒤, `CLAUDE_CONFIG_DIR`(없으면 `~/.claude`)의 `skills/`에
`SKILL.md`가 있는 스킬 디렉토리를 각각 링크한다. (링크만 걸므로 서브모듈에서 편집하면 즉시 반영)

## 새 스킬 추가

스킬을 독립 repo로 만든 뒤 서브모듈로 장착한다.

```bash
git submodule add https://github.com/<owner>/<skill>.git <skill>
git commit -m "add <skill> submodule"
```

## 서브모듈 갱신 (스킬 최신화)

```bash
git submodule update --remote --merge        # 각 스킬 repo 최신 커밋으로
git commit -am "bump skills"
```
