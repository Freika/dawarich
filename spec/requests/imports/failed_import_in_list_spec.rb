# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A failed import in the imports list', type: :request do
  let(:user) { create(:user) }
  let!(:import) do
    create(:import, user:, status: :failed, error_message: "undefined method 'download' for nil")
  end

  before { sign_in user }

  def failure_link
    Nokogiri::HTML(response.body).at_css("#import_#{import.id} a[data-testid='import-failure-link']")
  end

  it 'explains the failure in words a user can act on, not the raw exception' do
    get imports_path

    expect(failure_link['aria-label']).to eq(I18n.t('ux_p2.import.failed_reason_in_list'))
    expect(response.body).not_to include('undefined method')
  end

  it 'links to the import page, where the reference and next steps are' do
    get imports_path

    expect(failure_link['href']).to eq(import_path(import))
  end

  it 'names every icon-only action so a screen reader can announce it' do
    create(:import, user:)

    get imports_path

    unnamed = Nokogiri::HTML(response.body).css('#imports-table a.btn, table a.btn').select do |link|
      link.text.strip.empty? && link['aria-label'].blank?
    end
    expect(unnamed.map { _1['href'] }).to be_empty
  end
end
