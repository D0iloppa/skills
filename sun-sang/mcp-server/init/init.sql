-- sun-sang mcp-server 초기화 SQL.
--
-- 이 파일은 두 가지를 한다:
--   1. 테이블/인덱스 DDL — djinn.define()이 서버 시작 시마다 하는 것과 동일(멱등).
--      다만 djinn이 collection을 내부 상태에 등록해야 get/find/put이 동작하므로,
--      이 SQL만 실행해서는 부족하다 — mcp-server/src/db.js가 실제 진입점이다.
--      이 파일은 문서/외부 도구(sqlite3 CLI 등)용 참조 스키마이자, npm run init이
--      실제로 실행하는 초기화 스크립트다.
--   2. 스킬의 "기본 골격" 시드 — ss_catalog(root, 빈 subjects)만 심는다. 개념 노드/로그/
--      docs 인덱스/미러 설정은 전부 사용자별 실사용으로 채워지는 개인 데이터라 git에
--      공유하지 않는다(비어있는 골격만 시드).

CREATE TABLE IF NOT EXISTS ss_catalog (
  id  TEXT PRIMARY KEY,
  doc TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ss_catalog__modified_at ON ss_catalog(json_extract(doc, '$.modified_at'));

CREATE TABLE IF NOT EXISTS ss_profile (
  id  TEXT PRIMARY KEY,
  doc TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ss_profile__modified_at ON ss_profile(json_extract(doc, '$.modified_at'));

-- ss_concept.doc 필드: { id, subject, name, description(canonical 설명), rubric:[...],
--   verify_state:'unverified'|'withheld'|'failed'|'passed' (영속화 자체는 이 값과 무관하게
--   절대 휘발되지 않는다 — verify는 그 위에 얹히는 별도 상태 축), last_verified_at
--   (passed/failed로 실제 판정이 난 시각만 갱신, withheld/unverified는 갱신 안 함),
--   parent(계층 edge — 선수/포함 관계, 최상위면 null), doc_refs:[path,...],
--   refs:[{concept_key, note?}](비계층 edge — 연관 개념. parent/children과 완전히 별개,
--   ss_concept_link/ss_concept_unlink 또는 ss_concept_put으로 관리), created_at, modified_at }
CREATE TABLE IF NOT EXISTS ss_concept (
  id  TEXT PRIMARY KEY,
  doc TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ss_concept__subject      ON ss_concept(json_extract(doc, '$.subject'));
CREATE INDEX IF NOT EXISTS idx_ss_concept__parent       ON ss_concept(json_extract(doc, '$.parent'));
CREATE INDEX IF NOT EXISTS idx_ss_concept__verify_state ON ss_concept(json_extract(doc, '$.verify_state'));
CREATE INDEX IF NOT EXISTS idx_ss_concept__modified_at  ON ss_concept(json_extract(doc, '$.modified_at'));

CREATE TABLE IF NOT EXISTS ss_log (
  id  TEXT PRIMARY KEY,
  doc TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ss_log__subject    ON ss_log(json_extract(doc, '$.subject'));
CREATE INDEX IF NOT EXISTS idx_ss_log__concept_id ON ss_log(json_extract(doc, '$.concept_id'));
CREATE INDEX IF NOT EXISTS idx_ss_log__event      ON ss_log(json_extract(doc, '$.event'));
CREATE INDEX IF NOT EXISTS idx_ss_log__created_at ON ss_log(json_extract(doc, '$.created_at'));

CREATE TABLE IF NOT EXISTS ss_docs (
  id  TEXT PRIMARY KEY,
  doc TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ss_docs__modified_at ON ss_docs(json_extract(doc, '$.modified_at'));

CREATE TABLE IF NOT EXISTS ss_mirror_map (
  id  TEXT PRIMARY KEY,
  doc TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ss_mirror_map__notion_page_id ON ss_mirror_map(json_extract(doc, '$.notion_page_id'));
CREATE INDEX IF NOT EXISTS idx_ss_mirror_map__modified_at    ON ss_mirror_map(json_extract(doc, '$.modified_at'));

CREATE TABLE IF NOT EXISTS ss_mirror_config (
  id  TEXT PRIMARY KEY,
  doc TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ss_mirror_config__modified_at ON ss_mirror_config(json_extract(doc, '$.modified_at'));

-- root 카탈로그 시드 (빈 subjects — 실제 과목은 ss_subject_put으로 채운다)
INSERT OR IGNORE INTO ss_catalog (id, doc) VALUES ('root', '{"subjects":{},"created_at":"1970-01-01T00:00:00.000Z","modified_at":"1970-01-01T00:00:00.000Z"}');
