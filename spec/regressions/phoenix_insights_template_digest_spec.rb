# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix port: the insights/details template digest Phoenix keys fragments with' do
  it 'matches the digest Rails computes for the current insights views' do
    corpus = JSON.parse(Rails.root.join('app-phoenix/test/fixtures/insights/details-corpus.json').read)
    digest = ActionView::Digestor.digest(name: 'insights/details', format: :html,
                                         finder: ApplicationController.new.lookup_context)

    expect("insights/details:#{digest}").to eq(corpus['template_digest'])
  end
end
