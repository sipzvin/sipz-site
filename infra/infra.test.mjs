// Properties of the Terraform that `terraform validate` cannot see: it would apply cleanly and still be wrong. These read the files as text.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const dir = new URL('./', import.meta.url);
const tf = Object.fromEntries(readdirSync(dir).filter((f) => f.endsWith('.tf')).map((f) => [f, readFileSync(new URL(f, dir), 'utf8')]));
const all = Object.values(tf).join('\n');
const block = (text, header) => { const i = text.indexOf(header); assert.ok(i >= 0, `no ${header}`); const j = text.indexOf('\n}\n', i); return text.slice(i, j + 3); };

test('the site bucket blocks every kind of public access, and only CloudFront can read it', () => {
  const b = block(tf['site.tf'], 'resource "aws_s3_bucket_public_access_block" "site"');
  for (const k of ['block_public_acls', 'block_public_policy', 'ignore_public_acls', 'restrict_public_buckets']) assert.match(b, new RegExp(`${k}\\s*=\\s*true`), k);
  const pol = block(tf['site.tf'], 'data "aws_iam_policy_document" "bucket"');
  assert.match(pol, /cloudfront\.amazonaws\.com/);
  assert.match(pol, /AWS:SourceArn/, 'read access is tied to THIS distribution, not any CloudFront');
  assert.match(pol, /aws:SecureTransport/, 'plain-HTTP requests are refused');
  assert.doesNotMatch(pol, /identifiers\s*=\s*\["\*"\][\s\S]{0,80}actions\s*=\s*\["s3:GetObject"\]/, 'no public read');
});

test('CloudFront reads the bucket through origin access control, never a public website endpoint', () => {
  assert.match(tf['site.tf'], /origin_access_control_id/);
  assert.doesNotMatch(all, /aws_s3_bucket_website_configuration/);
  assert.match(tf['site.tf'], /viewer_protocol_policy\s*=\s*"redirect-to-https"/);
  assert.match(tf['site.tf'], /minimum_protocol_version\s*=\s*"TLSv1\.2_2021"/);
});

test('the certificate is in us-east-1, which is the only place CloudFront accepts one', () => {
  assert.match(block(tf['certificate.tf'], 'resource "aws_acm_certificate" "site"'), /provider\s*=\s*aws\.us_east_1/);
  assert.match(block(tf['certificate.tf'], 'resource "aws_acm_certificate_validation" "site"'), /provider\s*=\s*aws\.us_east_1/);
});

test('the site does not own the hosted zone: it takes the id from sipz-foundation, where the zone cannot be destroyed', () => {
  assert.doesNotMatch(tf['zone.tf'], /resource "aws_route53_zone"/, 'the zone lives in sipz-foundation');
  assert.match(tf['variables.tf'], /variable "route53_zone_id"/);
  assert.doesNotMatch(tf['outputs.tf'], /output "name_servers"/, 'the registrar step belongs to sipz-foundation');
  const dns = readFileSync(new URL('../../sipz-foundation/terraform/dns.tf', import.meta.url), 'utf8');
  assert.match(block(dns, 'resource "aws_route53_zone"'), /prevent_destroy\s*=\s*true/);
});

test('the security headers are on: HSTS, no sniffing, no framing, and a policy that allows no scripts', () => {
  const h = block(tf['site.tf'], 'resource "aws_cloudfront_response_headers_policy" "site"');
  for (const k of ['strict_transport_security', 'content_type_options', 'frame_options', 'referrer_policy', 'content_security_policy']) assert.match(h, new RegExp(k), k);
  assert.match(h, /access_control_max_age_sec\s*=\s*63072000/);
  assert.match(h, /default-src 'none'/);
  assert.match(h, /script-src 'none'/);
  assert.match(h, /frame-ancestors 'none'/);
  assert.doesNotMatch(h, /unsafe-inline|unsafe-eval|\*/, 'no wildcards or unsafe directives');
});

test('missing pages return a real 404 with the right status code, not a 200 or a raw S3 error', () => {
  const d = block(tf['site.tf'], 'resource "aws_cloudfront_distribution" "site"');
  assert.equal((d.match(/response_code\s*=\s*404/g) ?? []).length, 2, 'both S3 403 and 404 map to a 404');
  assert.match(d, /response_page_path\s*=\s*"\/404\.html"/);
});

test('www redirects to the bare domain and the redirect cannot be turned into an open redirect', () => {
  const f = block(tf['site.tf'], 'resource "aws_cloudfront_function" "redirect_www"');
  assert.match(f, /statusCode: 301/);
  assert.match(f, /location: \{ value: 'https:\/\/\$\{var\.domain\}' \+ r\.uri \}/, 'the destination host is fixed, only the path is passed on');
  assert.doesNotMatch(f, /event\.request\.querystring|headers\.host\.value\s*\+/, 'never builds a destination from the Host header');
});

test('deploying uses OIDC, not stored keys, and only the named repo and branch can assume the role', () => {
  assert.doesNotMatch(all, /aws_iam_access_key|aws_iam_user\b/, 'no long-lived keys exist');
  const t = block(tf['deploy.tf'], 'data "aws_iam_policy_document" "deploy_trust"');
  assert.match(t, /sts:AssumeRoleWithWebIdentity/);
  assert.match(t, /token\.actions\.githubusercontent\.com:sub/);
  assert.match(t, /StringEquals/, 'an exact match, not StringLike with a wildcard');
  assert.match(t, /repo:\$\{var\.github_repo\}:ref:refs\/heads\/\$\{var\.deploy_branch\}/);
  assert.doesNotMatch(t, /StringLike|:\*"|repo:\*/, 'no wildcard in who may deploy');
});

test('the deploy role can do exactly what a deploy does and nothing wider', () => {
  const p = block(tf['deploy.tf'], 'data "aws_iam_policy_document" "deploy"');
  const actions = [...p.matchAll(/"((?:s3|cloudfront|route53|iam|dynamodb|lambda|\*)[:\w*]*)"/g)].map((m) => m[1]).sort();
  assert.deepEqual(actions, ['cloudfront:CreateInvalidation', 's3:DeleteObject', 's3:GetObject', 's3:ListBucket', 's3:PutObject']);
  assert.doesNotMatch(p, /resources\s*=\s*\["\*"\]/, 'every permission is tied to this bucket or this distribution');
});

test('every input that can be set wrongly is validated', () => {
  const v = tf['variables.tf'];
  assert.match(block(v, 'variable "domain"'), /validation/);
  assert.match(block(v, 'variable "github_repo"'), /validation/);
});

test('nothing in the stack contains a secret, an account id, or a hard-coded profile', () => {
  assert.doesNotMatch(all, /AKIA[0-9A-Z]{16}|aws_secret|profile\s*=|\b\d{12}\b/);
});
