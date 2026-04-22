# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::DigestsMailerPreview, type: :mailer do
  it 'renders both previews without raising' do
    user = create(:user)
    user.digests.create!(year: 2026, month: 3, period_type: :monthly, distance: 100)
    user.digests.create!(year: 2025, period_type: :yearly, distance: 4287)

    expect { described_class.new.year_end_digest }.not_to raise_error
    expect { described_class.new.monthly_digest }.not_to raise_error
  end
end
