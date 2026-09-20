# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillFamiliesForFamilyPlanJob do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    ActiveJob::Base.queue_adapter = :test
  end

  def family_plan_user
    create(:user, status: :active, active_until: 1.year.from_now).tap do |user|
      user.update_column(:plan, User.plans[:family])
    end
  end

  it 'enqueues auto-creation for a family-plan user without a family' do
    user = family_plan_user

    expect { described_class.perform_now }
      .to have_enqueued_job(Families::AutoCreationJob).with(user.id)
  end

  it 'creates the missing family' do
    family_plan_user

    perform_enqueued_jobs(only: Families::AutoCreationJob) do
      expect { described_class.perform_now }.to change(Family, :count).by(1)
    end
  end

  it 'skips a family-plan user who already owns a family' do
    user = family_plan_user
    family = create(:family, creator: user)
    create(:family_membership, :owner, user: user, family: family)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Families::AutoCreationJob)
  end

  it 'skips users on other plans' do
    create(:user, plan: :pro)
    create(:user, plan: :lite)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Families::AutoCreationJob)
  end

  it 'does nothing on self-hosted instances' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    family_plan_user

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Families::AutoCreationJob)
  end

  it 'is idempotent across repeated runs' do
    family_plan_user

    perform_enqueued_jobs(only: Families::AutoCreationJob) do
      described_class.perform_now
      expect { described_class.perform_now }.not_to change(Family, :count)
    end
  end
end
