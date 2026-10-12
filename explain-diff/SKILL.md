---
name: explain-diff
description: 코드 변경(diff/브랜치/PR)을 배경·직관·코드워크스루·퀴즈 섹션을 갖춘 리치 설명 콘텐츠로 만들어줄 때 사용한다. 출력 형식은 커맨드로 라우팅한다 — `html`(자체완결 HTML 파일)과 `notion`(Notion 페이지, Notion MCP 필요) 두 가지를 지원한다. "이 diff/PR/브랜치 설명해줘", "코드 변경 설명 만들어줘", "explain this diff/PR" 류에서 트리거된다.
---

# Explain Diff

지정된 코드 변경(diff, 브랜치, PR 등)을 리치하고 인터랙티브한 설명 콘텐츠로 만드는 스킬이다. 출력 형식에 따라 두 가지 커맨드로 나뉜다.

## 커맨드

- `html` — 자체완결 HTML 파일로 출력. 상세 지침: [references/explain-diff-html.md](references/explain-diff-html.md)
- `notion` — Notion 페이지로 출력(Notion MCP 도구 필요). 상세 지침: [references/explain-diff-notion.md](references/explain-diff-notion.md)

## 라우팅 규칙

1. 사용자가 "html", "노션", "notion", "페이지로" 등 형식을 명시하면 해당 커맨드로 바로 라우팅한다.
2. 형식이 명시되지 않았다면:
   - Notion MCP 도구(`mcp__*Notion*__*` 등)가 현재 세션에 연결되어 있고 사용자가 평소 Notion을 문서 저장처로 쓰는 맥락이면 `notion`을 제안하되, 확실치 않으면 짧게 물어본다.
   - 그 외에는 `html`을 기본값으로 사용한다.
3. 라우팅이 결정되면 해당 reference 파일의 지침을 그대로 따른다 — 두 파일 모두 Background / Intuition / Code / Quiz 4개 섹션과 다이어그램·퀴즈 요구사항을 공유하며, 출력 형식과 저장 위치만 다르다.

## 공통 원칙 (두 커맨드 모두 적용)

- 대상 diff/PR과 관련된 기존 코드를 폭넓게 탐색해서 배경을 설명한다. 독자의 사전 지식 수준을 모른다고 가정하고, 초심자용 심화 배경(스킵 가능 표시) + 변경에 직접 관련된 좁은 배경을 함께 제공한다.
- 핵심 직관은 완전한 디테일이 아니라 본질을 전달하는 데 집중하고, 토이 데이터를 활용한 구체적 예시와 다이어그램을 적극 사용한다.
- 코드 변경은 이해하기 쉬운 순서/그룹으로 하이레벨 워크스루한다.
- 퀴즈는 5문항, 실제로 PR 내용을 이해해야 풀 수 있는 중간 난이도(가짓수 트릭 지양)로, 각 선택지마다 정답/오답 이유를 설명한다.
- Martin Kleppmann 스타일의 명료하고 매끄러운 문체로 작성한다.
