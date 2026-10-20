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
  need(!/<link[^>]+href=["']https?:\/\/(?!sipz\.wine)/i.test(html), 'loads a stylesheet from another site');
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
// The CloudFront policy (infra/site.tf) forbids scripts, styles from elsewhere and inline styles. A page that breaks those rules
// would be silently blocked in production while looking fine here, so catch it before deploy.
const tf = readFileSync(new URL('../infra/site.tf', import.meta.url), 'utf8');
const csp = /content_security_policy = "([^"]+)"/.exec(tf)?.[1] ?? '';
if (!csp) problems.push('infra/site.tf has no content security policy');
for (const f of pages) {
  const html = readFileSync(join(root, f), 'utf8');
  if (/script-src 'none'/.test(csp) && /<script\b/i.test(html)) problems.push(`${f}: has a <script>, but the CloudFront policy says script-src 'none', so it would be blocked`);
  if (/style-src 'self'/.test(csp) && (/<style\b/i.test(html) || /\sstyle=/i.test(html))) problems.push(`${f}: has inline styles, but the policy says style-src 'self'`);
  if (/\son[a-z]+=/i.test(html)) problems.push(`${f}: has an inline event handler, which the policy blocks`);
}
for (const f of ['robots.txt', 'sitemap.xml', 'style.css', 'favicon.png']) if (!existsSync(join(root, f))) problems.push(`missing ${f}`);
const sitemap = existsSync(join(root, 'sitemap.xml')) ? readFileSync(join(root, 'sitemap.xml'), 'utf8') : '';
for (const m of sitemap.matchAll(/<loc>https:\/\/sipz\.wine\/([^<]*)<\/loc>/g)) if (m[1] && !existsSync(join(root, m[1]))) problems.push(`sitemap lists /${m[1]}, which does not exist`);
const total = files.reduce((n, f) => n + statSync(f).size, 0);
if (total > 1_000_000) problems.push(`the site is ${(total / 1024).toFixed(0)} KB; a page like this should be well under 1 MB`);

if (problems.length) { console.error(problems.map((p) => '  - ' + p).join('\n')); console.error(`\n${problems.length} problem(s)`); process.exit(1); }
console.log(`site OK: ${pages.length} pages, ${files.length} files, ${(total / 1024).toFixed(0)} KB`);
