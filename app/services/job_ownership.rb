# frozen_string_literal: true

module JobOwnership
  OWNERS = %i[sidekiq oban].freeze
  LOCK_TIMEOUT = '5s'
  JOINT_KEYS = [%w[cron:lite_archival_warning_job command:mail.user.archival_approaching]].freeze
  class InconsistentOwners < StandardError; end

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

  def oban?(key)
    with_owner(key) { :sidekiq } == :not_owner
  end

  def lock_owner(key)
    return :sidekiq unless table?

    keys = joint_keys(key)
    keys.each do |owner_key|
      ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array(
                                              ['INSERT INTO phoenix.job_owners (key) VALUES (?) ' \
                                               'ON CONFLICT (key) DO NOTHING', owner_key]
                                            ))
    end
    owners = ActiveRecord::Base.connection.select_rows(ActiveRecord::Base.sanitize_sql_array(
                                                         ['SELECT key, owner FROM phoenix.job_owners ' \
                                                          'WHERE key IN (?) ORDER BY key FOR SHARE', keys]
                                                       ))
    raise InconsistentOwners, "joint job ownership disagrees for #{key}" unless owners.map(&:last).uniq.one?

    owners.first.last.to_sym
  end

  def release!(key, by:)
    put!(key, :sidekiq, pinned: true, by:)
  end

  def unpin!(key, by:)
    require_table!
    keys = joint_keys(key)
    with_lock_timeout do
      lock_keys(keys)
      ActiveRecord::Base.connection.update(ActiveRecord::Base.sanitize_sql_array(
                                             ['UPDATE phoenix.job_owners SET pinned = false, updated_at = now(), ' \
                                              'updated_by = ? WHERE key IN (?)', by, keys]
                                           ))
    end
    keys
  end

  def put!(key, owner, pinned:, by:)
    raise ArgumentError, "unknown owner #{owner}" unless OWNERS.include?(owner.to_sym)

    Geocoding::RateLimiter.guard_claim!(key) if owner.to_sym == :oban

    require_table!
    sql = <<~SQL.squish
      INSERT INTO phoenix.job_owners (key, owner, pinned, updated_at, updated_by) VALUES (?, ?, ?, now(), ?)
      ON CONFLICT (key) DO UPDATE SET owner = EXCLUDED.owner, pinned = EXCLUDED.pinned,
        updated_at = EXCLUDED.updated_at, updated_by = EXCLUDED.updated_by
    SQL
    keys = joint_keys(key)
    with_lock_timeout do
      keys.each do |joint_key|
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([sql, joint_key, owner.to_s, pinned, by])
        )
      end
    end
    keys
  end

  def joint_keys(key)
    (JOINT_KEYS.find { |keys| keys.include?(key) } || [key]).sort
  end

  def lock_keys(keys)
    ActiveRecord::Base.connection.select_rows(ActiveRecord::Base.sanitize_sql_array(
                                                ['SELECT key FROM phoenix.job_owners WHERE key IN (?) ' \
                                                 'ORDER BY key FOR UPDATE', keys]
                                              ))
  end

  def with_lock_timeout
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
      yield
    end
  end

  private_class_method :with_lock_timeout

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
