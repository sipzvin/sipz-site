# sipz-site

The public website for [Sipz.vin](https://sipz.vin): a single page that says what it is and that it is **invite only**, plus a privacy
page. Plain HTML and CSS, no framework, no build step, no scripts, no tracking. Published with **GitHub Pages**.

The app and its API live in the `sipz` repository; account-wide AWS pieces live in `sipz-foundation`.

## Layout

```
site/                what gets published: index.html, privacy.html, 404.html, style.css, assets/, robots.txt, sitemap.xml
mockup/              a standalone preview of the home page (open it in a browser; not deployed)
scripts/             check-site.mjs: checks the pages before a deploy
.github/workflows/   pages.yml: checks, then publishes site/ on every push to main
```

## Edit the site

Open `site/index.html` in a browser, or serve the folder: `npx serve site`. Then run the check:

```bash
node scripts/check-site.mjs
```

It fails if any of these are wrong, because each would only show up after deploying:
- a link, image, stylesheet or sitemap entry points at a file that does not exist
- a page is missing a title, a description, a language or the mobile viewport tag
- there is not exactly one `<h1>`, or an image has no alt text
- a page has no Content-Security-Policy `<meta>` tag, or breaks its own policy (a script, an inline style or an event handler)
- the page loads something from another site
- a placeholder such as `CONTACT_EMAIL_HERE` is still in a page

**It currently fails on purpose.** `site/privacy.html` needs a real contact email for deletion requests before this can go live. The
deploy workflow runs the same check first, so nothing with a placeholder can be published.

## Publish it (once)

1. **Repository visibility.** GitHub Pages from a *private* repository needs a paid GitHub plan (the documentation mentions Enterprise Cloud; I
   could not confirm anything about other plans). On the free plan the repository has to be **public**. Everything in it is meant to be
   public anyway; check there is nothing in the history you would not want seen first.
2. **Settings → Pages → Source: GitHub Actions.**
3. **Settings → Pages → Custom domain: `sipz.vin`.** Do this **before** step 4. GitHub's documentation warns that creating the DNS records first
   can let someone else claim the domain on GitHub in between.
4. **DNS** (wherever the domain's DNS is hosted; see below):

   | Name | Type | Value |
   | --- | --- | --- |
   | `sipz.vin` | A | `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153` |
   | `sipz.vin` | AAAA (optional) | `2606:50c0:8000::153`, `2606:50c0:8001::153`, `2606:50c0:8002::153`, `2606:50c0:8003::153` |
   | `www.sipz.vin` | CNAME | `sipzvin.github.io` |

   Those addresses are from GitHub's own documentation for custom domains; check them there before relying on them, as they can change.
   With both the apex and `www` set up, GitHub redirects between them.
5. **Settings → Pages → Enforce HTTPS**, once GitHub offers it (it can take up to 24 hours after DNS is correct).
6. Push to `main`. The workflow checks the site and publishes it.

### Where the DNS lives
Either works; this is your call.
- **At the registrar** (Namecheap): add the records above in its DNS settings. Simplest, and nothing in AWS is involved for the site.
- **In Route 53**, in the zone `sipz-foundation` creates: add the same records there, and set the name servers at the registrar to the zone's.
  Worth it if the API will also live on `sipz.vin` (for example `api.sipz.vin`) and you want all the records in one place.

## What GitHub Pages cannot do (compared with the S3 + CloudFront setup this replaced)

The previous setup (a private S3 bucket behind CloudFront, written in Terraform and never applied) is gone from this repo. The differences:
- **No response headers.** The old setup sent HSTS and a `frame-ancestors 'none'` policy. Pages cannot set headers, so the Content-Security-Policy is
  now a `<meta>` tag on each page, and **`frame-ancestors` cannot be set that way at all**: the site could be shown inside someone else's frame.
  For a page with no login, form or script, the practical risk is small. "Enforce HTTPS" covers the transport side.
- **Public repository** on the free plan, as above.

## Not done yet
- A contact email on the privacy page (the check blocks a deploy until it is real)
- A way to request an invite; the page currently says to ask someone who is already in
- No analytics, deliberately
