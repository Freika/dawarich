# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reverse geocoding backlog' do
  let(:user) { create(:user) }
  let!(:point) { create(:point, user: user, reverse_geocoded_at: Time.current) }

  before do
    configure_instance_geocoding
    point.update_columns(reverse_geocoded_at: nil)
    Sidekiq.redis { |r| r.del(Point.geocode_dedup_key(point.id)) }
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  it 'does not duplicate pending jobs across continue and repeated nightly runs' do
    Jobs::Create.new('continue_reverse_geocoding', user.id).call
    3.times { Points::NightlyReverseGeocodingJob.perform_now }
    Jobs::Create.new('continue_reverse_geocoding', user.id).call

    expect(ReverseGeocodingJob).to have_been_enqueued.exactly(:once)
  end

  it 'keeps claims for a backlog that takes longer than a day to drain' do
    point.async_reverse_geocode

    expect(Sidekiq.redis { |r| r.ttl(Point.geocode_dedup_key(point.id)) }).to eq(-1)
  end

  it 'preserves an existing expiring claim without adding another job' do
    Sidekiq.redis { |r| r.set(Point.geocode_dedup_key(point.id), 1, ex: 10) }
    point.async_reverse_geocode

    expect(ReverseGeocodingJob).not_to have_been_enqueued
    expect(Sidekiq.redis { |r| r.ttl(Point.geocode_dedup_key(point.id)) }).to eq(-1)
  end

  it 'keeps a claim while Sidekiq retries a failed lookup' do
    point.async_reverse_geocode
    fetcher = instance_double(ReverseGeocoding::Points::FetchData)
    allow(ReverseGeocoding::Points::FetchData).to receive(:new).and_return(fetcher)
    allow(fetcher).to receive(:call).and_raise(StandardError, 'temporary provider failure')

    expect { ReverseGeocodingJob.new.perform('Point', point.id) }.to raise_error(StandardError)
    expect { Points::NightlyReverseGeocodingJob.perform_now }.not_to have_enqueued_job(ReverseGeocodingJob)
  end

  it 'releases a claim when Sidekiq exhausts the retries' do
    point.async_reverse_geocode
    payload = { 'args' => [ReverseGeocodingJob.new('Point', point.id, force: false).serialize] }

    ReverseGeocodingJob.sidekiq_retries_exhausted_block.call(payload, StandardError.new)

    expect { Points::NightlyReverseGeocodingJob.perform_now }.to have_enqueued_job(ReverseGeocodingJob).exactly(:once)
  end

  it 'does not release a concurrent claim when a forced job exhausts retries' do
    point.async_reverse_geocode
    payload = { 'args' => [ReverseGeocodingJob.new('Point', point.id, force: true).serialize] }

    ReverseGeocodingJob.sidekiq_retries_exhausted_block.call(payload, StandardError.new)

    expect { Points::NightlyReverseGeocodingJob.perform_now }.not_to have_enqueued_job(ReverseGeocodingJob)
  end

  context 'when the provider starts refusing lookups partway through' do
    include ActiveJob::TestHelper

    let(:lookups) { [] }

    before do
      create_list(:point, 9, user: user, reverse_geocoded_at: nil)
      Sidekiq.redis { |r| r.keys('geocode:enq:*').each { |k| r.del(k) } }
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      allow(Geocoder).to receive(:search) do |query|
        lookups << query
        raise Geocoder::OverQueryLimitError if lookups.size > 3

        [double(city: 'Berlin', country: 'Germany', data: { 'properties' => {} })]
      end
    end

    def run_nightly_backlog
      Points::NightlyReverseGeocodingJob.perform_now
      perform_enqueued_jobs(only: ReverseGeocodingJob)
    end

    it 'sends one refused lookup instead of one for every point left' do
      run_nightly_backlog

      expect(lookups.size).to eq(4)
      expect(Point.not_reverse_geocoded.count).to eq(7)
    end

    it 'picks the rest up once the provider answers again' do
      run_nightly_backlog
      allow(Geocoder).to receive(:search).and_return(
        [double(city: 'Berlin', country: 'Germany', data: { 'properties' => {} })]
      )
      Geocoding::Cooldown.reset!

      Points::ResumeReverseGeocodingJob.perform_now
      perform_enqueued_jobs(only: ReverseGeocodingJob)

      expect(Point.not_reverse_geocoded.count).to eq(0)
    end
  end
end
