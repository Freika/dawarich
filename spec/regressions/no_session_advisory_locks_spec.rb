# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Session-level advisory locks behind PgBouncer transaction pooling' do
  let(:sources) { Dir[Rails.root.join('{app,lib,app-phoenix/lib}/**/*.{rb,rake,ex}')].sort }
  let(:allowed_session_gem_locks) do
    %w[
      app/jobs/points/anomaly_backfill_user_job.rb app/jobs/points/raw_data/archive_user_job.rb
      app/jobs/points/raw_data/clear_user_job.rb app/jobs/tesla_mate/sync_job.rb app/jobs/trek/import_trips_job.rb
      app/jobs/trek/sync_job.rb app/services/phoenix_lease.rb app/services/points/raw_data/archiver.rb
      app/services/visits/select_place.rb lib/tasks/points_raw_data.rake
    ]
  end

  def relative(path) = Pathname(path).relative_path_from(Rails.root).to_s

  it 'leaves no session advisory lock function call in Rails or Phoenix code' do
    offenders = sources.select { |path| File.read(path).match?(/pg_(try_)?advisory_(lock|unlock)(_shared|_all)?\(/i) }
    expect(offenders.map { relative(_1) }).to be_empty
  end

  it 'takes gem advisory locks only transaction-scoped, outside the listed files' do
    offenders = sources.select do |path|
      File.readlines(path).any? { |line| line.match?(/with_advisory_lock!?\(/) && !line.include?('transaction: true') }
    end
    expect(offenders.map { relative(_1) }).to eq(allowed_session_gem_locks)
  end
end
