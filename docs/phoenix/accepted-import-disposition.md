# Accepted import disposition

Every accepted import keeps an executor until terminal settlement. The import lease,
stored executing job/attempt/argument fence, actor locks and run token remain the
processing authority. A processed event acknowledges a completed effect or a
durable handoff; it is not evidence that the import itself has already completed.

| Mode and input | Disposition |
| --- | --- |
| Supported normal import or GPX discovered by a normal job, either mode | Current normal Oban job processes it. Failure status, localized notification and terminal attachment receipt commit in one fenced transaction. Retry acknowledges the receipt without repeating failure effects. |
| Successful normal or dedicated GPX import with zero points, either mode | Final no-points notification, completed status and terminal attachment receipt commit in one fenced transaction. An interruption rolls them back together; a successor commits one notice, and terminal replay only acknowledges the receipt. |
| Normal job edited to GPX before admission, standalone | The current normal job admits the supported GPX adapter without requiring an older receipt. |
| Native legacy envelope or changed-source continuation, coexistence | Publish a durable Rails resume with `native_fallback=true` where the current native worker cannot process the source. Lane ownership stays fixed; Rails resumes the accepted import instead of forwarding it back into the rejected native parser. |
| Native legacy or unsupported continuation, standalone | Native processing or transactional failed status plus localized failure notification and processed acknowledgement. A finite error retry chain cannot abandon an accepted row. |
| ZIP parent with pending children, either mode | Persist fanout and queue each accepted child once; snooze the parent until every child is completed/failed or has a native removal receipt or completed Rails handoff. |
| Partial ZIP build failure | Queue previously accepted children, retain the archive error, and defer the parent's failure notification until those children are terminal. Unaccepted reservations do not block settlement. |
| ZIP parent with all children terminal | Preserve archive removal, cleanup publication and one parent acknowledgement. Child notifications remain unchanged. Child readiness and settlement share one fenced transaction; busy child rows cause a snooze, and shared child locks protect the terminal decision through removal. |

Coexistence intentionally retains the executable source fallback. This is not
source retirement or H03/H04/G49 closure. SQL-only observations cannot prove that
Rails source work has drained. Standalone produces no Rails resume commands.
Cloud lifecycle refusal remains unchanged in every mode.

The ZIP ordering requirement differs from Rails: Rails removes a successful ZIP
parent immediately after enqueueing its members, and a later child validation
failure can bypass enqueueing earlier accepted members. Phoenix waits for child
terminal states on both success and failure. Existing archive unit tests explicitly
acknowledge child terminal states at their component boundary; the real-upload and
partial-build regressions execute the actual child workers.

Regression counterparts are `standalone_zip_test.exs`,
`interrupted_failure_test.exs`, `accepted_disposition_test.exs`, and
`partial_zip_disposition_test.exs`, and `legacy_zip_child_test.exs` under `app-phoenix/test/dawarich/imports/`.
`interrupted_empty_success_test.exs` executes empty GPX and KML through the real
normal worker in each mode. A notification trigger advances only the executing
job's attempt; retry and terminal replay must preserve one no-points notice.
A removed legacy archive child remains pending while its Rails handoff is pending;
only its completed handoff authorizes the outer native parent to settle. A failed
standalone legacy child is terminal status 3 and produces one failure notice.

Shared imports/source-execution history is indexed in AFFiNE document
`OICwyQJkkxfUDp6macMX9`; assignment report synchronization is controller-owned.
