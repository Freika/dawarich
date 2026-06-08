# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::SweepJob do
  before { Flipper.enable(:points_archival) }
  after { Flipper.disable(:points_archival) }

  it 'enqueues an ArchiveUserJob per candidate' do
    user = create(:user, skip_auto_trial: true, active_until: 2.years.ago, last_sign_in_at: 1.year.ago,
                         points_count: 5)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect { described_class.new.perform }
      .to have_enqueued_job(Points::Archival::ArchiveUserJob).with(user.id)
  end

  it 'does nothing when the points_archival flag is disabled' do
    Flipper.disable(:points_archival)
    create(:user, skip_auto_trial: true, active_until: 2.years.ago, last_sign_in_at: 1.year.ago,
                  points_count: 5)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect { described_class.new.perform }
      .not_to have_enqueued_job(Points::Archival::ArchiveUserJob)
  end
end
