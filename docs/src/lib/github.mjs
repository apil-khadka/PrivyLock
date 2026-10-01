export const repository = 'apil-khadka/PrivyLock';
export const repositoryURL = `https://github.com/${repository}`;
export function normalizeRepository(value) {
  if (value.full_name !== repository || !Number.isSafeInteger(value.stargazers_count) || value.stargazers_count < 0) throw new Error('Invalid repository response');
  return { name: repository, url: repositoryURL, stars: value.stargazers_count };
}
export function normalizeReleases(values) {
  if (!Array.isArray(values)) throw new Error('Invalid release response');
  return values.filter(v => !v.draft && v.published_at).map(v => {
    if (typeof v.tag_name !== 'string' || !v.html_url?.startsWith(`${repositoryURL}/releases/tag/`) || !Number.isFinite(Date.parse(v.published_at))) throw new Error('Invalid release metadata');
    const asset = v.assets?.find(a => a.name === 'PrivyLock-macOS.zip' && a.browser_download_url?.startsWith(`${repositoryURL}/releases/download/`));
    const checksum = v.assets?.find(a => a.name === 'PrivyLock-macOS.zip.sha256' && a.browser_download_url?.startsWith(`${repositoryURL}/releases/download/`));
    return { tag: v.tag_name, name: v.name || v.tag_name, publishedAt: v.published_at, url: v.html_url, prerelease: Boolean(v.prerelease), notes: (v.body || 'See this release on GitHub for details.').replace(/\\n/g, '\n').replace(/[\u2013\u2014]/g, ' - '), downloadURL: asset?.browser_download_url || null, downloadSize: asset?.size || null, checksumURL: checksum?.browser_download_url || null };
  }).sort((a, b) => Date.parse(b.publishedAt) - Date.parse(a.publishedAt));
}
export function latestStable(releases) { return releases.find(r => !r.prerelease) || null; }
export function releaseParagraphs(notes) { return notes.split(/\n+/).map(line => line.replace(/^[-*]\s+/, '').trim()).filter(Boolean); }
