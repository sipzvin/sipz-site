# sipz-site

The public website for [Sipz.vin](https://sipz.vin): a single page that says what it is and that it is **invite only**, plus a privacy
page. Plain HTML and CSS, no framework, no build step, no scripts, no tracking.

This repo holds the site and the infrastructure that serves it. The app and its API live in the `sipz` repository. Accounts-wide pieces
(the DNS zone, the GitHub OIDC provider) live in `sipz-foundation`; see [Where things live](#where-things-live).

## Layout

```
site/           what gets published: index.html, privacy.html, 404.html, style.css, assets/, robots.txt, sitemap.xml
mockup/         a standalone preview of the home page (open it in a browser; not deployed)
scripts/        check-site.mjs: checks the pages before a deploy
infra/          Terraform: private S3 bucket, CloudFront, certificate, DNS records, and a GitHub deploy role
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
- the page loads something from another site, or contains a script, inline style or event handler. The CloudFront policy in
  `infra/site.tf` blocks all of those, so a page that does would look fine here and break in production
- a placeholder such as `CONTACT_EMAIL_HERE` is still in a page

**It currently fails on purpose.** `site/privacy.html` needs a real contact email for deletion requests before this can go live.

## Infrastructure

`infra/` creates, in one AWS region (`eu-west-1`, plus `us-east-1` for the certificate only, because CloudFront accepts no other):

| Resource | Notes |
| --- | --- |
| S3 bucket | Private. Only this CloudFront distribution can read it, over TLS. Versioned, so a bad deploy can be undone. |
| CloudFront | HTTPS only, HTTP/3, security headers (HSTS, no framing, no sniffing, a policy that allows no scripts). `www` redirects to the bare domain. |
| ACM certificate | For the bare domain and `www`, validated through DNS. |
| Route 53 records | Point the domain at CloudFront. The hosted zone itself is created in `sipz-foundation`. |
| Deploy role | Lets GitHub Actions publish **without stored AWS keys** (OIDC). Only this repo's `main` branch can assume it, and it can only copy files to the bucket and clear the CDN cache. |

```bash
cd infra
terraform init
terraform validate
terraform plan        # nothing exists until you apply
```

> **Nothing here has been planned or applied.** Check which account you are in (`aws sts get-caller-identity`) before running
> `plan` or `apply`. The Terraform never sets a profile or account id; it uses whatever your environment points at.

Run the file checks any time without touching AWS: `node --test infra/infra.test.mjs`. They confirm the properties `validate` cannot see:
the bucket is never public, the deploy role cannot be assumed by any other repo or branch, the certificate is in `us-east-1`, and the
security headers are present.

### Going live, in order

1. Create `sipz-foundation` first (it owns the hosted zone and the OIDC provider) and apply it.
2. **Point the domain at Route 53:** copy the `name_servers` output into your registrar. The certificate cannot validate until you do.
3. Fill in the contact email in `site/privacy.html` and run `node scripts/check-site.mjs`.
4. Apply `infra/` with `github_repo = "nicolasarnold12321/sipz-site"`.
5. Deploy the files:

   ```bash
   aws s3 sync site/ "s3://$(terraform -chdir=infra output -raw bucket)" --delete
   aws cloudfront create-invalidation --distribution-id "$(terraform -chdir=infra output -raw distribution_id)" --paths '/*'
   ```

   After step 4, a GitHub Actions workflow can do this for you using the `deploy_role_arn` output. No access keys are stored anywhere.

## Where things live

| Repo | Holds |
| --- | --- |
| `sipz` | The Android app, the API (`server/`), the contract they share (`shared/`), and the API's own infrastructure |
| `sipz-site` (this repo) | The website and its S3 / CloudFront stack |
| `sipz-foundation` | Things that belong to the whole AWS account rather than to one app: the DNS zone, the GitHub OIDC provider, and (optionally) a VPC |

The zone and the OIDC provider are in `sipz-foundation` so that deleting the site or the API can never take DNS or the other's deploys
with it. This repo and the API both read the zone's id from it.

## Not done yet

- A contact email on the privacy page (the check above blocks a deploy until it is real)
- A GitHub Actions workflow to deploy on push to `main`
- A way to request an invite; the page currently says to ask someone who is already in
- No analytics, deliberately
