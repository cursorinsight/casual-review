import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

import {defineConfig} from '@playwright/test';

if (!process.env.GERRIT_URL) {
  throw new Error('GERRIT_URL is required');
}
const gerritUrl = new URL(process.env.GERRIT_URL);
const defaultAuth = fileURLToPath(
  new URL('.auth/gerrit.json', import.meta.url)
);
const configuredAuth = process.env.GERRIT_STORAGE_STATE;
const storageState = configuredAuth ||
  (existsSync(defaultAuth) ? defaultAuth : undefined);

export default defineConfig({
  expect: {timeout: 15_000},
  fullyParallel: false,
  outputDir: fileURLToPath(
    new URL('test-results/gerrit-browser', import.meta.url)
  ),
  reporter: 'line',
  testDir: fileURLToPath(new URL('../tests/browser', import.meta.url)),
  timeout: 120_000,
  use: {
    baseURL: gerritUrl.origin,
    ignoreHTTPSErrors:
      process.env.GERRIT_IGNORE_HTTPS_ERRORS === '1',
    screenshot: 'only-on-failure',
    storageState,
    trace: 'retain-on-failure',
  },
  workers: 1,
});
