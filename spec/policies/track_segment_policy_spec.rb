# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrackSegmentPolicy do
  subject { described_class.new(user, segment) }

  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }
  let(:track) { create(:track, user: owner) }
  let(:segment) { create(:track_segment, track: track) }

  describe '#update?' do
    context 'when user owns the track' do
      let(:user) { owner }

      it { expect(subject.update?).to be true }
    end

    context 'when user is a different user' do
      let(:user) { other_user }

      it { expect(subject.update?).to be false }
    end

    context 'when user is anonymous' do
      let(:user) { nil }

      it { expect(subject.update?).to be false }
    end
  end
end
