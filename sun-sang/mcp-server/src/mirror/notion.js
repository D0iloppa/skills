'use strict';

// Notion 공식 REST API를 직접 호출하는 provider(외부 SDK 미사용, Node 20 전역 fetch 사용).
// 이 파일은 provider 구현 하나만 담당한다 — 설정/암복호화/재시도 정책은 mirror/index.js가 맡는다.

const NOTION_VERSION = '2022-06-28';
const API_BASE = 'https://api.notion.com/v1';

function headers(apiKey) {
  return {
    Authorization: `Bearer ${apiKey}`,
    'Notion-Version': NOTION_VERSION,
    'Content-Type': 'application/json',
  };
}

function toRichText(text) {
  const value = (text ?? '').toString().slice(0, 2000); // Notion rich_text 필드 길이 제한
  return [{ type: 'text', text: { content: value } }];
}

function conceptToBlocks(node) {
  const blocks = [];
  if (node.description) {
    blocks.push({
      object: 'block',
      type: 'paragraph',
      paragraph: { rich_text: toRichText(node.description) },
    });
  }
  if (Array.isArray(node.rubric) && node.rubric.length) {
    blocks.push({
      object: 'block',
      type: 'heading_3',
      heading_3: { rich_text: toRichText('판정 rubric') },
    });
    for (const point of node.rubric) {
      blocks.push({
        object: 'block',
        type: 'bulleted_list_item',
        bulleted_list_item: { rich_text: toRichText(point) },
      });
    }
  }
  blocks.push({
    object: 'block',
    type: 'paragraph',
    paragraph: {
      rich_text: toRichText(
        `verify_state: ${node.verify_state ?? 'unverified'}${node.last_verified_at ? ` (last_verified_at: ${node.last_verified_at})` : ''}`
      ),
    },
  });
  return blocks;
}

/**
 * 노드 하나를 Notion 페이지로 push한다. existingPageId가 있으면 update(멱등),
 * 없으면 parentPageId 하위에 새 페이지를 생성한다. 반환값: { pageId }.
 * 실패 시 예외를 던진다 — 호출자(mirror/index.js)가 best-effort로 감싼다.
 */
async function pushConcept({ apiKey, parentPageId, existingPageId, node }) {
  if (existingPageId) {
    // 제목 갱신
    await request(`/pages/${existingPageId}`, apiKey, 'PATCH', {
      properties: { title: { title: toRichText(node.name) } },
    });
    // 본문은 기존 children을 지우지 않고 유지하는 대신, 통짜 재작성이 필요하면
    // 별도 append 대신 전체를 대체한다: 기존 children 조회 후 archive, 새로 append.
    const existingChildren = await request(`/blocks/${existingPageId}/children?page_size=100`, apiKey, 'GET');
    for (const child of existingChildren.results ?? []) {
      await request(`/blocks/${child.id}`, apiKey, 'DELETE');
    }
    await request(`/blocks/${existingPageId}/children`, apiKey, 'PATCH', {
      children: conceptToBlocks(node),
    });
    return { pageId: existingPageId };
  }

  const created = await request('/pages', apiKey, 'POST', {
    parent: { page_id: parentPageId },
    properties: { title: { title: toRichText(node.name) } },
    children: conceptToBlocks(node),
  });
  return { pageId: created.id };
}

async function request(pathname, apiKey, method, body) {
  const res = await fetch(`${API_BASE}${pathname}`, {
    method,
    headers: headers(apiKey),
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`notion API ${method} ${pathname} failed: ${res.status} ${text}`);
  }
  if (res.status === 204) return {};
  return res.json();
}

module.exports = { pushConcept };
