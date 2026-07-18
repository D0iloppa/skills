'use strict';

const fs = require('fs');
const { McpServer } = require('@modelcontextprotocol/sdk/server/mcp.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const { z } = require('zod');
const { djinn, CATALOG_ID, PROFILE_ID, makeLogId } = require('./db');
const { ONBOARD_LOCK_PATH, DOCS_DIR, SUNSANG_HOME } = require('./paths');
const mirror = require('./mirror');

function json(text) {
  return { content: [{ type: 'text', text: JSON.stringify(text, null, 2) }] };
}

function now() {
  return new Date().toISOString();
}

function getCatalog() {
  return djinn.get('ss_catalog', CATALOG_ID);
}

function ensureCatalog() {
  let root = getCatalog();
  if (!root) {
    const ts = now();
    root = { subjects: {}, created_at: ts, modified_at: ts };
    djinn.put('ss_catalog', CATALOG_ID, root);
  }
  return root;
}

function addLog({ subject, concept_id, event, payload }) {
  const id = makeLogId(event);
  const doc = {
    id,
    subject: subject ?? null,
    concept_id: concept_id ?? null,
    event,
    payload: payload ?? {},
    created_at: now(),
  };
  djinn.put('ss_log', id, doc);
  return doc;
}

// 트리 재조정 시 부모가 먼저 push되도록 위상정렬(간단히: 깊이 오름차순).
function sortByDepth(nodes) {
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const depth = (n, seen = new Set()) => {
    if (!n.parent || seen.has(n.id)) return 0;
    seen.add(n.id);
    const p = byId.get(n.parent);
    return p ? 1 + depth(p, seen) : 0;
  };
  return [...nodes].sort((a, b) => depth(a) - depth(b));
}

function createServer() {
  const server = new McpServer({ name: 'sun-sang', version: '0.1.0' });

  // ---- 온보딩 게이트 -------------------------------------------------

  server.tool(
    'ss_onboard_status',
    '온보딩 완료 여부를 확인한다. 데이터 홈(기본 ~/.sun-sang, SUNSANG_HOME으로 오버라이드)의 onboard.lock 파일 존재 여부가 기준이다(파일 없음 = 미완료). 저장된 학습자 프로파일과 데이터 홈 경로(data_home, docs_dir)도 함께 반환한다 — docs_dir이 ingest 등에서 자료 원문을 저장할 실제 경로다(스킬 설치경로가 아니다). 차단 게이트가 아니라 유도용 — 미완료여도 진행 자체는 막지 않는다.',
    {},
    async () => {
      const onboarded = fs.existsSync(ONBOARD_LOCK_PATH);
      const profile = djinn.get('ss_profile', PROFILE_ID);
      return json({ onboarded, profile: profile ?? null, data_home: SUNSANG_HOME, docs_dir: DOCS_DIR });
    }
  );

  server.tool(
    'ss_onboard_complete',
    '학습자 프로파일(배경지식/목표/설명 선호)을 저장하고 onboard.lock 파일을 생성해 온보딩을 완료 처리한다.',
    {
      background: z.string().optional().describe('배경지식 요약'),
      goals: z.string().optional().describe('학습 목표'),
      explain_pref: z.string().optional().describe('설명 선호 스타일(예: 비유 위주, 수식 위주)'),
    },
    async ({ background, goals, explain_pref }) => {
      const ts = now();
      const existing = djinn.get('ss_profile', PROFILE_ID);
      const doc = {
        background: background ?? existing?.background ?? '',
        goals: goals ?? existing?.goals ?? '',
        explain_pref: explain_pref ?? existing?.explain_pref ?? '',
        onboarded_at: ts,
        created_at: existing?.created_at ?? ts,
        modified_at: ts,
      };
      djinn.put('ss_profile', PROFILE_ID, doc);
      fs.writeFileSync(
        ONBOARD_LOCK_PATH,
        JSON.stringify({ onboarded_at: ts, profile_summary: doc }, null, 2)
      );
      return json({ ok: true, onboarded_at: ts });
    }
  );

  // ---- 과목 카탈로그 ---------------------------------------------------

  server.tool(
    'ss_subject_put',
    '과목(subject)을 카탈로그에 upsert한다. 지식트리의 루트 단위다.',
    {
      slug: z.string().describe('과목 식별 slug, 예: "linear-algebra"'),
      name: z.string().describe('과목 표시 이름'),
      description: z.string().optional(),
    },
    async ({ slug, name, description }) => {
      const root = ensureCatalog();
      const subjects = { ...(root.subjects ?? {}) };
      subjects[slug] = { name, description: description ?? subjects[slug]?.description ?? '' };
      djinn.put('ss_catalog', CATALOG_ID, {
        subjects,
        created_at: root.created_at,
        modified_at: now(),
      });
      return json({ ok: true, slug });
    }
  );

  server.tool(
    'ss_subject_list',
    '등록된 과목 카탈로그 전체를 조회한다.',
    {},
    async () => {
      const root = getCatalog();
      return json(root?.subjects ?? {});
    }
  );

  // ---- 개념 노드 -------------------------------------------------------

  server.tool(
    'ss_concept_put',
    '개념 노드를 upsert한다. canonical description과 판정 rubric(체득 인정 핵심 포인트 배열)을 함께 저장한다 — 세션이 바뀌어도 같은 기준으로 같은 개념을 채점하기 위한 SoT다. parent는 계층 edge(선수/포함)이고, refs는 그와 별개인 비계층 참조(연관 개념)다 — 둘을 혼동하지 않는다. 이 영속화는 verify 결과와 무관하게 절대 휘발되지 않는다 — verify는 이 위에 얹히는 별도의 상태(verify_state)일 뿐이다. 새 노드는 verify_state:"unverified"로 시작한다(명시하지 않는 한 기존 verify_state/last_verified_at은 보존 — verify_state는 보통 이 도구가 아니라 ss_verify_record가 갱신한다). 변경 성공 후 미러링이 설정돼 있으면 best-effort로 자동 push한다(실패해도 이 호출은 실패하지 않는다). refs를 점진적으로 추가/삭제만 하려면 이 도구 대신 ss_concept_link/ss_concept_unlink를 쓰는 편이 더 자연스럽다(전체를 통째로 덮어쓰지 않아도 된다).',
    {
      id: z.string().describe('전역 유일 slug, 예: "linear-algebra::eigenvalues"'),
      subject: z.string().describe('소속 과목 slug'),
      name: z.string(),
      description: z.string().optional().describe('canonical 설명'),
      rubric: z.array(z.string()).optional().describe('체득 인정 핵심 포인트 목록'),
      parent: z.string().nullable().optional().describe('상위 개념 노드 id(계층 edge, 선수/포함 관계), 최상위면 null'),
      doc_refs: z.array(z.string()).optional().describe('연결된 docs 인덱스 path 목록'),
      refs: z
        .array(z.object({ concept_key: z.string(), note: z.string().optional() }))
        .optional()
        .describe('비계층 연관 개념 참조 목록(전체 교체). 점진적 추가/삭제는 ss_concept_link/ss_concept_unlink 권장'),
      verify_state: z
        .enum(['unverified', 'withheld', 'failed', 'passed'])
        .optional()
        .describe('명시적 강제 재설정 시에만 사용(보통은 ss_verify_record가 관리)'),
    },
    async ({ id, subject, name, description, rubric, parent, doc_refs, refs, verify_state }) => {
      const ts = now();
      const existing = djinn.get('ss_concept', id);
      const doc = {
        id,
        subject,
        name,
        description: description ?? existing?.description ?? '',
        rubric: rubric ?? existing?.rubric ?? [],
        parent: parent === undefined ? existing?.parent ?? null : parent,
        doc_refs: doc_refs ?? existing?.doc_refs ?? [],
        refs: refs ?? existing?.refs ?? [],
        verify_state: verify_state ?? existing?.verify_state ?? 'unverified',
        last_verified_at: verify_state
          ? (verify_state === 'passed' || verify_state === 'failed' ? ts : null)
          : existing?.last_verified_at ?? null,
        created_at: existing?.created_at ?? ts,
        modified_at: ts,
      };
      djinn.put('ss_concept', id, doc);
      const mirrorResult = await mirror.pushNode(doc);
      return json({ ok: true, id, node: doc, mirror: mirrorResult });
    }
  );

  server.tool(
    'ss_concept_link',
    '개념 노드 사이에 비계층 참조(refs)를 하나 추가/갱신한다. 지식트리의 parent/children(계층 edge)과 완전히 별개다 — "관련은 있지만 상하관계는 아닌" 연결에 쓴다(같은 concept_key로 다시 호출하면 note만 갱신, 중복 추가 안 함).',
    {
      id: z.string().describe('참조를 추가할 개념 노드 id'),
      concept_key: z.string().describe('참조 대상 개념 노드 id'),
      note: z.string().optional().describe('연관 이유/맥락 메모'),
    },
    async ({ id, concept_key, note }) => {
      const existing = djinn.get('ss_concept', id);
      if (!existing) return json({ ok: false, error: `concept not found: ${id}` });
      const refs = [...(existing.refs ?? [])];
      const idx = refs.findIndex((r) => r.concept_key === concept_key);
      if (idx >= 0) refs[idx] = { concept_key, note: note ?? refs[idx].note };
      else refs.push({ concept_key, note: note ?? '' });
      const doc = { ...existing, refs, modified_at: now() };
      djinn.put('ss_concept', id, doc);
      const mirrorResult = await mirror.pushNode(doc);
      return json({ ok: true, node: doc, mirror: mirrorResult });
    }
  );

  server.tool(
    'ss_concept_unlink',
    '개념 노드의 비계층 참조(refs) 하나를 제거한다.',
    {
      id: z.string(),
      concept_key: z.string(),
    },
    async ({ id, concept_key }) => {
      const existing = djinn.get('ss_concept', id);
      if (!existing) return json({ ok: false, error: `concept not found: ${id}` });
      const refs = (existing.refs ?? []).filter((r) => r.concept_key !== concept_key);
      const doc = { ...existing, refs, modified_at: now() };
      djinn.put('ss_concept', id, doc);
      const mirrorResult = await mirror.pushNode(doc);
      return json({ ok: true, node: doc, mirror: mirrorResult });
    }
  );

  server.tool(
    'ss_concept_get',
    '개념 노드 하나를 조회한다(description/rubric/verify_state 포함).',
    { id: z.string() },
    async ({ id }) => {
      const doc = djinn.get('ss_concept', id);
      return json(doc ?? null);
    }
  );

  server.tool(
    'ss_concept_list',
    '개념 노드 목록을 조회한다. subject/parent/verify_state로 선택 필터링 가능.',
    {
      subject: z.string().optional(),
      parent: z.string().nullable().optional(),
      verify_state: z.enum(['unverified', 'withheld', 'failed', 'passed']).optional(),
    },
    async ({ subject, parent, verify_state }) => {
      const filter = {};
      if (subject) filter.subject = subject;
      if (parent !== undefined) filter.parent = parent;
      if (verify_state) filter.verify_state = verify_state;
      const rows = djinn.find('ss_concept', filter, { orderBy: 'created_at', orderDir: 'asc' });
      return json(rows);
    }
  );

  server.tool(
    'ss_concept_tree',
    '과목 하나의 지식트리를 조회한다. "tree"는 계층 edge(parent/children, 선수/포함 관계)만으로 조립한 구조이고, "cross_refs"는 그와 별개인 비계층 참조(refs) 목록을 {from, to, note} 형태로 평탄화해 함께 반환한다 — 계층과 참조를 섞지 않고 구분해서 보여준다.',
    { subject: z.string() },
    async ({ subject }) => {
      const rows = djinn.find('ss_concept', { subject });
      const byId = new Map(rows.map((r) => [r.id, { ...r, children: [] }]));
      const roots = [];
      for (const node of byId.values()) {
        if (node.parent && byId.has(node.parent)) {
          byId.get(node.parent).children.push(node);
        } else {
          roots.push(node);
        }
      }
      const crossRefs = [];
      for (const r of rows) {
        for (const ref of r.refs ?? []) {
          crossRefs.push({ from: r.id, to: ref.concept_key, note: ref.note ?? '' });
        }
      }
      return json({ subject, tree: roots, cross_refs: crossRefs });
    }
  );

  server.tool(
    'ss_concept_del',
    '개념 노드 하나를 삭제한다(자식 노드는 자동으로 함께 삭제하지 않는다 — 필요하면 각각 호출).',
    { id: z.string() },
    async ({ id }) => {
      djinn.del('ss_concept', id);
      return json({ ok: true });
    }
  );

  // ---- 검증(verify) — 파인만 루프의 핵심 -------------------------------

  server.tool(
    'ss_verify_record',
    "verify 시도 하나의 결과를 기록한다 — 판정이 나왔을 때(passed/failed)뿐 아니라 근거 부족으로 보류했을 때(withheld)도 반드시 기록한다. 개념의 영속화(description/rubric/doc_refs)는 이 호출과 무관하게 이미 완료돼 있고 절대 휘발되지 않는다 — 이 도구는 그 위에 얹히는 verify_state만 갱신한다. result:'passed'|'failed'는 rubric 대조 결과이고 last_verified_at을 현재시각으로 갱신한다. result:'withheld'는 근거(description/rubric/doc_refs)가 부족해 판정을 내리지 못했다는 뜻이며 last_verified_at은 갱신하지 않는다(실제 rubric 대조가 일어나지 않았으므로). 판정 자체(rubric 대조)는 이 도구 호출 전에 AI가 수행한다 — 이 도구는 그 결과를 영속화만 한다. 판정은 dJinn에 영속화된 canonical description/rubric/연결된 docs만 근거로 삼아야 한다(AI의 내재 지식으로 대체 금지) — evidence_rubric_points/evidence_doc_refs에 실제로 대조에 쓴 rubric 항목 원문과 doc 경로를 남겨 근거를 추적 가능하게 한다.",
    {
      id: z.string().describe('개념 노드 id'),
      result: z.enum(['passed', 'failed', 'withheld']).describe('passed/failed=rubric 대조 결과, withheld=근거 부족으로 판정 보류'),
      rationale: z
        .string()
        .describe(
          'passed/failed면 rubric의 어느 포인트가 어떻게 충족/미충족/부분충족됐는지, withheld면 어떤 근거(description/rubric/doc_refs)가 왜 부족한지 구체적으로'
        ),
      user_explanation: z.string().optional().describe('사용자가 실제로 말한 설명 원문(선택, withheld면 생략 가능)'),
      evidence_rubric_points: z
        .array(z.string())
        .optional()
        .describe('판정에 실제로 대조한 rubric 항목 원문 목록(해당 노드 rubric의 부분집합)'),
      evidence_doc_refs: z
        .array(z.string())
        .optional()
        .describe('판정 근거로 인용한 docs 인덱스 path 목록(해당 노드 doc_refs의 부분집합)'),
    },
    async ({ id, result, rationale, user_explanation, evidence_rubric_points, evidence_doc_refs }) => {
      const existing = djinn.get('ss_concept', id);
      if (!existing) return json({ ok: false, error: `concept not found: ${id}` });
      const ts = now();
      const doc = {
        ...existing,
        verify_state: result,
        last_verified_at: result === 'passed' || result === 'failed' ? ts : existing.last_verified_at ?? null,
        modified_at: ts,
      };
      djinn.put('ss_concept', id, doc);
      const log = addLog({
        subject: existing.subject,
        concept_id: id,
        event: 'verify',
        payload: {
          result,
          rationale,
          user_explanation: user_explanation ?? null,
          evidence_rubric_points: evidence_rubric_points ?? [],
          evidence_doc_refs: evidence_doc_refs ?? [],
        },
      });
      const mirrorResult = await mirror.pushNode(doc);
      return json({ ok: true, node: doc, log, mirror: mirrorResult });
    }
  );

  // ---- 학습기록(로그) ---------------------------------------------------

  server.tool(
    'ss_log_add',
    'learn/ask 등 verify 이외의 세션 이벤트를 학습기록에 append한다(예: 새 주제 학습 시작, 자유 질문 답변).',
    {
      subject: z.string().optional(),
      concept_id: z.string().optional(),
      event: z.enum(['learn', 'ask']),
      payload: z.record(z.any()).optional(),
    },
    async ({ subject, concept_id, event, payload }) => {
      const log = addLog({ subject, concept_id, event, payload });
      return json({ ok: true, log });
    }
  );

  server.tool(
    'ss_log_list',
    '세션 로그를 조회한다. subject/concept_id로 필터링, limit으로 최신 N개만.',
    {
      subject: z.string().optional(),
      concept_id: z.string().optional(),
      limit: z.number().optional().default(50),
    },
    async ({ subject, concept_id, limit }) => {
      const filter = {};
      if (subject) filter.subject = subject;
      if (concept_id) filter.concept_id = concept_id;
      const rows = djinn.find('ss_log', filter, {
        orderBy: 'created_at',
        orderDir: 'desc',
        limit: limit ?? 50,
      });
      return json(rows);
    }
  );

  // ---- docs 인덱스 -------------------------------------------------------

  server.tool(
    'ss_docs_put',
    'docs/ 아래 저장된 자료 원문의 인덱스 항목을 upsert한다(원문 자체가 아니라 요약+연결 개념만 dJinn에 둔다).',
    {
      path: z.string().describe('docs/ 기준 상대 경로'),
      summary: z.string().optional(),
      linked_concepts: z.array(z.string()).optional().describe('연결된 개념 노드 id 목록'),
    },
    async ({ path: docPath, summary, linked_concepts }) => {
      const ts = now();
      const existing = djinn.get('ss_docs', docPath);
      const doc = {
        path: docPath,
        summary: summary ?? existing?.summary ?? '',
        linked_concepts: linked_concepts ?? existing?.linked_concepts ?? [],
        created_at: existing?.created_at ?? ts,
        modified_at: ts,
      };
      djinn.put('ss_docs', docPath, doc);
      return json({ ok: true, path: docPath });
    }
  );

  server.tool(
    'ss_docs_get',
    'docs 인덱스 항목 하나를 조회한다.',
    { path: z.string() },
    async ({ path: docPath }) => {
      const doc = djinn.get('ss_docs', docPath);
      return json(doc ?? null);
    }
  );

  server.tool(
    'ss_docs_list',
    'docs 인덱스 전체 목록을 조회한다.',
    {},
    async () => {
      const rows = djinn.find('ss_docs', {}, { orderBy: 'modified_at', orderDir: 'desc' });
      return json(rows);
    }
  );

  // ---- 진척도 -------------------------------------------------------

  server.tool(
    'ss_status',
    '과목별 지식트리 진척도를 verify_state 4상태(unverified/withheld/failed/passed) 기준으로 집계해 반환한다. subject를 지정하면 그 과목만, 생략하면 전체 과목을 훑는다.',
    { subject: z.string().optional() },
    async ({ subject }) => {
      const filter = subject ? { subject } : {};
      const rows = djinn.find('ss_concept', filter);
      const bySubject = {};
      for (const r of rows) {
        const s = (bySubject[r.subject] ??= {
          unverified: 0,
          withheld: 0,
          failed: 0,
          passed: 0,
          total: 0,
        });
        s.total += 1;
        const state = r.verify_state ?? 'unverified';
        s[state] = (s[state] ?? 0) + 1;
      }
      return json(bySubject);
    }
  );

  server.tool(
    'ss_review_candidates',
    "'review' 커맨드 전용 — 복습 큐를 뽑는다. unverified/withheld/failed 개념(아직 체득이 확인되지 않은 것들)을 우선 노출하고, 그 다음으로 passed 개념 중 last_verified_at이 오래된 것을 재검증 후보로 채운다. 자동 스케줄이 아니라 수동 호출 시에만 사용한다.",
    {
      subject: z.string().optional(),
      limit: z.number().optional().default(10),
    },
    async ({ subject, limit }) => {
      const baseFilter = subject ? { subject } : {};
      const cap = limit ?? 10;

      const priorityOrder = { unverified: 0, withheld: 1, failed: 2 };
      const notPassed = djinn
        .find('ss_concept', baseFilter)
        .filter((r) => (r.verify_state ?? 'unverified') !== 'passed')
        .sort((a, b) => {
          const pa = priorityOrder[a.verify_state ?? 'unverified'] ?? 0;
          const pb = priorityOrder[b.verify_state ?? 'unverified'] ?? 0;
          if (pa !== pb) return pa - pb;
          return (a.modified_at ?? '') < (b.modified_at ?? '') ? -1 : 1;
        });

      const candidates = notPassed.slice(0, cap);
      if (candidates.length < cap) {
        const passedFilter = subject ? { subject, verify_state: 'passed' } : { verify_state: 'passed' };
        const stalePassed = djinn.find('ss_concept', passedFilter, {
          orderBy: 'last_verified_at',
          orderDir: 'asc',
          limit: cap - candidates.length,
        });
        candidates.push(...stalePassed);
      }
      return json(candidates);
    }
  );

  // ---- 미러링(Notion, 옵셔널) -------------------------------------------

  server.tool(
    'ss_mirror_config_set',
    'Notion 미러링을 설정한다. api_key는 AES-256-GCM으로 즉시 암호화해 저장하고 ok만 반환한다 — 평문은 응답에 절대 포함되지 않는다.',
    {
      base_url: z.string().describe('미러 대상 Notion 부모 페이지 URL 또는 page_id'),
      api_key: z.string().describe('Notion Integration API 키(평문 입력, 저장 시 즉시 암호화됨)'),
    },
    async ({ base_url, api_key }) => {
      const result = mirror.setConfig({ base_url, api_key });
      return json(result);
    }
  );

  server.tool(
    'ss_mirror_status',
    '미러링 설정 상태를 조회한다. configured/base_url/last_push/failures만 반환하며 API 키(평문/암호문 모두)는 절대 포함하지 않는다.',
    {},
    async () => {
      return json(mirror.getStatus());
    }
  );

  server.tool(
    'ss_mirror_sync',
    "수동 전체 재동기화. 지정 과목(또는 전체)의 개념 노드를 부모부터 순서대로 push한다. 미설정 시 조용히 skip된다. 개별 실패는 학습 흐름과 무관하게 계속 진행하고 요약만 반환한다.",
    { subject: z.string().optional() },
    async ({ subject }) => {
      const filter = subject ? { subject } : {};
      const rows = djinn.find('ss_concept', filter);
      const sorted = sortByDepth(rows);
      const result = await mirror.syncAll(sorted);
      return json(result);
    }
  );

  return server;
}

async function serve() {
  const server = createServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);
  return server;
}

module.exports = { createServer, serve };
