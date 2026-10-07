# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Posters::CreateJob do
  around do |example|
    previous = ENV.fetch('DAWARICH_RAILS', nil)
    ENV['DAWARICH_RAILS'] = example.metadata[:rails_mode]
    example.run
  ensure
    previous ? ENV['DAWARICH_RAILS'] = previous : ENV.delete('DAWARICH_RAILS')
  end

  %w[on off].each do |mode|
    it "F5 #{mode} forwards accepted source work to its command owner", rails_mode: mode do
      job_owner!('command:posters.create', :oban)
      poster = create(:poster, settings: {})
      JobOutbox.delete_all
      job = described_class.new(poster.id)
      2.times { job.perform_now }
      expect(poster.reload.status).to eq('created')
      expect(JobOutbox.where(command_type: 'posters.create').sole)
        .to have_attributes(event_id: job.job_id, aggregate_id: poster.id)
    end

    it "F5 #{mode} refuses source generation while a native poster lease is live", rails_mode: mode do
      job_owner!('command:posters.create', :sidekiq)
      poster = create(:poster, settings: {})
      phoenix_leases!
      PhoenixSchema.reset!
      sql = "INSERT INTO phoenix.leases(name,holder,expires_at) VALUES(?, 'native-test', now() + interval '1 hour')"
      execute(sql, "posters:#{poster.id}")
      expect do
        described_class.perform_now(poster.id)
      end.to raise_error(StandardError, /poster generation is already running/)
      expect(poster.reload.status).to eq('created')
      expect(JobOutbox.where(command_type: 'posters.create')).to be_empty
      execute('DELETE FROM phoenix.leases WHERE name=?', "posters:#{poster.id}")
      described_class.perform_now(poster.id)
      expect(poster.reload.status).to eq('failed')
    end
  end
  def execute(sql, *values)
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([sql, *values]))
  end
end
