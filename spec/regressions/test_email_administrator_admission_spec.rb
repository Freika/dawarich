# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Test email administrator admission', type: :request do
  around do |example|
    original_from = UsersMailer.default_params[:from]
    UsersMailer.default from: 'fixture@example.com'
    example.run
  ensure
    UsersMailer.default from: original_from
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(DawarichSettings).to receive(:email_configured?).and_return(true)
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
  end

  it 'refuses a direct test email request from a non-administrator' do
    sign_in create(:user)

    expect { post settings_test_email_path }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
    expect(response).to redirect_to(root_path)
  end

  it 'hides the test email control from a non-administrator' do
    sign_in create(:user)
    get settings_general_index_path

    expect(response.body).not_to include(settings_test_email_path)
  end

  it 'discards queued test mail after the recipient is demoted' do
    admin = create(:user, :admin)
    UsersMailer.with(user: admin).test_email.deliver_later
    admin.update!(admin: false)

    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'checks a stale mailer recipient again before immediate delivery' do
    admin = create(:user, :admin)
    stale = User.find(admin.id)
    admin.update!(admin: false)

    UsersMailer.with(user: stale).test_email.deliver_now

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'still delivers ordinary account mail to a non-administrator' do
    user = create(:user)
    UsersMailer.with(user: user).welcome.deliver_now

    expect(ActionMailer::Base.deliveries.last.to).to eq([user.email])
  end

  it 'preserves test email access for a self-hosted administrator with inactive subscription status' do
    admin = create(:user, :admin, status: :inactive)
    sign_in admin

    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { post settings_test_email_path }

    expect(response).to redirect_to(settings_general_index_path)
    expect(ActionMailer::Base.deliveries.last.to).to eq([admin.email])
  end
end
