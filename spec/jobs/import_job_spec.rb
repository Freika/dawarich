# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImportJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform(user.id, import.id) }

    let(:user) { create(:user) }
    let(:import) { create(:import, user:, name: 'owntracks_export.json') }

    it 'creates points' do
      expect { perform }.to change { Point.count }.by(9)
    end

    it 'calls StatCreatingJob' do
      expect(StatCreatingJob).to receive(:perform_later).with(user.id)

      perform
    end
  end
end
