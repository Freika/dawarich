# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'stay_point_detection feature flag' do
  let(:user) { create(:user) }

  before { Flipper.disable(:stay_point_detection) }

  it 'is disabled by default' do
    expect(Flipper.enabled?(:stay_point_detection, user)).to be false
  end

  it 'can be enabled for a single user without affecting others' do
    other_user = create(:user)

    Flipper.enable_actor(:stay_point_detection, user)

    expect(Flipper.enabled?(:stay_point_detection, user)).to be true
    expect(Flipper.enabled?(:stay_point_detection, other_user)).to be false
  end
end
