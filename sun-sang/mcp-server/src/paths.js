'use strict';

// 데이터 홈 — 학습 데이터는 학습자에 귀속되며 스킬 코드(git repo)와 무관하게 관리된다.
// git(skills repo)은 스킬 코드 공유용일 뿐이다 — 실제 학습 데이터(dJinn DB, docs 원문,
// 암호화 secrets, 온보딩 마커)는 스킬 설치경로가 아니라 사용자 홈의 데이터 디렉토리에
// 둔다. 이렇게 하면 스킬 repo를 재클론하거나 스킬 코드를 업데이트해도 학습 데이터가
// 보존된다. 기본값은 `~/.sun-sang`이며 `SUNSANG_HOME` 환경변수로 오버라이드할 수 있다.

const fs = require('fs');
const os = require('os');
const path = require('path');

const SUNSANG_HOME = process.env.SUNSANG_HOME
  ? path.resolve(process.env.SUNSANG_HOME)
  : path.join(os.homedir(), '.sun-sang');

const DATA_DIR = path.join(SUNSANG_HOME, 'data');
const DOCS_DIR = path.join(SUNSANG_HOME, 'docs');
const SECRETS_DIR = path.join(SUNSANG_HOME, 'secrets');

const DB_PATH = path.join(DATA_DIR, 'sunsang.db');
const ONBOARD_LOCK_PATH = path.join(SUNSANG_HOME, 'onboard.lock');
const KEYFILE_PATH = path.join(SECRETS_DIR, 'mirror.key');

// 서버 기동/최초 사용 시 데이터 홈 하위 디렉토리가 없으면 자동 생성한다(멱등).
function ensureDataHome() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.mkdirSync(DOCS_DIR, { recursive: true });
  fs.mkdirSync(SECRETS_DIR, { recursive: true, mode: 0o700 });
  return SUNSANG_HOME;
}

module.exports = {
  SUNSANG_HOME,
  DATA_DIR,
  DOCS_DIR,
  SECRETS_DIR,
  DB_PATH,
  ONBOARD_LOCK_PATH,
  KEYFILE_PATH,
  ensureDataHome,
};
