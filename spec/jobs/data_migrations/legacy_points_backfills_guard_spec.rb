# frozen_string_literal: true

require 'rails_helper'

# The C-era backfills read legacy points columns that the v2 rewrite
# dropped. On a v2 schema each must no-op immediately: they are enqueued by
# shipped migrations on every fresh install and by Sidekiq retries on
# upgrading installs, and touching the dropped columns would crash-loop.
RSpec.describe 'legacy points backfills on the v2 schema' do
  let(:user) { create(:user) }

  before { create(:point, user: user) }

  [
    DataMigrations::BackfillCountryNameJob,
    DataMigrations::BackfillPointCountryIdJob,
    DataMigrations::BackfillPointDimensionsJob
  ].each do |job_class|
    it "#{job_class.name} returns without touching points or point_sources" do
      expect { job_class.perform_now }
        .not_to(change { [Point.count, PointSource.count, Point.first.updated_at] })
    end
  end
end
