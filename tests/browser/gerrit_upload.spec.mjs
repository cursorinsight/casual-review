import {randomUUID} from 'node:crypto';
import {gzipSync} from 'node:zlib';

import {expect, test} from '@playwright/test';

if (!process.env.GERRIT_URL) {
  throw new Error('GERRIT_URL is required');
}
const gerritUrl = new URL(process.env.GERRIT_URL);
const basePath = gerritUrl.pathname.replace(/\/+$/, '');
const project = process.env.GERRIT_TEST_PROJECT;
if (!project) {
  throw new Error('GERRIT_TEST_PROJECT is required');
}
const verdict = process.env.GERRIT_TEST_VERDICT || 'Needs changes';
const labelName = process.env.GERRIT_TEST_LABEL || 'AI-Review';
const labelValue = Number(process.env.GERRIT_TEST_LABEL_VALUE || '-1');
const projectPath = project
  .split('/')
  .map(segment => encodeURIComponent(segment))
  .join('/');

let changeNumber;

function pathAtGerrit(path) {
  return `${basePath}${path}`;
}

function parseJson(text) {
  const clean = text.startsWith(")]}'") ?
    text.slice(text.indexOf('\n') + 1) : text;
  return clean ? JSON.parse(clean) : null;
}

async function browserRequest(page, method, path, body, contentType) {
  return page.evaluate(async request => {
    const headers = {Accept: 'application/json'};
    const options = {
      method: request.method,
      credentials: 'same-origin',
      headers,
    };

    if (request.method !== 'GET') {
      const token = document.cookie
        .split(';')
        .map(value => value.trim())
        .find(value => value.startsWith('XSRF_TOKEN='));
      if (!token) throw new Error('Missing Gerrit XSRF token');
      headers['X-Gerrit-Auth'] = decodeURIComponent(
        token.slice(token.indexOf('=') + 1)
      );
    }

    if (request.body !== undefined) {
      headers['Content-Type'] = request.contentType ||
        'application/json; charset=UTF-8';
      options.body = request.contentType === 'text/plain' ?
        request.body : JSON.stringify(request.body);
    }

    const response = await fetch(request.path, options);
    return {
      status: response.status,
      text: await response.text(),
    };
  }, {
    body,
    contentType,
    method,
    path: pathAtGerrit(path),
  });
}

async function api(page, method, path, body, contentType) {
  const response = await browserRequest(
    page,
    method,
    path,
    body,
    contentType
  );
  if (response.status < 200 || response.status >= 300) {
    throw new Error(
      `${method} ${path} returned ${response.status}: ${response.text}`
    );
  }
  return parseJson(response.text);
}

async function authenticate(page) {
  await page.goto(pathAtGerrit('/'));
  let self = await browserRequest(page, 'GET', '/accounts/self');
  if (self.status === 200) return parseJson(self.text);

  const user = process.env.GERRIT_USER;
  const password = process.env.GERRIT_PASSWORD;
  if (!user || !password) {
    throw new Error(
      'Gerrit session is not authenticated; refresh GERRIT_STORAGE_STATE ' +
        'or set GERRIT_USER and GERRIT_PASSWORD'
    );
  }

  await page.goto(pathAtGerrit('/login/'));
  await page.locator('#f_user').fill(user);
  await page.locator('#f_pass').fill(password);
  await Promise.all([
    page.waitForNavigation(),
    page.locator('#b_signin').click(),
  ]);

  self = await browserRequest(page, 'GET', '/accounts/self');
  if (self.status !== 200) {
    throw new Error('Gerrit login failed');
  }
  return parseJson(self.text);
}

async function createChange(page) {
  const runId = `${Date.now().toString(36)}-${randomUUID().slice(0, 8)}`;
  const file = `casual-review-e2e-${runId}.txt`;
  const change = await api(page, 'POST', '/changes/', {
    branch: 'master',
    project,
    subject: `casual-review browser E2E ${runId}`,
    topic: 'casual-review-browser-e2e',
    work_in_progress: true,
  });
  changeNumber = change._number;

  await api(
    page,
    'PUT',
    `/changes/${changeNumber}/edit/${encodeURIComponent(file)}`,
    `first line for ${runId}\nsecond line\n`,
    'text/plain'
  );
  await api(page, 'POST', `/changes/${changeNumber}/edit:publish`, {
    notify: 'NONE',
  });
  const detail = await api(
    page,
    'GET',
    `/changes/${changeNumber}?o=CURRENT_REVISION&o=ALL_REVISIONS`
  );
  return {commit: detail.current_revision, file, runId};
}

async function updateChange(page, fixture) {
  await api(
    page,
    'PUT',
    `/changes/${changeNumber}/edit/${encodeURIComponent(fixture.file)}`,
    `first line for ${fixture.runId}\nchanged second line\n`,
    'text/plain'
  );
  await api(page, 'POST', `/changes/${changeNumber}/edit:publish`, {
    notify: 'NONE',
  });
}

function makeBundle(fixture) {
  const short = fixture.commit.slice(0, 7);
  const marker = `AI review from e2e for ${short}`;
  return {
    schema: 'casual-review.gerrit-upload.v1',
    commit: fixture.commit,
    commit_short: short,
    notify: 'NONE',
    reviews: [{
      engine: 'e2e',
      commit_short: short,
      verdict,
      message_marker: marker,
      message: `${marker}\n\n**Verdict:** ${verdict}`,
      labels: {},
      comments: [{
        path: fixture.file,
        line: 1,
        unresolved: true,
        severity: 'Major',
        title: 'Browser upload E2E line comment',
        body: 'Literal HTML must remain text: <img src=x onerror=alert(1)>',
        message: '**[AI/e2e] Major:** Browser upload E2E line comment\n\n' +
          'Literal HTML must remain text: <img src=x onerror=alert(1)>',
      }, {
        path: fixture.file,
        unresolved: false,
        severity: 'Minor',
        title: 'Browser upload E2E file comment',
        body: 'This item will be unselected.',
        message: '**[AI/e2e] Minor:** Browser upload E2E file comment\n\n' +
          'This item will be unselected.',
      }],
    }],
  };
}

async function openUploader(page) {
  const upload = page.locator('#crgu-button');
  await expect(upload).toHaveCount(1);
  await expect(upload).toBeVisible();
  await expect(upload).toHaveText('Upload AI review');
  expect(await upload.evaluate(node => {
    return node.previousElementSibling &&
      node.previousElementSibling.id === 'replyBtn';
  })).toBe(true);
  await upload.click();
  await expect(page.locator('#crgu-panel')).toBeVisible();
  await expect(page.locator('#crgu-backdrop')).toBeVisible();
}

function panelButton(page, name) {
  const matches = page.locator('#crgu-panel').getByRole('button', {
    exact: true,
    name,
  });
  // Gerrit exposes both gr-button and its inner paper-button.
  return matches.first();
}

async function loadBundle(page, bundle, name = 'review.json.gz') {
  const buffer = gzipSync(Buffer.from(JSON.stringify(bundle)));
  await page.locator('#crgu-panel .crgu-file-input').setInputFiles({
    buffer,
    mimeType: 'application/gzip',
    name,
  });
}

test.beforeAll(() => {
  if (process.env.GERRIT_E2E_ALLOW_WRITES !== '1') {
    throw new Error('Set GERRIT_E2E_ALLOW_WRITES=1 to run staging tests');
  }
  if (!Number.isInteger(labelValue)) {
    throw new Error('GERRIT_TEST_LABEL_VALUE must be an integer');
  }
});

test.afterEach(async ({page}) => {
  if (!changeNumber) return;
  try {
    await api(page, 'POST', `/changes/${changeNumber}/abandon`, {
      message: 'casual-review browser E2E cleanup',
      notify: 'NONE',
    });
  } finally {
    changeNumber = undefined;
  }
});

test('uploads an exact review and rejects unsafe reruns', async ({page}) => {
  const self = await authenticate(page);
  const fixture = await createChange(page);
  const bundle = makeBundle(fixture);
  const changePath = `/c/${projectPath}/+/${changeNumber}`;
  const reviewRequests = [];
  const dialogs = [];

  page.on('request', request => {
    const url = new URL(request.url());
    if (
      request.method() === 'POST' &&
      url.pathname.endsWith('/review')
    ) {
      reviewRequests.push(request);
    }
  });
  page.on('dialog', async dialog => {
    dialogs.push(dialog.message());
    await dialog.dismiss();
  });

  await page.goto(pathAtGerrit(changePath));
  await openUploader(page);
  const selectAll = panelButton(page, 'SELECT ALL');
  const unselectAll = panelButton(page, 'UNSELECT ALL');
  await expect(selectAll).toBeDisabled();
  await expect(unselectAll).toBeDisabled();
  await expect(panelButton(page, 'SEND')).toBeDisabled();
  await panelButton(page, 'CANCEL').click();
  await expect(page.locator('#crgu-panel')).toHaveCount(0);
  await expect(page.locator('#crgu-backdrop')).toHaveCount(0);
  await openUploader(page);

  await loadBundle(page, {...bundle, schema: 'invalid'}, 'invalid.json.gz');
  await expect(page.locator('.crgu-error')).toContainText(
    'Unsupported review bundle schema'
  );

  const rejectedBundle = structuredClone(bundle);
  rejectedBundle.notify = 'INVALID';
  rejectedBundle.reviews[0].message_marker =
    `Rejected browser upload ${fixture.runId}`;
  rejectedBundle.reviews[0].message =
    rejectedBundle.reviews[0].message_marker;
  rejectedBundle.reviews[0].comments.splice(1, 1);
  rejectedBundle.reviews[0].comments[0].message =
    `Rejected browser comment ${fixture.runId}`;
  await loadBundle(page, rejectedBundle, 'rejected.json.gz');
  const rejectedResponse = page.waitForResponse(response => {
    const url = new URL(response.url());
    return response.request().method() === 'POST' &&
      url.pathname.endsWith('/review');
  });
  await panelButton(page, 'SEND').click();
  expect((await rejectedResponse).ok()).toBe(false);
  await expect(page.locator('.crgu-error')).toContainText('HTTP 400');

  const rejectedComments = await api(
    page,
    'GET',
    `/changes/${changeNumber}/revisions/current/comments/`
  );
  expect(rejectedComments[fixture.file] || []).toHaveLength(0);
  const rejectedMessages = await api(
    page,
    'GET',
    `/changes/${changeNumber}/messages`
  );
  expect(rejectedMessages.some(message => {
    return message.message.includes(
      rejectedBundle.reviews[0].message_marker
    );
  })).toBe(false);

  await loadBundle(page, bundle);
  await expect(page.locator('.crgu-status')).toContainText(
    '3 new item(s), 0 duplicate(s)'
  );
  await expect(page.locator('#crgu-panel')).toContainText(
    '<img src=x onerror=alert(1)>'
  );
  expect(dialogs).toEqual([]);

  await unselectAll.click();
  await expect(panelButton(page, 'SEND')).toBeDisabled();
  await selectAll.click();

  const fileCard = page.locator('.crgu-card').filter({
    hasText: 'Browser upload E2E file comment',
  });
  await fileCard.locator('input[type=checkbox]').uncheck();

  const reviewResponse = page.waitForResponse(response => {
    const url = new URL(response.url());
    return response.request().method() === 'POST' &&
      url.pathname.endsWith('/review');
  });
  const reload = page.waitForEvent(
    'framenavigated',
    frame => frame === page.mainFrame()
  );
  await panelButton(page, 'SEND').click();
  const response = await reviewResponse;
  expect(response.ok()).toBe(true);
  const payload = response.request().postDataJSON();

  expect(payload).toEqual({
    comments: {
      [fixture.file]: [{
        line: 1,
        message: bundle.reviews[0].comments[0].message,
        unresolved: true,
      }],
    },
    labels: {[labelName]: labelValue},
    message: bundle.reviews[0].message,
    notify: 'NONE',
    omit_duplicate_comments: true,
    tag: 'autogenerated:casual-review',
  });
  await reload;

  const encodedCommit = encodeURIComponent(fixture.commit);
  const comments = await api(
    page,
    'GET',
    `/changes/${changeNumber}/revisions/${encodedCommit}/comments/`
  );
  expect(comments[fixture.file]).toHaveLength(1);
  expect(comments[fixture.file][0]).toMatchObject({
    line: 1,
    message: bundle.reviews[0].comments[0].message,
    unresolved: true,
  });

  const messages = await api(
    page,
    'GET',
    `/changes/${changeNumber}/messages`
  );
  expect(messages.some(message => {
    return message.tag === 'autogenerated:casual-review' &&
      message.message.includes(bundle.reviews[0].message_marker);
  })).toBe(true);

  const detail = await api(
    page,
    'GET',
    `/changes/${changeNumber}/detail?o=DETAILED_LABELS`
  );
  const votes = detail.labels[labelName].all || [];
  expect(votes.some(vote => {
    return vote._account_id === self._account_id &&
      Number(vote.value) === labelValue;
  })).toBe(true);

  await openUploader(page);
  const duplicateBundle = structuredClone(bundle);
  duplicateBundle.reviews[0].comments.splice(1, 1);
  await loadBundle(page, duplicateBundle, 'duplicate.json.gz');
  await expect(page.locator('.crgu-status')).toContainText(
    '0 new item(s), 2 duplicate(s)'
  );
  await expect(panelButton(page, 'SEND')).toBeDisabled();
  expect(reviewRequests).toHaveLength(2);

  await page.evaluate(nextPath => {
    history.pushState({}, '', nextPath);
  }, pathAtGerrit('/q/status:open'));
  await expect(page.locator('#crgu-panel')).toHaveCount(0);
  await page.evaluate(nextPath => {
    history.pushState({}, '', nextPath);
  }, pathAtGerrit(changePath));
  await openUploader(page);
  await expect(page.locator('.crgu-card')).toHaveCount(0);

  await panelButton(page, 'CANCEL').click();
  await updateChange(page, fixture);
  await page.reload();
  await openUploader(page);
  await loadBundle(page, bundle, 'stale.json.gz');
  await expect(page.locator('.crgu-error')).toContainText(
    'is not current Gerrit revision'
  );
  expect(reviewRequests).toHaveLength(2);
});
