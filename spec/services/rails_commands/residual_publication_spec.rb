# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Residual committed publication' do
  include ActiveSupport::Testing::TimeHelpers
  self.use_transactional_tests = false
  after(:context) { self.class.use_transactional_tests = true }

  let(:connection) { ActiveRecord::Base.connection }
  let(:ids) { [49_301, 49_302] }
  let(:now) { Time.utc(2026, 10, 4, 12) }

  before do
    phoenix_tables!
    @sequences = %w[phoenix.rails_commands_id_seq public.points_id_seq].index_with do |sequence|
      connection.select_one("SELECT last_value,is_called FROM #{sequence}")
    end
    @owners = connection.select_all('SELECT * FROM phoenix.job_owners WHERE key IN ' \
                                    "('cron:airtrail_flight_import_job','cron:teslamate_sync_job'," \
                                    "'cron:trek_sync_job','cron:achievements_bulk_check_job'," \
                                    "'command:imports.airtrail_flights','command:achievements.check'," \
                                    "'command:achievements.bulk_check')").to_a
    @owners.each { job_owner!(_1.fetch('key'), :sidekiq) }
    ids.each do |id|
      connection.execute('INSERT INTO users(id,email,settings,status,created_at,updated_at) VALUES ' \
                         "(#{id},'publication-#{id}@example.test','{}',1,now(),now())")
    end
    @events = []
  end

  after do
    connection.execute("DELETE FROM phoenix.rails_commands WHERE (payload->>'user_id')::bigint IN (49301,49302)")
    if @events.any?
      connection.execute('DELETE FROM phoenix.processed_commands WHERE event_id IN ' \
                         "(#{@events.map { connection.quote(_1) }.join(',')})")
    end
    TripSource.where(user_id: ids).delete_all
    Point.where(user_id: ids).delete_all
    User.unscoped.where(id: ids).delete_all
    @owners.each do |owner|
      connection.execute("UPDATE phoenix.job_owners SET owner=#{connection.quote(owner.fetch('owner'))} " \
                         "WHERE key=#{connection.quote(owner.fetch('key'))}")
    end
    @sequences.each do |sequence, state|
      connection.execute(ActiveRecord::Base.sanitize_sql_array(
                           ['SELECT setval(?, ?, ?)', sequence, state.fetch('last_value'), state.fetch('is_called')]
                         ))
    end
    PhoenixSchema.reset!
  end

  def pending
    connection.select_all('SELECT * FROM phoenix.rails_commands WHERE ' \
                          "(payload->>'user_id')::bigint IN (49301,49302) ORDER BY id").to_a
  end

  %w[airtrail teslamate trek achievements].each do |kind|
    it "#{kind} retains failed and unexecuted leaves across the real after-commit boundary" do
      travel_to now do
        if kind == 'achievements'
          ids.each do |id|
            connection.execute('INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES ' \
                               "(#{id},100,ST_GeomFromText('POINT(1 1)',4326),now(),now())")
          end
          parent = Achievements::BulkCheckJob.new
          leaf = Achievements::CheckJob
          root = Achievements::BulkCommands.root(parent.job_id, now.to_i)
          @events = ids.map { Digest::UUID.uuid_v5(root, "scheduled:#{_1}") }
        else
          settings = { "#{kind}_url" => 'https://synthetic.example.test' }
          settings['airtrail_api_key'] = 'synthetic' if kind == 'airtrail'
          User.where(id: ids).update_all(settings: settings)
          if kind == 'trek'
            allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
            ids.each do |id|
              connection.execute('INSERT INTO trip_sources' \
                                 '(id,user_id,provider,status,base_url,created_at,updated_at) ' \
                                 "VALUES(#{id},#{id},'trek',0,'https://synthetic.example.test',now(),now())")
            end
          end
          parent = { 'airtrail' => AirTrail::SyncSchedulingJob, 'teslamate' => TeslaMate::SyncSchedulingJob,
                     'trek' => Trek::SyncSchedulingJob }.fetch(kind).new
          leaf = { 'airtrail' => AirTrail::ImportFlightsJob, 'teslamate' => TeslaMate::SyncJob,
                   'trek' => Trek::SyncJob }.fetch(kind)
          @events = ids.map { Integrations::SchedulingCommands.event_id("#{kind}.scheduled", now.to_i, _1) }
        end
        parent.enqueued_at = now
        allow(leaf).to receive(:set).and_return(leaf)
        allow(leaf).to receive(:perform_later).and_raise(IOError, 'after commit enqueue failed')
        expect { parent.perform('a12d2_cron') }.to raise_error(IOError, 'after commit enqueue failed')
        retained = pending
        expect(retained.size).to eq(2)
        expect(connection.select_value('SELECT count(*) FROM phoenix.processed_commands WHERE event_id IN ' \
                                       "(#{@events.map { connection.quote(_1) }.join(',')})")).to eq(2)
        parent.perform('a12d2_cron')
        expect(pending.map { _1.fetch('id') }).to eq(retained.map { _1.fetch('id') })
        allow(leaf).to receive(:perform_later).and_return(false)
        expect { RailsCommands::Poller.deliver(retained.first.fetch('id')) }.to raise_error(/enqueue aborted/)
        expect(pending.size).to eq(2)
        allow(leaf).to receive(:set).and_call_original
        allow(leaf).to receive(:perform_later).and_call_original
        retained.each { RailsCommands::Poller.deliver(_1.fetch('id')) }
        expect(pending).to be_empty
        expect(enqueued_jobs.select { _1[:job] == leaf }.size).to eq(2)
      end
    end
  end
end
