# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::ExtractionPolicy do
  subject(:policy) { described_class.new(user, import) }

  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }

  describe '#create?' do
    it 'allows a fresh supported import' do
      expect(policy.create?).to be true
    end

    it 'blocks a run that is already in flight' do
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:running],
        additional_data_extraction: { 'started_at' => 10.minutes.ago.iso8601 }
      )

      expect(policy.create?).to be false
    end

    it 'lets the user retry once an in-flight run has gone stale' do
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:running],
        additional_data_extraction: { 'started_at' => 8.hours.ago.iso8601 }
      )

      expect(policy.create?).to be true
    end

    it 'blocks an unsupported source' do
      other = create(:import, user: user, source: :kml)

      expect(described_class.new(user, other).create?).to be false
    end

    it 'blocks another user' do
      expect(described_class.new(create(:user), import).create?).to be false
    end
  end

  describe '#destroy?' do
    it 'refuses when nothing has been extracted' do
      expect(policy.destroy?).to be false
    end

    it 'allows removing a completed extraction' do
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:completed]
      )

      expect(policy.destroy?).to be true
    end
  end
end
