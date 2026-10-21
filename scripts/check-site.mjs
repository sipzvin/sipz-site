// Check the built site the way a visitor would meet it: every local link and asset exists, every page has the basics, nothing points off-site
// by accident, and no placeholder is left in. Run before every deploy:  node scripts/check-site.mjs
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, normalize } from 'node:path';

const root = new URL('../site/', import.meta.url).pathname;
const pages = readdirSync(root).filter((f) => f.endsWith('.html'));
const problems = [];

const walk = (d) => readdirSync(d).flatMap((n) => (statSync(join(d, n)).isDirectory() ? walk(join(d, n)) : [join(d, n)]));
const files = walk(root);

for (const f of pages) {
  const html = readFileSync(join(root, f), 'utf8');
  const need = (ok, msg) => { if (!ok) problems.push(`${f}: ${msg}`); };
  need(/<html[^>]+lang="/.test(html), 'no lang attribute');
  need(/<meta name="viewport"/.test(html), 'no viewport meta, so it will not scale on a phone');
  need(/<title>[^<]{3,}<\/title>/.test(html), 'no title');
  if (f !== '404.html') need(/<meta name="description" content="[^"]{20,}/.test(html), 'no description');
  need(!/CONTACT_EMAIL_HERE|TODO|FIXME|lorem ipsum/i.test(html), 'a placeholder is still in the page');
  need(!/<script[^>]+src=["']https?:/i.test(html), 'loads a script from another site');
  need(!/<link[^>]+href=["']https?:\/\/(?!sipz\.vin)/i.test(html), 'loads a stylesheet from another site');
  need((html.match(/<h1\b/g) ?? []).length === 1, 'should have exactly one h1');
  for (const m of html.matchAll(/<img\b[^>]*>/g)) need(/\balt=/.test(m[0]), `image with no alt text: ${m[0].slice(0, 60)}`);
  // every local reference resolves to a real file
  for (const m of html.matchAll(/(?:href|src)=["']([^"'#?]+)(?:[?#][^"']*)?["']/g)) {
    const ref = m[1];
    if (/^(https?:|mailto:|tel:|data:)/.test(ref)) continue;
    const target = ref.startsWith('/') ? join(root, ref) : normalize(join(dirname(join(root, f)), ref));
    need(ref === '/' || existsSync(target), `links to ${ref}, which does not exist`);
  }
}
// GitHub Pages cannot set response headers, so the Content-Security-Policy travels in a <meta> tag on every page. This checks the tag is there
// and that each page obeys it. A page that breaks its own policy would be silently blocked in the browser while looking fine here.
// (frame-ancestors cannot be set from a meta tag at all, only as a header, so framing cannot be forbidden on this host.)
for (const f of pages) {
  const html = readFileSync(join(root, f), 'utf8');
  const csp = /<meta http-equiv="Content-Security-Policy" content="([^"]+)"/.exec(html)?.[1] ?? '';
  if (!csp) { problems.push(`${f}: has no Content-Security-Policy meta tag`); continue; }
  if (/frame-ancestors/.test(csp)) problems.push(`${f}: frame-ancestors in a meta tag is ignored by browsers; remove it so nobody thinks framing is blocked`);
  if (/script-src 'none'/.test(csp) && /<script\b/i.test(html)) problems.push(`${f}: has a <script>, but its policy says script-src 'none', so it would be blocked`);
  if (/style-src 'self'/.test(csp) && (/<style\b/i.test(html) || /\sstyle=/i.test(html))) problems.push(`${f}: has inline styles, but its policy says style-src 'self'`);
  if (/\son[a-z]+=/i.test(html)) problems.push(`${f}: has an inline event handler, which its policy blocks`);
}
// .nojekyll stops Pages running Jekyll over the folder. (No CNAME file: when deploying with an Actions workflow, GitHub ignores it. The custom
// domain is set in the repository's Pages settings.)
if (!existsSync(join(root, '.nojekyll'))) problems.push('missing .nojekyll');
for (const f of ['robots.txt', 'sitemap.xml', 'style.css', 'favicon.png']) if (!existsSync(join(root, f))) problems.push(`missing ${f}`);
const sitemap = existsSync(join(root, 'sitemap.xml')) ? readFileSync(join(root, 'sitemap.xml'), 'utf8') : '';
for (const m of sitemap.matchAll(/<loc>https:\/\/sipz\.vin\/([^<]*)<\/loc>/g)) if (m[1] && !existsSync(join(root, m[1]))) problems.push(`sitemap lists /${m[1]}, which does not exist`);
const total = files.reduce((n, f) => n + statSync(f).size, 0);
if (total > 1_000_000) problems.push(`the site is ${(total / 1024).toFixed(0)} KB; a page like this should be well under 1 MB`);

if (problems.length) { console.error(problems.map((p) => '  - ' + p).join('\n')); console.error(`\n${problems.length} problem(s)`); process.exit(1); }
console.log(`site OK: ${pages.length} pages, ${files.length} files, ${(total / 1024).toFixed(0)} KB`);
