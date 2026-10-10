# Pending-import cleanup

Native cleanup remains default off until the pending-import cron is registered and explicitly claimed.
It selects at most 1,000 expired unclaimed or strictly older-than-seven-day claimed records per batch.
Shared attachments keep their blob and object; cleanup removes only the pending-import attachment.

ED522: an unshared candidate retains its row, attachment and blob until an internal Oban purge confirms
object deletion. Rails removes these references on its synchronous purge or queued purge path.
The continuation binds the original pending-import, attachment and blob IDs and rechecks eligibility,
identity and other attachments under locks. A replacement attachment or newly shared blob survives.
Disk deletion errors, unsafe paths and failed S3 DELETE responses preserve recoverable work for retry.
Confirmed missing objects permit final metadata deletion. Accepted purge work completes after cron release.
