# sun-sang (선생)

탑다운(top-down) + 파인만 학습법 기반 AI 학습 튜터 Claude Code 스킬. **알려주는 것이
끝이 아니다** — 사용자가 자기 말로 설명한 것을 AI가 개념 노드의 rubric 기준으로
검증(verify)해 "체득" 여부를 판정하는 것이 핵심이다. 자세한 절차는
[`SKILL.md`](./SKILL.md) 참고.

## 설치

```bash
./install.sh                 # 스킬 심볼릭 링크 + mcp-server npm install + 데이터 홈 초기화까지 한 번에
./install.sh --all-profiles  # ~ 아래 모든 Claude 프로필에 설치
```

MCP는 선택이지만 권장이다(없으면 SKILL.md의 세션 내 임시 진행 폴백). 수동으로 하려면:

```bash
cd mcp-server
npm install
npm run init   # 데이터 홈(기본 ~/.sun-sang)에 init/init.sql로 스키마+빈 카탈로그를 시드(멱등)
```

Claude Code MCP 설정(`~/.claude/settings.json` 등)에 stdio 서버로 등록:

```json
{
  "mcpServers": {
    "sun-sang": {
      "command": "node",
      "args": ["/absolute/path/to/sun-sang/mcp-server/src/index.js"]
    }
  }
}
```

또는 `claude mcp add sun-sang -- node /absolute/path/to/sun-sang/mcp-server/src/index.js`.

## 데이터는 이 repo 밖에 산다

**git(이 skills repo)은 스킬 코드 공유용일 뿐이다.** 학습 데이터는 학습자에 귀속되며
워크스페이스·repo와 무관하게 관리된다 — 스킬 repo를 재클론하거나 코드를 업데이트해도
학습 데이터는 그대로 보존된다. 그래서 데이터는 스킬 설치경로(`sun-sang/`)가 아니라
**데이터 홈**에 저장된다.

- **데이터 홈**: 기본값 `~/.sun-sang`. `SUNSANG_HOME` 환경변수로 오버라이드 가능. 서버
  최초 기동 시 하위 디렉토리가 없으면 자동 생성된다.
  - `~/.sun-sang/data/sunsang.db` — 지식트리/검증기록/docs 인덱스/미러 매핑의 실물 저장소.
  - `~/.sun-sang/docs/` — 학습 자료 원문 보관소(dJinn에는 요약+연결 개념 인덱스만 둔다).
  - `~/.sun-sang/secrets/` — Notion API 키 암호화용 keyfile(AES-256-GCM, chmod 600,
    서버 최초 실행 시 자동 생성). WSL이라도 `/mnt/c` 같은 drvfs 마운트가 아니라 리눅스
    네이티브 파일시스템(홈 디렉토리)이라 chmod 600이 실제로 적용된다.
  - `~/.sun-sang/onboard.lock` — 온보딩 완료 마커. 존재하면 온보딩 완료로 간주한다.
- **repo(`sun-sang/`) 안에는 코드만 남는다.** `mcp-server/data/`, `mcp-server/secrets/`,
  `docs/`, `onboard.lock` 등은 정상 동작 시 이 repo 안에 생기지 않는다. `.gitignore`에
  해당 패턴이 남아있는 건(예: `mcp-server/data/`, `*.db*`) 오설정·구버전 실행 등으로
  혹시 데이터가 repo 안에 생기는 사고를 막는 안전망이다.

## 스키마

```
ss_catalog        // root, 1-row(id='root'). { subjects:{slug:{name,description}}, created_at, modified_at }
ss_profile        // root, 1-row(id='root'). { background, goals, explain_pref, onboarded_at, created_at, modified_at }
ss_concept        // 개념 노드. id="<subject>::<slug>"(전역 유일).
                   // { id, subject, name, description(canonical 설명), rubric:[체득 인정 핵심 포인트],
                   //   verify_state:'unverified'|'withheld'|'failed'|'passed', last_verified_at(passed/failed
                   //   시각만 갱신), parent(계층 edge — 선수/포함, 최상위면 null), doc_refs:[path,...],
                   //   refs:[{concept_key, note?}](비계층 edge — parent/children과 완전히 별개인 연관 참조),
                   //   created_at, modified_at }
ss_log            // 학습기록(append). { id, subject, concept_id, event:'learn'|'verify'|'ask', payload, created_at }
ss_docs           // docs 인덱스. id=path(데이터 홈 docs/ 기준 상대경로). { path, summary, linked_concepts:[concept_id,...], created_at, modified_at }
ss_mirror_map     // node_id <-> Notion page_id 매핑(멱등 push용). id=node_id.
                   // { node_id, notion_page_id, last_pushed_at }
ss_mirror_config  // root, 1-row(id='root'). { base_url, provider, encrypted_api_key:{iv,tag,ciphertext},
                   //   last_push, failures:[...], created_at, modified_at }
```

숙련도는 `verify_state` 4상태(`unverified`/`withheld`/`failed`/`passed`)로 관리한다
(간격반복·점수화 없음). **개념·자료의 영속화(description/rubric/doc_refs)는
verify_state와 완전히 무관하며 절대 휘발되지 않는다** — verify는 그 위에 얹히는 별도의
상태 축일 뿐이다. `last_verified_at`은 `passed`/`failed`로 실제 rubric 판정이 난
시각만 갱신하고, `withheld`(근거 부족으로 판정 보류)는 갱신하지 않는다. 재검증/복습
제안은 `review` 커맨드를 수동 호출했을 때만 나온다(자동 스케줄 없음). 인덱스:
`ss_concept`(subject/parent/verify_state/modified_at), `ss_log`(subject/concept_id/event/created_at),
그 외는 각각 modified_at 기준.

## 툴

| 툴 | 용도 |
|---|---|
| `ss_onboard_status` | onboard.lock 존재 여부 + 저장된 학습자 프로파일 + 데이터 홈 경로(data_home/docs_dir) 조회 |
| `ss_onboard_complete` | 학습자 프로파일 저장 + onboard.lock 생성 |
| `ss_subject_put` | 과목 카탈로그 upsert |
| `ss_subject_list` | 과목 카탈로그 전체 조회 |
| `ss_concept_put` | 개념 노드 upsert(description+rubric+refs 전체 교체 가능) — 성공 후 미러링 best-effort 자동 push |
| `ss_concept_get` | 개념 노드 하나 조회 |
| `ss_concept_list` | 개념 노드 목록(subject/parent/verify_state 필터) |
| `ss_concept_tree` | 과목 하나의 지식트리(계층 edge) + cross_refs(비계층 edge) 조회 |
| `ss_concept_link` | 개념 간 비계층 참조(refs) 하나 추가/갱신(중복 없이 upsert) |
| `ss_concept_unlink` | 개념 간 비계층 참조(refs) 하나 제거 |
| `ss_concept_del` | 개념 노드 삭제 |
| `ss_verify_record` | verify 시도 결과 기록(result: passed/failed/withheld) — verify_state·last_verified_at(passed/failed만) 갱신 + 근거(rationale)·인용 근거(evidence_rubric_points/evidence_doc_refs)를 세션 로그에 기록. 성공 후 미러링 best-effort 자동 push |
| `ss_log_add` | learn/ask 이벤트를 세션 로그에 append |
| `ss_log_list` | 세션 로그 조회(subject/concept_id/limit 필터) |
| `ss_docs_put` | docs 인덱스 항목 upsert |
| `ss_docs_get` | docs 인덱스 항목 하나 조회 |
| `ss_docs_list` | docs 인덱스 전체 목록 |
| `ss_status` | 과목별 verify_state 4상태(unverified/withheld/failed/passed) + total 집계 |
| `ss_review_candidates` | 복습 큐 — unverified/withheld/failed 개념을 우선, 그다음 passed 중 오래된 것을 채운다. 수동 호출 전용 |
| `ss_mirror_config_set` | Notion base_url + api_key 설정(키는 즉시 암호화, ok만 반환) |
| `ss_mirror_status` | 미러링 상태 조회(configured/base_url/last_push/failures만, 키 없음) |
| `ss_mirror_sync` | 수동 전체 재동기화 |

자세한 사용 규칙(온보딩, 파인만 검증 루프, 데이터 홈 원칙, 미러링 보안 원칙)은
[`SKILL.md`](./SKILL.md) 참고.
