# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::SweepJob do
  it 'enqueues an ArchiveUserJob per candidate' do
    user = create(:user, skip_auto_trial: true, active_until: 2.years.ago, last_sign_in_at: 1.year.ago,
                         points_count: 5)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect { described_class.new.perform }
      .to have_enqueued_job(Points::Archival::ArchiveUserJob).with(user.id)
  end
end
