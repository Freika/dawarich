# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::Destroy do
  describe '#call' do
    let!(:user) { create(:user) }
    let!(:import) { create(:import, :with_points, user: user) }
    let(:service) { described_class.new(user, import) }

    it 'destroys the import' do
      expect { service.call }.to change { Import.count }.by(-1)
    end

    it 'destroys the points' do
      expect { service.call }.to change { Point.count }.by(-import.points.count)
    end

    it 'enqueues a BulkStatsCalculatingJob' do
      expect(Stats::BulkCalculator).to receive(:new).with(user.id).and_return(double(call: nil))

      service.call
    end
  end
end
