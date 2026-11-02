# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'shared/_flash', type: :view do
  it 'keeps a bulk dismissal control in the empty container for future messages' do
    render partial: 'shared/flash'
    container = Nokogiri::HTML.fragment(rendered).at_css('#flash-messages[data-controller="flash"]')
    control = container.at_css('[data-flash-target="dismissAll"]')

    expect(control).to have_attribute('hidden')
    expect(control.at_css('button')['data-action']).to eq('flash#dismissAll')
    expect(container.css('[data-flash-target="message"]')).to be_empty
  end

  it 'includes server-rendered errors and notices in bulk dismissal without changing their timeouts' do
    flash[:error] = 'Upload failed'
    flash[:notice] = 'Upload prepared'

    render partial: 'shared/flash'
    messages = Nokogiri::HTML.fragment(rendered).css('[data-flash-target="message"]')

    expect(messages.map { |message| message['data-removals-timeout-value'] }).to eq(%w[0 5000])
    expect(messages.map { |message| message.at_css('button')['data-action'] }).to all(eq('click->removals#remove'))
  end

  I18n.available_locales.each do |locale|
    it "translates the bulk dismissal control in #{locale}" do
      I18n.with_locale(locale) do
        render partial: 'shared/flash'
        button = Nokogiri::HTML.fragment(rendered).at_css('[data-action="flash#dismissAll"]')

        expect(button.text.strip).to eq(I18n.t('shared.flash.dismiss_all', raise: true))
      end
    end
  end
end
