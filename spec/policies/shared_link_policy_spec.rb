# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLinkContext do
  let(:user) { create(:user) }
  let(:link) { create(:shared_link, user: user) }

  it 'exposes the share link, owner, and settings' do
    ctx = described_class.new(link)
    expect(ctx.shared_link).to eq(link)
    expect(ctx.owner).to eq(user)
    expect(ctx.settings).to eq(link.settings)
  end

  it 'reports show_photos based on settings' do
    link.update!(settings: { 'show_photos' => true })
    ctx = described_class.new(link)
    expect(ctx.show_photos?).to be true
  end

  it 'defaults show_stats to false and reports true only when opted in' do
    link.update!(settings: {})
    expect(described_class.new(link).show_stats?).to be false

    link.update!(settings: { 'show_stats' => true })
    expect(described_class.new(link).show_stats?).to be true
  end

  it 'is not a User' do
    ctx = described_class.new(link)
    expect(ctx.is_a?(User)).to be false
  end
end
