# Digest email delivery

Monthly and yearly digest email jobs require `DawarichSettings.email_configured?`,
which checks that `SMTP_SERVER` is present. An unset, empty or whitespace-only
value skips mail enqueueing and leaves the digest, including `sent_at`, unchanged.
The legacy `Users::Digests::EmailSendingJob` inherits the yearly behavior.

Digest calculation and in-app availability are independent of this email guard.
With SMTP configured, existing user email preferences, missing/empty digest
checks and the `sent_at` duplicate guard still apply. `sent_at` records mail
enqueueing; it does not guarantee successful SMTP delivery.

Configuring SMTP later does not add an automatic catch-up mailing of skipped
digests. This change does not remove previously queued or dead mail delivery jobs.

Regression coverage: `spec/regressions/digest_emails_without_smtp_spec.rb`.
Issue: <https://github.com/Freika/dawarich/issues/3932>.
Review: <https://onedev.dwri.xyz/dawarich/~pulls/259>.
Knowledge index: [Dawarich — Open issue priorities](https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/2tgruNB7k104KlD136MUh).
