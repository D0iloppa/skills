'use strict';

// AES-256-GCM 봉투 암호화. 암호화 키(keyfile)는 mcp-server/secrets/ 아래 로컬에
// 최초 1회 자동 생성되며(chmod 600), git에는 절대 커밋되지 않는다(.gitignore).
// 이 모듈이 유일한 암/복호화 경로다 — 어떤 MCP 도구 핸들러도 평문 API 키를 다루지 않고,
// mirror push 직전에만 decrypt()를 호출한다.

const fs = require('fs');
const crypto = require('crypto');
const { SECRETS_DIR, KEYFILE_PATH } = require('../paths');

const ALGO = 'aes-256-gcm';

function ensureKey() {
  fs.mkdirSync(SECRETS_DIR, { recursive: true, mode: 0o700 });
  if (!fs.existsSync(KEYFILE_PATH)) {
    const key = crypto.randomBytes(32);
    fs.writeFileSync(KEYFILE_PATH, key, { mode: 0o600 });
    return key;
  }
  const key = fs.readFileSync(KEYFILE_PATH);
  // 기존 파일 권한이 느슨하면(예: umask 영향) 조여둔다.
  try {
    fs.chmodSync(KEYFILE_PATH, 0o600);
  } catch {
    // best-effort — 권한 변경 실패는 치명적이지 않다.
  }
  return key;
}

/**
 * 평문 문자열을 암호화해 { iv, tag, ciphertext } (모두 base64) 봉투로 반환한다.
 * 이 봉투 형태 그대로 djinn에 저장한다 — 평문은 절대 저장하지 않는다.
 */
function encrypt(plaintext) {
  const key = ensureKey();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ALGO, key, iv);
  const ciphertext = Buffer.concat([cipher.update(String(plaintext), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return {
    iv: iv.toString('base64'),
    tag: tag.toString('base64'),
    ciphertext: ciphertext.toString('base64'),
  };
}

/**
 * encrypt()가 만든 봉투를 원문 문자열로 복호화한다. mirror push 직전에만 호출할 것 —
 * 이 함수의 반환값을 MCP 도구 응답에 그대로 담지 않는다.
 */
function decrypt(envelope) {
  if (!envelope || !envelope.iv || !envelope.tag || !envelope.ciphertext) {
    throw new Error('invalid encrypted envelope');
  }
  const key = ensureKey();
  const decipher = crypto.createDecipheriv(ALGO, key, Buffer.from(envelope.iv, 'base64'));
  decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(envelope.ciphertext, 'base64')),
    decipher.final(),
  ]);
  return plaintext.toString('utf8');
}

module.exports = { encrypt, decrypt, ensureKey, KEYFILE_PATH };
