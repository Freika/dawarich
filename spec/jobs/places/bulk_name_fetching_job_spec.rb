# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::BulkNameFetchingJob, type: :job do
  describe '#perform' do
    let!(:place1) { create(:place, name: Place::DEFAULT_NAME) }
    let!(:place2) { create(:place, name: Place::DEFAULT_NAME) }
    let!(:place3) { create(:place, name: 'Other place') }

    it 'enqueues name fetching job for each place with default name' do
      expect { described_class.perform_now }.to \
        have_enqueued_job(Places::NameFetchingJob).exactly(2).times
    end

    it 'does not process places with custom names' do
      expect { described_class.perform_now }.not_to \
        have_enqueued_job(Places::NameFetchingJob).with(place3.id)
    end

    it 'selects only place IDs while enqueueing' do
      queries = []
      callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        described_class.perform_now
      end

      place_queries = queries.select { |sql| sql.include?('FROM "places"') }
      expect(place_queries).not_to be_empty
      expect(place_queries).to all(include('"places"."id"'))
      expect(place_queries).to all(satisfy { |sql| !sql.include?('"places".*') })
    end

    it 'can be enqueued' do
      expect { described_class.perform_later }.to have_enqueued_job(described_class)
        .on_queue('places')
    end
  end
end
