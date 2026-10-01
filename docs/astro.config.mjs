import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://apil-khadka.github.io',
  base: '/PrivyLock',
  output: 'static',
  trailingSlash: 'always',
  devToolbar: { enabled: false },
});
