require 'rails_helper'

RSpec.describe StatCreatingJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }

    subject { described_class.perform_now([user.id]) }

    before do
      allow(CreateStats).to receive(:new).and_call_original
      allow_any_instance_of(CreateStats).to receive(:call)
    end

    it 'creates a stat' do
      subject

      expect(CreateStats).to have_received(:new).with([user.id])
    end
  end
end
