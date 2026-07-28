# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'map/_onboarding_modal', type: :view do
  let(:user) { create(:user) }

  before do
    allow(view).to receive_messages(
      user_signed_in?: true,
      current_user: user,
      onboarding_modal_showable?: true
    )
  end

  def rendered_modal
    render partial: 'map/onboarding_modal'
    rendered
  end

  it 'leads with the tracking path before the import path' do
    html = rendered_modal

    tracking_index = html.index('Start tracking now')
    import_index = html.index('I have data')

    expect(tracking_index).not_to be_nil
    expect(import_index).not_to be_nil
    expect(tracking_index).to be < import_index
  end

  it 'reassures that importing history can happen later' do
    expect(rendered_modal).to include('import your history anytime')
  end

  it 'keeps all three paths available' do
    html = rendered_modal

    expect(html).to include('Start tracking now')
    expect(html).to include('I have data')
    expect(html).to include('demo data')
  end
end
