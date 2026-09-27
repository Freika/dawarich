# frozen_string_literal: true

module JobOwnership
  OWNERS = %i[sidekiq oban].freeze

  module_function

  def with_owner(key, runtime = :sidekiq)
    ActiveRecord::Base.transaction do
      owner = lock_owner(key)
      if owner == runtime.to_sym
        yield
      else
        Rails.logger.info("JobOwnership: #{key} owned by #{owner}, skipped")
        :not_owner
      end
    end
  end

  def lock_owner(key)
    return :sidekiq unless table?

    owner = ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(['SELECT owner FROM phoenix.job_owners WHERE key = ? FOR SHARE', key])
    )
    owner == 'oban' ? :oban : :sidekiq
  end

  def release!(key, by:)
    put!(key, :sidekiq, pinned: true, by:)
  end

  def unpin!(key, by:)
    require_table!
    ActiveRecord::Base.connection.update(ActiveRecord::Base.sanitize_sql_array(
                                           ['UPDATE phoenix.job_owners SET pinned = false, updated_at = now(), ' \
                                            'updated_by = ? WHERE key = ?', by, key]
                                         ))
  end

  def put!(key, owner, pinned:, by:)
    raise ArgumentError, "unknown owner #{owner}" unless OWNERS.include?(owner.to_sym)

    require_table!
    sql = <<~SQL.squish
      INSERT INTO phoenix.job_owners (key, owner, pinned, updated_at, updated_by) VALUES (?, ?, ?, now(), ?)
      ON CONFLICT (key) DO UPDATE SET owner = EXCLUDED.owner, pinned = EXCLUDED.pinned,
        updated_at = EXCLUDED.updated_at, updated_by = EXCLUDED.updated_by
    SQL
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([sql, key, owner.to_s, pinned, by]))
  end

  def table?
    ActiveRecord::Base.connection.select_value("SELECT to_regclass('phoenix.job_owners') IS NOT NULL")
  end

  def require_table!
    return if table?

    raise 'phoenix.job_owners does not exist: Phoenix has never migrated this database, so every job runs in Sidekiq'
  end

  def operator
    "rake:#{ENV.fetch('USER', 'unknown')}"
  end
end
