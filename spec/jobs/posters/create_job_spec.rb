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

  it 'raises for a missing poster without generating or changing locale' do
    expect(Posters::Generate).not_to receive(:new)

    I18n.with_locale(:en) do
      expect { described_class.perform_now(-1) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(I18n.locale).to eq(:en)
    end
  end

  it 'restores the caller locale when generation escapes with an error' do
    poster = create(:poster, user: create(:user, settings: { 'locale' => 'fr' }))
    generator = instance_double(Posters::Generate)
    allow(Posters::Generate).to receive(:new).with(poster).and_return(generator)
    allow(generator).to receive(:call).and_raise('synthetic generation failure')

    I18n.with_locale(:en) do
      expect { described_class.perform_now(poster.id) }.to raise_error('synthetic generation failure')
      expect(I18n.locale).to eq(:en)
    end
    expect(poster.reload).to be_created
  end
end
