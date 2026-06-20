# frozen_string_literal: true

module Points
  module Archival
    # Transaction-scoped advisory lock for serializing a single user's archival
    # lifecycle. Unlike the session-scoped `pg_advisory_lock` (used by the
    # with_advisory_lock gem), `pg_advisory_xact_lock` is held for the duration
    # of the surrounding transaction and is therefore safe under PgBouncer
    # transaction pooling, where the lock and the work it guards must run on the
    # same backend. The two-key form keeps these locks in a separate space from
    # any single-key advisory locks elsewhere in the app.
    module AdvisoryLock
      NAMESPACE = 2_026

      module_function

      def with_lock(user_id)
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.sanitize_sql_array(
              ['SELECT pg_advisory_xact_lock(?, ?)', NAMESPACE, user_id.to_i]
            )
          )
          yield
        end
      end
    end
  end
end
