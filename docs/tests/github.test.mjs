import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeRepository, normalizeReleases, latestStable, releaseParagraphs, repositoryURL } from '../src/lib/github.mjs';
const release = (tag, date, extra = {}) => ({ tag_name: tag, name: tag, html_url: `${repositoryURL}/releases/tag/${tag}`, published_at: date, body: 'First line\\nSecond line', assets: [], ...extra });
test('zero stars is valid and invalid repository data is rejected', () => {
  assert.equal(normalizeRepository({ full_name: 'apil-khadka/PrivyLock', stargazers_count: 0 }).stars, 0);
  for (const count of [-1, '7', null]) assert.throws(() => normalizeRepository({ full_name: 'apil-khadka/PrivyLock', stargazers_count: count }));
  assert.throws(() => normalizeRepository({ full_name: 'other/repo', stargazers_count: 1 }));
});
test('release ordering excludes drafts and latest stable skips prereleases', () => {
  const releases = normalizeReleases([release('v1', '2026-01-01'), release('v2-beta', '2026-03-01', { prerelease: true }), release('draft', '2026-04-01', { draft: true }), release('v2', '2026-02-01')]);
  assert.deepEqual(releases.map(r => r.tag), ['v2-beta', 'v2', 'v1']);
  assert.equal(latestStable(releases).tag, 'v2');
  assert.equal(latestStable([]), null);
});
test('notes normalize escaped newlines and unsafe download URLs are omitted', () => {
  const item = normalizeReleases([release('v1', '2026-01-01', { assets: [{ name: 'PrivyLock-macOS.zip', browser_download_url: 'https://example.com/malware.zip' }] })])[0];
  assert.deepEqual(releaseParagraphs(item.notes), ['First line', 'Second line']);
  assert.equal(item.downloadURL, null);
  assert.throws(() => normalizeReleases([release('v1', 'invalid')]));
  assert.throws(() => normalizeReleases([release('v1', '2026-01-01', { html_url: 'javascript:alert(1)' })]));
});
