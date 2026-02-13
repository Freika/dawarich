# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AreaVisitsCalculationSchedulingJob, type: :job do
  describe '#perform' do
    let!(:user) { create(:user) }
    let(:area) { create(:area, user: user) }

    it 'enqueues the AreaVisitsCalculatingJob' do
      expect { described_class.new.perform }.to have_enqueued_job(AreaVisitsCalculatingJob).with(user.id)
    end
  end
end
