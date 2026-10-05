# frozen_string_literal: true

module NonTransactionalConcurrency
  # Only the tables that the duplicate-tracks regression specs mutate. Each
  # spec creates its own user via `let(:user) { create(:user) }`, so leave
  # `users` and unrelated tables alone — deleting their rows between examples
  # would wipe state shared with other specs running in the same process.
  TABLES_TO_DELETE = %w[track_segments tracks points].freeze

  def self.delete_all
    conn = ActiveRecord::Base.connection
    existing = conn.tables & TABLES_TO_DELETE
    return if existing.empty?

    FixtureCleanup.delete!(existing)
  end

  def self.newest_user_id
    User.unscoped.maximum(:id).to_i
  end

  def self.delete_users_created_after(user_id)
    created = User.unscoped.where('id > ?', user_id)
    [Import, Export, Place].each { |model| model.where(user_id: created.select(:id)).delete_all }
    created.delete_all
  end
end

RSpec.configure do |config|
  # rspec-rails reads `use_transactional_tests` from the example class at
  # `setup_fixtures` time (via `before_setup`), which runs BEFORE any RSpec
  # `before(:each)` hook. Setting the flag inside `before(:each)` would be
  # too late and the example would still run inside a wrapping transaction —
  # defeating the cross-thread visibility the concurrency specs depend on.
  # `before(:context)` runs once per example group, before any example sets
  # up its fixtures, and `self.class` resolves to the describe block class.
  config.before(:context, :non_transactional) do
    self.class.use_transactional_tests = false
  end

  # Restore the default after the group finishes. The flag is class-level state
  # on the example class — without this, any later untagged `it` block added
  # inside a `:non_transactional` describe would silently run without a
  # wrapping transaction and dirty the shared DB.
  config.after(:context, :non_transactional) do
    self.class.use_transactional_tests = true
  end

  config.before(:each, :non_transactional) do |example|
    required_threads = example.metadata[:threads] || 2
    pool_size = ActiveRecord::Base.connection_pool.size
    if pool_size < required_threads
      raise(
        "Non-transactional spec needs DB pool size >= #{required_threads}, got #{pool_size}. " \
        'Run with `RAILS_MAX_THREADS=10 bundle exec rspec ...` or raise the test pool ' \
        'in config/database.yml.'
      )
    end

    # The first non_transactional example in a run can inherit data created by
    # earlier transactional specs that wrote outside the wrapping transaction
    # (e.g. via `before(:all)` or jobs). Start clean.
    NonTransactionalConcurrency.delete_all
  end

  config.after(:each, :non_transactional) do
    NonTransactionalConcurrency.delete_all
  end

  config.around(:each, :non_transactional) do |example|
    newest_user_id = NonTransactionalConcurrency.newest_user_id
    connection = ActiveRecord::Base.connection
    owner_keys = connection.select_values('SELECT key FROM phoenix.job_owners')
    example.run
  ensure
    NonTransactionalConcurrency.delete_users_created_after(newest_user_id)
    quoted = owner_keys.map { connection.quote(_1) }
    predicate = quoted.empty? ? '' : "WHERE key NOT IN (#{quoted.join(',')})"
    connection.execute("DELETE FROM phoenix.job_owners #{predicate}")
  end
end
