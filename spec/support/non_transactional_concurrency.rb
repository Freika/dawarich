# frozen_string_literal: true

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
  end
end
