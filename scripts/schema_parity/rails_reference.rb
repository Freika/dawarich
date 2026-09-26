# frozen_string_literal: true

require 'json'

mode = ARGV.fetch(0)
out = ARGV.fetch(1)
pool = ActiveRecord::Base.connection_pool
context = pool.migration_context
states = JSON.parse(Rails.root.join('db/release_migrations.json').read).fetch('states')
listed = states.flat_map { |state| state.fetch('schema_added') }.map(&:to_i)
present = context.migrations.map(&:version)
capture = []
baseline = []
jobs = []
ledger_create = /\ACREATE TABLE (?="(schema_migrations|ar_internal_metadata)")/

ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
  sql = payload[:sql].strip
  binds = payload[:type_casted_binds]
  binds = binds.call if binds.respond_to?(:call)
  if %w[SCHEMA TRANSACTION].include?(payload[:name]) || sql.match?(/\A(SELECT|SHOW)\b/i)
    capture << "-- [#{payload[:name]}] #{sql.squish}"
  elsif sql.match?(/schema_migrations|ar_internal_metadata|pg_(try_)?advisory/)
    capture << "-- [ledger] #{sql.squish}"
    unless sql.match?(/\A(INSERT INTO|UPDATE|DELETE FROM) "ar_internal_metadata"/)
      baseline << [sql.sub(ledger_create, 'CREATE TABLE IF NOT EXISTS '), binds]
    end
  else
    capture << (sql.end_with?(';') ? sql : "#{sql};")
    capture << "-- binds: #{binds.inspect}" if binds.present?
    baseline << [sql, binds] unless sql.match?(/\ADROP TABLE IF EXISTS "[^"]+" CASCADE\z/)
  end
end

def migration_error(error)
  error.message.start_with?('An error has occurred') && error.cause ? error.cause : error
end

def failure_class(error)
  error = migration_error(error)
  error = error.cause if error.is_a?(ActiveRecord::StatementInvalid)
  return 'none' unless error.is_a?(PG::Error)

  error.result&.error_field(PG::Result::PG_DIAG_SQLSTATE) || PG::ERROR_CLASSES.key(error.class) || 'none'
end

def job_line(job)
  wait = job.scheduled_at ? (job.scheduled_at.to_f - Time.now.to_f).round : 0
  JSON.generate([job.class.name, job.serialize.fetch('arguments'), wait])
end

ActiveSupport::Notifications.subscribe(/\Aenqueue(_at)?\.active_job\z/) do |*, payload|
  jobs << job_line(payload[:job])
end

ActiveSupport::Notifications.subscribe('enqueue_all.active_job') do |*, payload|
  payload[:jobs].each { |job| jobs << job_line(job) }
end

begin
  case mode
  when 'schema'
    ActiveRecord::Tasks::DatabaseTasks.load_schema(pool.db_config, :ruby, Rails.root.join('db/schema.rb').to_s)
  when 'all'
    context.migrate
  else
    versions =
      if mode == 'unreleased'
        present - listed
      else
        state = states.find { |candidate| candidate.fetch('first_release') == mode } || abort("no state #{mode}")
        state.fetch('schema_added').map(&:to_i) & present
      end
    versions.sort.each do |version|
      capture << "-- version #{version}"
      context.run(:up, version)
    end
  end
rescue StandardError => e
  File.write("#{out}.failure", "#{failure_class(e)}\n")
  File.write("#{out}.message", migration_error(e).message)
  raise
ensure
  body =
    if mode == 'schema'
      baseline.map { |sql, _| sql.end_with?(';') ? "#{sql}\n" : "#{sql};\n" }.join
    else
      "#{capture.join("\n")}\n"
    end
  File.write("#{out}.sql", body)
  File.write("#{out}.jobs", jobs.map { |line| "#{line}\n" }.join)
end

if mode == 'schema'
  offending = baseline.find { |sql, binds| binds.present? || sql.match?(/\A(SET|RESET)\b/i) }
  abort("cannot go into the baseline: #{offending.first}") if offending
end
