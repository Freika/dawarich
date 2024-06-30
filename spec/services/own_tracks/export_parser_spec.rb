# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OwnTracks::ExportParser do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }
    let(:import) { create(:import, user:, name: 'owntracks_export.json') }

    context 'when file exists' do
      it 'creates points' do
        expect { parser }.to change { Point.count }.by(9)
      end
    end
  end
end
