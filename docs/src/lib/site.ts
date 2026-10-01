export function withBase(path = '') {
  return `${import.meta.env.BASE_URL.replace(/\/$/, '')}/${path.replace(/^\/+/, '')}`;
}
export const docsNavigation = [
  ['Overview', 'docs/'], ['Getting started', 'docs/getting-started/'],
  ['Security', 'docs/security/'], ['Troubleshooting', 'docs/troubleshooting/'],
  ['Development', 'docs/development/'],
];
