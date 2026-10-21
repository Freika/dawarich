# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsCommands::ShareManagementCommands' do
  it 'broadcasts revoked for the supplied old live UUID after native rotation' do
    user = create(:user)
    old = SharedLink.create!(user:, resource_type: :live, name: 'Old fixture')
    replacement = SharedLink.create!(user:, resource_type: :live, name: 'New fixture')
    payload = { 'user_id' => user.id, 'share_id' => old.id, 'new_share_id' => replacement.id }
    old.destroy!
    expect(SharedLink.exists?(old.id)).to be(false)

    2.times do
      expect { RailsCommands::Registry.handler('share_management.live_revoked').call(payload) }
        .to have_broadcasted_to(old).from_channel(SharedLocationChannel).with(revoked: true)
    end
    expect(replacement.reload).to be_active
    expect(SharedLink.count).to eq(1)
  end
end
