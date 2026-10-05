# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cache::UserPreheatingJob do
  include ActiveSupport::Testing::TimeHelpers
  before { Rails.cache.clear }

  it 'Oban ownership retains one-day user and one-hour yearly warming before forwarding the original job once' do
    connection = ActiveRecord::Base.connection
    sequence = connection.select_one('SELECT last_value, is_called FROM digests_id_seq')
    travel_to(Time.utc(2026, 10, 3, 12)) do
      User.insert_all!([{ id: 180_111, email: 'cache-warming@example.invalid', encrypted_password: '', status: 0,
                         settings: { 'timezone' => 'Asia/Tokyo' }, plan: 1,
                         created_at: Time.current, updated_at: Time.current }])
      Stat.insert_all!([{ id: 180_511, user_id: 180_111, year: 2025, month: 1, distance: 1000,
                         daily_distance: {}, toponyms: [], created_at: Time.current, updated_at: Time.current }])
      keys = %w[years_tracked points_geocoded_stats countries_visited cities_visited total_distance]
             .map { |suffix| "dawarich/user_180111_#{suffix}" }
      writes = []
      listener = ->(*, payload) { writes << payload.slice(:key, :expires_in) }
      allow(JobCommands).to receive(:produce).and_wrap_original do |original, *args, **kwargs, &block|
        if args.first == 'cache.preheat_user'
          expect(writes.select { |write| keys.include?(write[:key]) }.map { |write| write[:key] }.uniq.sort)
            .to eq(keys.sort)
          expect(writes.find { |write| write[:key].start_with?('insights/yearly_digest/180111/2025/') }[:expires_in])
            .to eq(3600)
        end
        original.call(*args, **kwargs, &block)
      end

      %i[sidekiq oban].product(%i[warm nil stale]).each do |owner, state|
        job_owner!('command:cache.preheat_user', owner)
        digest = Users::Digest.find_by(user_id: 180_111, year: 2025)
        if digest
          value = state == :nil ? nil : digest.dup
          value.distance = 777 if state == :stale
          Rails.cache.write("insights/yearly_digest/180111/2025/#{digest.updated_at.to_i}", value, expires_in: 1.hour)
        end
        job = described_class.new(180_111)
        2.times do
          writes.clear
          ActiveSupport::Notifications.subscribed(listener, 'cache_write.active_support') { job.perform_now }
          expect(writes.select { |write| keys.include?(write[:key]) }.map { |write| write[:expires_in].to_i }.uniq)
            .to eq([86_400])
          digest = Users::Digest.find_by!(user_id: 180_111, year: 2025)
          expect(Rails.cache.read("insights/yearly_digest/180111/2025/#{digest.updated_at.to_i}").distance).to eq(1000)
        end
        payload = { 'user_id' => 180_111, 'time_zone' => Time.zone.name, 'source_job_id' => job.job_id }
        if owner == :oban
          expect(JobOutbox.where(event_id: job.job_id).count).to eq(1)
          expect(JobOutbox.find(job.job_id)).to have_attributes(payload:, command_version: 1)
        else
          expect(JobOutbox.exists?(job.job_id)).to be(false)
        end
        expect(enqueued_jobs).to be_empty
      end
    end
  ensure
    if sequence
      connection.execute("SELECT setval('digests_id_seq', #{sequence.fetch('last_value')}, " \
                         "#{connection.quote(sequence.fetch('is_called'))})")
    end
  end

  describe '#perform' do
    let!(:user) { create(:user) }
    let!(:import) { create(:import, user: user) }

    before do
      create_list(:point, 3, user: user, import: import, reverse_geocoded_at: Time.current)
    end

    it 'runs on the cache queue' do
      expect(described_class.new.queue_name).to eq('cache')
    end

    it 'preheats years_tracked' do
      described_class.new.perform(user.id)

      expect(Rails.cache.read("dawarich/user_#{user.id}_years_tracked")).to be_an(Array)
    end

    it 'preheats points_geocoded_stats' do
      described_class.new.perform(user.id)

      stats = Rails.cache.read("dawarich/user_#{user.id}_points_geocoded_stats")

      expect(stats).to include(geocoded: 3)
      expect(stats).to have_key(:without_data)
    end

    it 'preheats countries and cities visited' do
      described_class.new.perform(user.id)

      expect(Rails.cache.exist?("dawarich/user_#{user.id}_countries_visited")).to be true
      expect(Rails.cache.exist?("dawarich/user_#{user.id}_cities_visited")).to be true
    end

    it 'preheats total_distance' do
      described_class.new.perform(user.id)

      expect(Rails.cache.exist?("dawarich/user_#{user.id}_total_distance")).to be true
    end

    it 'handles a user with no points gracefully' do
      user_without_points = create(:user)

      expect { described_class.new.perform(user_without_points.id) }.not_to raise_error

      expect(Rails.cache.read("dawarich/user_#{user_without_points.id}_points_geocoded_stats"))
        .to eq({ geocoded: 0, without_data: 0 })
    end

    context 'when the user no longer exists' do
      it 'does not raise' do
        deleted_id = create(:user).id
        User.find(deleted_id).destroy

        expect { described_class.new.perform(deleted_id) }.not_to raise_error
      end
    end
  end
end
