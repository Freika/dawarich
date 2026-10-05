# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Nightly geocoding publication', :non_transactional do
  it 'recovers every accepted point and invalidation after post-commit Sidekiq enqueue fails and the slot replays' do
    configure_instance_geocoding
    user = create(:user)
    points = create_list(:point, 2, user: user, reverse_geocoded_at: nil)
    clear_geocode_claims!
    source = Points::NightlyReverseGeocodingJob.new
    source.enqueued_at = Time.utc(2026, 10, 4, 1, 15)
    root = Geocoding::NightlyCommands.root(source.enqueued_at.to_i)
    ActiveJob::Base.queue_adapter = :sidekiq
    Sidekiq::ActiveJob::Wrapper.clear
    allow(Sidekiq::Client).to receive(:push_bulk).and_wrap_original do |original, *args|
      committed = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |db|
          db.select_value('SELECT count(*) FROM phoenix.processed_commands')
        end
      end.value
      expect(committed).to be >= points.size
      raise RedisClient::ConnectionError, 'synthetic post-commit failure' if failing

      original.call(*args)
    end
    allow(Cache::InvalidateUserCaches).to receive(:new).and_call_original

    expect { source.perform }.to raise_error(RedisClient::ConnectionError, 'synthetic post-commit failure')
    expect(points.map { Geocoding::NightlyCommands.claim(root, _1.id) }).to eq([false, false])
    intents = ActiveRecord::Base.connection.select_rows(
      'SELECT kind, payload FROM phoenix.rails_commands ORDER BY id'
    ).map { |kind, payload| [kind, JSON.parse(payload)] }
    expect(intents.select { _1.first == 'geocoding.reverse_point' }.flat_map { _1.last.fetch('point_ids') })
      .to match_array(points.map(&:id))
    expect(intents.select { _1.first == 'geocoding.reverse_point' }.map(&:last)).to all(include('force' => false))
    expect(intents.map(&:first)).to include('stats.caches_invalidated')
    source.perform
    expect(ActiveRecord::Base.connection.select_value('SELECT count(*) FROM phoenix.rails_commands'))
      .to eq(intents.size)
    self.failing = false
    expect(RailsCommands::Poller.drain_once).to eq(intents.size)
    recovered = Sidekiq::ActiveJob::Wrapper.jobs.select { _1.fetch('wrapped') == 'ReverseGeocodingJob' }
    expect(recovered.flat_map { _1.fetch('args').first.fetch('arguments')[1] }).to match_array(points.map(&:id))
    expect(Cache::InvalidateUserCaches).to have_received(:new).with(user.id, year: nil).once
    expect(ActiveRecord::Base.connection.select_value('SELECT count(*) FROM phoenix.rails_commands')).to eq(0)
  ensure
    ActiveJob::Base.queue_adapter = :test
    Sidekiq::ActiveJob::Wrapper.clear
    %w[phoenix.rails_commands phoenix.processed_commands phoenix.job_owners instance_settings].each do |table|
      ActiveRecord::Base.connection.execute("DELETE FROM #{table}")
    end
    InstanceSettings::Resolver.reset!
    clear_geocode_claims!
  end

  attr_writer :failing

  def failing = @failing != false
end
