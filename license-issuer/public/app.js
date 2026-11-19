const labels = {
  title: ['授权签发', 'License issuer'],
  language: ['语言', 'Language'],
  loginTitle: ['登录授权后台', 'Sign in to the license issuer'],
  account: ['账号', 'Account'],
  password: ['密码', 'Password'],
  login: ['登录', 'Sign in'],
  logout: ['退出登录', 'Sign out'],
  issueTitle: ['签发FIN Energy 能源管理授权', 'Issue an FinEnergy license'],
  licenseType: ['授权类型', 'License type'],
  host: ['机器绑定', 'Machine-bound'],
  training: ['培训授权', 'Training'],
  trainingInfo: ['培训授权按有效期使用，签发时无需机器码。', 'A training license is valid for its specified period and requires no Host ID.'],
  customer: ['客户名称（选填）', 'Customer (optional)'],
  hostId: ['FIN 机器码', 'FIN Host ID'],
  requestFile: ['导入授权申请（选填）', 'Import activation request (optional)'],
  chooseRequestFile: ['选择申请文件', 'Choose request file'],
  notBefore: ['生效时间', 'Starts at'],
  expiresAt: ['到期时间', 'Expires at'],
  note: ['备注（选填）', 'Notes (optional)'],
  timeZone: ['输入时间采用浏览器时区 {zone}。签发前请核对实际时间。', 'Enter dates in your browser time zone, {zone}. Review the exact times before signing.'],
  reset: ['新建申请', 'New request'],
  review: ['核对授权内容', 'Review license'],
  reviewTitle: ['确认签发', 'Review and sign'],
  confirm: ['生成授权', 'Sign license'],
  cancel: ['返回编辑', 'Back to editing'],
  linked: ['本次签发关联原授权 {id}', 'This issuance refers to license {id}'],
  licenseId: ['授权编号', 'License ID'],
  downloadIssued: ['下载本次授权', 'Download this license'],
  download: ['下载授权', 'Download license'],
  history: ['签发记录', 'Issuance history'],
  empty: ['没有匹配的签发记录。', 'No matching licenses.'],
  issued: ['授权 {id} 已签发。', 'License {id} is ready to download.'],
  requestLoaded: ['已载入申请中的 FIN 机器码。', 'FIN Host ID loaded from the request.'],
  searchLabel: ['搜索客户、机器码或授权编号', 'Search by customer, Host ID or license ID'],
  search: ['搜索', 'Search'],
  historyPages: ['签发记录分页', 'Issuance history pages'],
  previous: ['上一页', 'Previous'],
  next: ['下一页', 'Next'],
  pageCount: ['第 {page} / {pages} 页', 'Page {page} of {pages}'],
  issuer: ['签发人', 'Issued by'],
  issuedAt: ['签发时间', 'Issued at'],
  action: ['签发方式', 'Issuance'],
  issue: ['首次签发', 'New license'],
  renewal: ['续期', 'Renewal'],
  reissue: ['换机重签', 'Reissue for another host'],
  renew: ['续期或换机', 'Renew or reissue'],
  renewTraining: ['续期', 'Renew'],
  original: ['原授权编号', 'Previous license ID'],
  invalidInput: ['请检查填写内容。', 'Check the entered values.'],
  invalidHostId: ['请填写有效的 FIN 机器码。', 'Enter a valid FIN Host ID.'],
  invalidRequestFile: ['授权申请文件格式有误。', 'The activation request file is invalid.'],
  invalidPeriod: ['请检查生效和到期时间。到期时间须晚于生效时间及当前时间。', 'Check the dates. The expiry must be after the start time and the current time.'],
  invalidLicenseType: ['请选择授权类型。', 'Select a license type.'],
  trainingHostId: ['培训授权的申请中不可填写机器码。', 'Remove the Host ID from the training license request.'],
  invalidPreviousLicense: ['原授权不存在或授权类型不一致。', 'The previous license is missing or has a different type.'],
  invalidCredentials: ['账号或密码不正确。', 'The account or password is incorrect.'],
  loginRequired: ['会话已结束，请重新登录。', 'Your session ended. Sign in again.'],
  forbidden: ['请求无法验证，请刷新页面后重试。', 'The request could not be verified. Refresh the page and try again.'],
  rateLimited: ['请求过于频繁，请稍后重试。', 'Too many requests. Try again later.'],
  tooLarge: ['文件太大，请选择有效的授权申请文件。', 'The file is too large. Select a valid activation request file.'],
  requestConflict: ['此次签发已提交。请核对签发记录后再操作。', 'This request was already submitted. Check the issuance history before continuing.'],
  requestFailed: ['请求失败，请稍后重试。', 'The request failed. Try again in a moment.'],
  notFound: ['找不到该授权。', 'The license could not be found.'],
};

const $ = id => document.getElementById(id);
const form = $('issue');
const fields = form.elements;
const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
let language = navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en';
try { language = localStorage.getItem('finenergy-issuer-language') ?? language; } catch { /* Session-only preference. */ }
if (!['zh', 'en'].includes(language)) language = 'en';

let session = null;
let previousLicense = null;
let pending = null;
let signing = false;
let history = { items: [], page: 1, pageSize: 50, total: 0 };
let historyRequest = 0;
const messages = new Map();
const t = (key, values = {}) => (labels[key] ?? labels.requestFailed)[language === 'zh' ? 0 : 1]
  .replace(/\{(\w+)\}/g, (_, field) => String(values[field] ?? ''));
const setText = (el, value) => { el.textContent = value; };

function message(id, key, error = false, values = {}) {
  const el = $(id);
  if (key) messages.set(id, { key, values, error });
  else messages.delete(id);
  el.hidden = !key;
  el.classList.toggle('error', error);
  setText(el, key ? t(key, values) : '');
}

function localTime(date) {
  const format = new Intl.DateTimeFormat(language === 'zh' ? 'zh-CN' : 'en', {
    dateStyle: 'medium', timeStyle: 'short', timeZone,
  });
  return format.format(date);
}

function dateValue(date) {
  const two = value => String(value).padStart(2, '0');
  return [date.getFullYear(), two(date.getMonth() + 1), two(date.getDate())].join('-') + 'T' +
    two(date.getHours()) + ':' + two(date.getMinutes());
}

function setSession(user) {
  session = user;
  $('login-panel').hidden = Boolean(user);
  $('issuer').hidden = !user;
  $('logout').hidden = !user;
  $('username').hidden = !user;
  setText($('username'), user?.username ?? '');
  if (!user) {
    if ($('confirmation').open) $('confirmation').close();
    pending = null;
    resetForm();
    historyRequest++;
    history = { items: [], page: 1, pageSize: 50, total: 0 };
    $('search').reset();
    renderHistory();
  }
}

async function api(path, body) {
  const response = await fetch(path, body === undefined ? undefined : {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': session?.csrf ?? '' },
    body: JSON.stringify(body),
  });
  const result = await response.json();
  if (!response.ok) {
    if (response.status === 401 && !['/api/session', '/api/login'].includes(path)) {
      setSession(null);
      message('login-message', 'loginRequired', true);
    }
    throw new Error(result.error ?? 'requestFailed');
  }
  return result;
}

function updateForm() {
  const host = fields.type.value === 'host';
  $('host-fields').hidden = !host;
  $('training-info').hidden = host;
  fields.hostId.disabled = !host;
  fields.hostId.required = host;
  $('linked').hidden = !previousLicense;
  setText($('linked'), previousLicense ? t('linked', { id: previousLicense.licenseId }) : '');
  setText($('time-zone'), t('timeZone', { zone: timeZone }));
}

function resetForm() {
  previousLicense = null;
  pending = null;
  form.reset();
  fields.type.disabled = false;
  fields.notBefore.value = dateValue(new Date());
  $('latest-download').hidden = true;
  $('latest-download').removeAttribute('href');
  message('issue-message', null);
  updateForm();
}

function details(target, pairs) {
  target.replaceChildren();
  for (const [key, value] of pairs) {
    const dt = document.createElement('dt');
    const dd = document.createElement('dd');
    setText(dt, t(key));
    setText(dd, value);
    target.append(dt, dd);
  }
}

const filePath = id => '/api/licenses/' + encodeURIComponent(id) + '/file';
const timeText = value => localTime(new Date(value)) + ' (' + value + ')';

function recordDetails(record) {
  const pairs = [['licenseId', record.licenseId], ['licenseType', t(record.type)]];
  if (record.hostId) pairs.push(['hostId', record.hostId]);
  pairs.push(['notBefore', timeText(record.notBefore)], ['expiresAt', timeText(record.expiresAt)]);
  if (record.customer) pairs.push(['customer', record.customer]);
  if (record.note) pairs.push(['note', record.note]);
  pairs.push(['issuer', record.issuer], ['issuedAt', timeText(record.issuedAt)], ['action', t(record.action)]);
  if (record.previousLicenseId) pairs.push(['original', record.previousLicenseId]);
  return pairs;
}

function startRenewal(record) {
  resetForm();
  previousLicense = record;
  fields.type.value = record.type;
  fields.type.disabled = true;
  fields.hostId.value = record.hostId ?? '';
  fields.customer.value = record.customer;
  fields.note.value = record.note;
  updateForm();
  fields.notBefore.focus();
}

function renderHistory() {
  const target = $('records');
  target.replaceChildren();
  if (!history.items.length) {
    const empty = document.createElement('p');
    empty.className = 'hint';
    setText(empty, t('empty'));
    target.append(empty);
  }
  for (const record of history.items) {
    const item = document.createElement('details');
    const summary = document.createElement('summary');
    const name = document.createElement('b');
    const facts = document.createElement('dl');
    const actions = document.createElement('div');
    const download = document.createElement('a');
    const renew = document.createElement('button');
    item.className = 'record';
    facts.className = 'details';
    actions.className = 'actions';
    setText(name, record.customer || record.hostId || record.licenseId);
    summary.append(name, document.createTextNode(' · ' + t(record.type) + ' · ' + localTime(new Date(record.expiresAt))));
    details(facts, recordDetails(record));
    download.href = filePath(record.licenseId);
    setText(download, t('download'));
    renew.type = 'button';
    renew.className = 'secondary';
    setText(renew, t(record.type === 'training' ? 'renewTraining' : 'renew'));
    renew.addEventListener('click', () => startRenewal(record));
    actions.append(download, renew);
    item.append(summary, facts, actions);
    target.append(item);
  }
  const pages = Math.max(1, Math.ceil(history.total / history.pageSize));
  $('pages').hidden = pages === 1;
  $('previous').disabled = history.page <= 1;
  $('next').disabled = history.page >= pages;
  setText($('page-count'), t('pageCount', { page: history.page, pages }));
}

async function loadHistory(page = 1) {
  const generation = ++historyRequest;
  const query = new URLSearchParams({ page: String(page), q: $('search').elements.q.value });
  try {
    const result = await api('/api/licenses?' + query);
    if (generation !== historyRequest) return;
    history = result;
    renderHistory();
    message('history-message', null);
  } catch (error) {
    if (generation === historyRequest) message('history-message', error.message, true);
  }
}

function renderConfirmation() {
  if (!pending) return;
  const pairs = [['licenseType', t(pending.type)]];
  if (pending.hostId) pairs.push(['hostId', pending.hostId]);
  pairs.push(['notBefore', timeText(pending.notBefore)], ['expiresAt', timeText(pending.expiresAt)]);
  if (pending.customer) pairs.push(['customer', pending.customer]);
  if (pending.note) pairs.push(['note', pending.note]);
  if (pending.previousLicenseId) pairs.push(['original', pending.previousLicenseId]);
  details($('confirmation-fields'), pairs);
}

function applyLanguage() {
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
  document.title = 'FinEnergy · ' + t('title');
  $('language').value = language;
  for (const el of document.querySelectorAll('[data-text]')) setText(el, t(el.dataset.text));
  for (const el of document.querySelectorAll('[data-label]')) el.setAttribute('aria-label', t(el.dataset.label));
  for (const el of document.querySelectorAll('[data-placeholder]')) el.placeholder = t(el.dataset.placeholder);
  for (const [id, { key, error, values }] of messages) message(id, key, error, values);
  updateForm();
  renderHistory();
  renderConfirmation();
}

$('language').addEventListener('change', event => {
  language = event.target.value;
  try { localStorage.setItem('finenergy-issuer-language', language); } catch { /* Session-only preference. */ }
  applyLanguage();
});

$('login').addEventListener('submit', async event => {
  event.preventDefault();
  const credentials = Object.fromEntries(new FormData(event.target));
  const button = event.submitter;
  button.disabled = true;
  try {
    setSession(await api('/api/login', credentials));
    event.target.reset();
    message('login-message', null);
    resetForm();
    await loadHistory();
  } catch (error) {
    message('login-message', error.message, true);
    event.target.elements.password.value = '';
  } finally { button.disabled = false; }
});

$('logout').addEventListener('click', async () => {
  try { await api('/api/logout', {}); setSession(null); message('login-message', null); }
  catch (error) { message('issue-message', error.message, true); }
});

$('request-file').addEventListener('change', async event => {
  const file = event.target.files[0];
  if (!file) return;
  try {
    if (file.size > 8 * 1024) throw new Error('tooLarge');
    let requestFile;
    try { requestFile = JSON.parse(await file.text()); } catch { throw new Error('invalidRequestFile'); }
    const result = await api('/api/requests/parse', { requestFile });
    if (fields.type.value === 'host') {
      fields.hostId.value = result.hostId;
      message('issue-message', 'requestLoaded');
    }
  } catch (error) { message('issue-message', error.message, true); }
  finally { event.target.value = ''; }
});

function dateFromInput(value) {
  const date = new Date(value);
  if (!Number.isFinite(date.valueOf()) || dateValue(date) !== value) throw new Error('invalidPeriod');
  return date;
}

fields.type.addEventListener('change', updateForm);
$('reset').addEventListener('click', resetForm);
form.addEventListener('submit', event => {
  event.preventDefault();
  try {
    const start = dateFromInput(fields.notBefore.value);
    const end = dateFromInput(fields.expiresAt.value);
    if (end <= start || end <= new Date()) throw new Error('invalidPeriod');
    const type = fields.type.value;
    const request = { type, notBefore: start.toISOString(), expiresAt: end.toISOString(),
      customer: fields.customer.value, note: fields.note.value };
    if (type === 'host') request.hostId = fields.hostId.value.trim();
    if (previousLicense) request.previousLicenseId = previousLicense.licenseId;
    const { requestId, ...oldRequest } = pending ?? {};
    pending = { ...request, requestId: JSON.stringify(oldRequest) === JSON.stringify(request) ? requestId : crypto.randomUUID() };
    message('confirm-message', null);
    renderConfirmation();
    $('confirmation').showModal();
  } catch (error) { message('issue-message', error.message, true); }
});

$('cancel').addEventListener('click', () => $('confirmation').close());
$('confirmation').addEventListener('cancel', event => { if (signing) event.preventDefault(); });
$('confirm').addEventListener('click', async () => {
  if (!pending || signing) return;
  signing = true;
  $('confirm').disabled = true;
  $('cancel').disabled = true;
  try {
    const record = await api('/api/licenses', pending);
    $('confirmation').close();
    pending = null;
    resetForm();
    $('latest-download').href = filePath(record.licenseId);
    $('latest-download').hidden = false;
    message('issue-message', 'issued', false, { id: record.licenseId });
    $('search').reset();
    await loadHistory();
  } catch (error) { message('confirm-message', error.message, true); }
  finally {
    signing = false;
    $('confirm').disabled = false;
    $('cancel').disabled = false;
  }
});

$('search').addEventListener('submit', event => { event.preventDefault(); void loadHistory(); });
$('previous').addEventListener('click', () => { void loadHistory(history.page - 1); });
$('next').addEventListener('click', () => { void loadHistory(history.page + 1); });

applyLanguage();
resetForm();
try {
  setSession(await api('/api/session'));
  await loadHistory();
} catch (error) {
  setSession(null);
  if (error.message !== 'loginRequired') message('login-message', error.message, true);
}
