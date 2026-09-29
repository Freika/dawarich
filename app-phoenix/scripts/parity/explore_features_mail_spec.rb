# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: the explore_features mail as Rails renders it' do
  it 'records the subject and both bodies for preferred locales and for the job-locale fallback' do
    cases = { 'en' => [{ 'locale' => 'en' }, :en], 'de' => [{ 'locale' => ' DE ' }, :en], 'fallback_fr' => [{}, :fr] }

    fixtures = cases.to_h do |name, (settings, job_locale)|
      user = create(:user, email: "mail-#{name}@example.test")
      user.update_columns(settings: user.settings.except('locale').merge(settings))
      message = I18n.with_locale(job_locale) { UsersMailer.with(user: user.reload).explore_features.message }

      [name, { 'email' => user.email, 'settings' => settings, 'job_locale' => job_locale.to_s,
               'subject' => message.subject, 'text' => message.text_part.body.decoded,
               'html' => message.html_part.body.decoded }]
    end

    path = Rails.root.join('app-phoenix/test/fixtures/mail/explore_features.json')
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{JSON.pretty_generate(fixtures)}\n")
  end
end
