'use strict';

const { DJinn } = require('@d0iloppa/djinn');
const { DB_PATH, ensureDataHome } = require('./paths');

// 데이터 홈(기본 ~/.sun-sang, SUNSANG_HOME으로 오버라이드)이 없으면 자동 생성한다 —
// 학습 데이터는 스킬 설치경로(git repo)가 아니라 학습자 홈에 귀속된다.
ensureDataHome();

const djinn = new DJinn(DB_PATH);

// ss_catalog: 루트 카탈로그(1-row, id='root'). 등록된 과목(subject) 목록 + 설명.
djinn.define('ss_catalog', { indexes: ['modified_at'] });
const CATALOG_ID = 'root';

// ss_profile: 학습자 프로파일(1-row, id='root'). 배경지식/목표/설명 선호.
djinn.define('ss_profile', { indexes: ['modified_at'] });
const PROFILE_ID = 'root';

// ss_concept: 개념 노드(테이블 노드). id는 호출자가 부여하는 전역 유일 slug
// (예: "math::linear-equations") — 세션이 바뀌어도 같은 개념을 같은 id로 지칭하는
// referential grounding의 핵심. canonical description + 판정 rubric을 함께 영속화한다.
// 이 영속화는 verify_state와 무관하게 절대 휘발되지 않는다 — verify는 그 위에 얹히는
// 별도의 상태 축일 뿐이다. parent는 계층 edge(선수/포함 관계)이고,
// refs:[{concept_key, note?}]는 그와 완전히 별개인 비계층 참조(연관 개념)다 — 트리
// 구조와 섞이지 않는다. verify_state: 'unverified'(영속화만 됨, 아직 검증 안 됨) |
// 'withheld'(verify 시도했으나 근거 부족으로 판정 보류) | 'failed'(rubric 대조 불통과) |
// 'passed'(체득 인정). last_verified_at은 passed/failed로 판정이 실제로 난 시각만 갱신한다.
djinn.define('ss_concept', {
  indexes: ['subject', 'parent', 'verify_state', 'modified_at'],
});

// ss_log: 학습기록(데이터 노드). append 전용 세션 로그(learn/verify/ask 이벤트).
djinn.define('ss_log', {
  indexes: ['subject', 'concept_id', 'event', 'created_at'],
});

// ss_docs: 자료 원문 인덱스. 원문 자체는 docs/ 폴더에, 여기는 요약+연결 개념만.
djinn.define('ss_docs', { indexes: ['modified_at'] });

// ss_mirror_map: 개념 노드 <-> Notion 페이지 매핑(멱등 push용). id = node_id.
djinn.define('ss_mirror_map', { indexes: ['notion_page_id', 'modified_at'] });

// ss_mirror_config: 미러링 설정(1-row, id='root'). api key는 암호화된 형태로만 저장.
djinn.define('ss_mirror_config', { indexes: ['modified_at'] });
const MIRROR_CONFIG_ID = 'root';

function makeLogId(suffix) {
  const rand = Math.random().toString(36).slice(2, 10);
  return suffix != null ? `${Date.now()}-${suffix}-${rand}` : `${Date.now()}-${rand}`;
}

module.exports = {
  djinn,
  DB_PATH,
  CATALOG_ID,
  PROFILE_ID,
  MIRROR_CONFIG_ID,
  makeLogId,
};
