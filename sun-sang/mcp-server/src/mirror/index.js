'use strict';

// 미러링 단일 엔트리포인트. provider 인터페이스 + notion provider 하나만 구현한다.
// 원칙:
//  - 미설정 시 전체를 조용히 skip한다(에러 아님).
//  - push 실패는 학습 흐름을 절대 차단하지 않는다 — 예외를 던지지 않고 결과 객체로만 알린다.
//  - 평문 API 키는 이 모듈 내부, push 직전에만 존재한다. 호출자에게 반환되지 않는다.

const { djinn, MIRROR_CONFIG_ID } = require('../db');
const cryptoUtil = require('./crypto');
const notionProvider = require('./notion');

const MAX_FAILURES = 20;

function getConfig() {
  return djinn.get('ss_mirror_config', MIRROR_CONFIG_ID);
}

function isConfigured() {
  const cfg = getConfig();
  return !!(cfg && cfg.base_url && cfg.encrypted_api_key);
}

/** 설정용 — 평문 키를 받아 암호화 저장만 하고 ok만 반환한다(평문 재노출 없음). */
function setConfig({ base_url, api_key }) {
  const now = new Date().toISOString();
  const existing = getConfig();
  const doc = {
    base_url,
    provider: 'notion',
    encrypted_api_key: cryptoUtil.encrypt(api_key),
    last_push: existing?.last_push ?? null,
    failures: existing?.failures ?? [],
    created_at: existing?.created_at ?? now,
    modified_at: now,
  };
  djinn.put('ss_mirror_config', MIRROR_CONFIG_ID, doc);
  return { ok: true };
}

/** 조회용 — configured/base_url/last_push/failures만 반환한다. 키는 절대 포함하지 않는다. */
function getStatus() {
  const cfg = getConfig();
  if (!cfg) {
    return { configured: false, base_url: null, last_push: null, failures: [] };
  }
  return {
    configured: !!cfg.encrypted_api_key,
    base_url: cfg.base_url ?? null,
    last_push: cfg.last_push ?? null,
    failures: cfg.failures ?? [],
  };
}

function recordFailure(nodeId, message) {
  const cfg = getConfig();
  if (!cfg) return;
  const failures = [...(cfg.failures ?? []), { node_id: nodeId, message, at: new Date().toISOString() }].slice(
    -MAX_FAILURES
  );
  djinn.put('ss_mirror_config', MIRROR_CONFIG_ID, { ...cfg, failures, modified_at: new Date().toISOString() });
}

function recordSuccess() {
  const cfg = getConfig();
  if (!cfg) return;
  djinn.put('ss_mirror_config', MIRROR_CONFIG_ID, {
    ...cfg,
    last_push: new Date().toISOString(),
    modified_at: new Date().toISOString(),
  });
}

/**
 * 노드 하나를 best-effort로 push한다. 미설정이면 { skipped: true }.
 * 실패해도 예외를 던지지 않는다 — { ok: false, error } 형태로 알리고 config.failures에 기록한다.
 */
async function pushNode(node) {
  if (!isConfigured()) return { skipped: true };
  const cfg = getConfig();
  try {
    const apiKey = cryptoUtil.decrypt(cfg.encrypted_api_key); // 복호화는 여기, push 직전에만
    const mapping = djinn.get('ss_mirror_map', node.id);
    const parentMapping = node.parent ? djinn.get('ss_mirror_map', node.parent) : null;
    const parentPageId = parentMapping ? parentMapping.notion_page_id : extractPageId(cfg.base_url);

    const { pageId } = await notionProvider.pushConcept({
      apiKey,
      parentPageId,
      existingPageId: mapping ? mapping.notion_page_id : null,
      node,
    });

    djinn.put('ss_mirror_map', node.id, {
      node_id: node.id,
      notion_page_id: pageId,
      last_pushed_at: new Date().toISOString(),
    });
    recordSuccess();
    return { ok: true, pageId };
  } catch (err) {
    recordFailure(node.id, String(err && err.message ? err.message : err));
    return { ok: false, error: String(err && err.message ? err.message : err) };
  }
}

/** base_url(Notion 페이지 URL 또는 page_id)에서 page_id를 뽑아낸다. */
function extractPageId(baseUrl) {
  if (!baseUrl) return null;
  const cleaned = baseUrl.trim();
  const match = cleaned.match(/[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/);
  return match ? match[0] : cleaned;
}

/**
 * 전체 재동기화 — 지정된 노드 목록을 순서대로(부모 먼저 오도록 정렬돼 있다고 가정) push한다.
 * 개별 실패는 continue한다. { pushed, failed, skipped } 요약 반환.
 */
async function syncAll(nodes) {
  if (!isConfigured()) return { skipped: true, pushed: 0, failed: 0 };
  let pushed = 0;
  let failed = 0;
  const errors = [];
  for (const node of nodes) {
    const result = await pushNode(node);
    if (result.ok) pushed += 1;
    else if (result.skipped) break;
    else {
      failed += 1;
      errors.push({ node_id: node.id, error: result.error });
    }
  }
  return { pushed, failed, errors };
}

module.exports = { pushNode, syncAll, setConfig, getStatus, isConfigured };
