# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasks::Imports::GoogleRecords do
  describe '#call' do
    let(:user) { create(:user) }
    let(:file_path) { Rails.root.join('spec/fixtures/files/google/records.json').to_s }

    it 'schedules the Import::GoogleTakeoutJob' do
      expect { described_class.new(file_path, user.email).call }
        .to have_enqueued_job(Import::GoogleTakeoutJob).exactly(1).times
    end
  end
end
