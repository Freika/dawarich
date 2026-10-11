# Group C API golden captures

The terminal API oracle is Rails. Locations/photos, map reads, stats and visits
use the Rails captures checked into `app-phoenix/test/golden_captures/`. Notes
retain their complete existing Rails fixture. These captures are independent of
the historical ignored fixture symlink.

The assigned parity emitters record response status, normalized headers, complete
text or binary response bodies, and database after-state. Rails exception handling
is enabled with `show_exceptions: :all` and detailed exceptions disabled; rescued
exceptions must retain the response Rails actually renders. The comparator and
its normalization are unchanged.

`GroupCCapture` merges selected Rails cases by name. Set
`WRITE_PHOENIX_FIXTURES=1` only for an authorized Rails capture; without it the
helper verifies existing bytes. `API_GOLDEN_CASES` limits refreshed cases. Use
`GROUP_C_CAPTURE=1` for locations/photos to exclude the separate closure corpus.
Use the controller-assigned private Rails database and Redis environment, and
restore the swagger file after each RSpec batch. Never generate expected output
from Phoenix.

The refreshed cases preserve Rails permissive coordinate/date parsing, historical
HTTP dates, response wrapping, provider request paths, provider JSON order and
nearby-place cache effects. Every assigned golden checks the terminal response and
recorded database effects, including formerly deferred cases.

Photo thumbnail redirects follow only within the configured origin and retain the
existing FRB-011 cross-host credential refusal. Both the provider unit test and
the endpoint ownership test remain required callers of this code.

Golden case data is loaded at runtime for each generated test rather than embedded
as large compile-time literals. The case names remain separate ExUnit tests.
The focused native-time test runs asynchronously; endpoint cases retain their
existing synchronous templates because they alter process-wide environment and
cache configuration.

The implementation report records capture provenance, named RED/GREEN/mutation
evidence and the two targeted seeds. No full-suite acceptance or G44 is included
in this fix round. AFFiNE synchronization is pending because this controller brief
prohibits remote writes.
