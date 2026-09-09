# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Posters::CreateJob, type: :job do
  it 'generates the poster in the owner saved locale' do
    user = create(:user, settings: { 'locale' => 'fr' })
    poster = create(:poster, user:)
    generator = instance_double(Posters::Generate)

    allow(Posters::Generate).to receive(:new).with(poster).and_return(generator)
    allow(generator).to receive(:call) { expect(I18n.locale).to eq(:fr) }

    I18n.with_locale(:en) { described_class.perform_now(poster.id) }

    expect(generator).to have_received(:call)
  end
end
