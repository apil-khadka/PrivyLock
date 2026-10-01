# PrivyLock website

Product pages, user guides, and release history are a standalone Astro package.
The site publishes to https://apil-khadka.github.io/PrivyLock/ using GitHub Pages.

## Local development

Use Node 22.12 or later.

```sh
cd docs
npm ci
npm run dev
```

Open http://127.0.0.1:4321/PrivyLock/.
The base path is required locally and on GitHub Pages.

```sh
npm run sync:github  # refresh the committed public metadata snapshot
npm run check       # metadata tests and production build
npm run preview     # serve the generated site locally
```

## Structure

- `src/pages/`: product page, documentation, and releases.
- `src/layouts/`: shared site and documentation shells.
- `src/components/`: navigation, code-copy controls, and release entries.
- `src/styles/global.css`: supplied thistle, pink, and blue theme tokens.
- `src/data/github.json`: public repository and release snapshot.
- `scripts/sync-github.mjs`: bounded GitHub API requests and validated metadata.
- `public/assets/`: product imagery.

Inter and Poppins are pinned npm dependencies and served locally.
Documentation uses Inter for body copy and Poppins for headings.
Internal review artifacts outside `src/` and `public/` are not published.

## Automatic updates

The header fetches the public star count on a visit and caches it for five minutes in session storage.
No GitHub token is included in the browser.
If requests fail or storage is blocked, the site retains a usable count from the last deployment.
Zero stars is displayed correctly.
There are no polling intervals or background refresh loops.

The Pages workflow refreshes releases on publication, edits, deletion, successful native-release workflows, manual dispatch, and every six hours.
The native-release workflow completion trigger also covers releases created with GitHub's built-in Actions token.
The scheduled refresh does not commit generated changes back to the repository.
Local synchronization falls back to the committed snapshot on failure; CI uses `--strict` and fails instead of silently publishing stale metadata.

Edit release notes on GitHub releases rather than maintaining a second version list.
The latest stable download ignores prereleases.
Raw release text is escaped by Astro rather than rendered as HTML.

## Deployment

`.github/workflows/pages.yml` installs with `npm ci`, tests, syncs GitHub metadata, builds, and deploys `docs/dist`.
Pull requests build without deploying.
Set the repository's Pages build source to GitHub Actions.
Actions are pinned to commit hashes, and only the deploy job has Pages write permissions.

Keep installation and security claims aligned with published versions.
Add guides under `src/pages/docs/` and link them in `src/lib/site.ts`.
