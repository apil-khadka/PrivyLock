import { readFile, rename, writeFile } from 'node:fs/promises';
import { repository, normalizeRepository, normalizeReleases } from '../src/lib/github.mjs';
const output = new URL('../src/data/github.json', import.meta.url);
const headers = { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' };
if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
async function get(path) {
  const response = await fetch(`https://api.github.com/repos/${repository}${path}`, { headers, signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error(`GitHub returned ${response.status}`);
  return response.json();
}
try {
  const [repo, releases] = await Promise.all([get(''), get('/releases?per_page=100')]);
  const snapshot = { updatedAt: new Date().toISOString(), repository: normalizeRepository(repo), releases: normalizeReleases(releases) };
  const temporary = new URL(`${output.href}.tmp`);
  await writeFile(temporary, `${JSON.stringify(snapshot, null, 2)}\n`);
  await rename(temporary, output);
  console.log(`Updated ${snapshot.repository.stars} stars and ${snapshot.releases.length} releases.`);
} catch (error) {
  if (process.argv.includes('--strict')) throw error;
  await readFile(output);
  console.warn(`${error.message}. Keeping the last GitHub snapshot.`);
}
