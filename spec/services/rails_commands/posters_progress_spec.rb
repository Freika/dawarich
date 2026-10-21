# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsCommands posters.progress' do
  include ActionCable::TestHelper

  it 'poster progress re reads current row and broadcasts its exact card' do
    phoenix_tables!
    user = create(:user)
    poster = create(:poster, user: user, status: :processing, name: 'Synthetic current card')
    payload = { 'poster_id' => poster.id, 'user_id' => user.id, 'locale' => 'de' }
    stream = Turbo::StreamsChannel.send(:stream_name_from, [user, :posters])
    handler = RailsCommands::Registry.handler('posters.progress')
    expect(handler).to be_present
    first = capture_broadcasts(stream) { handler.call(payload) }.sole
    poster.update_columns(status: :failed, settings: { error: 'Synthetic current error' })
    expected = I18n.with_locale(:de) do
      ApplicationController.render(partial: 'posters/poster', locals: { poster: poster.reload })
    end
    quoted = ActiveRecord::Base.connection.quote(payload.to_json)
    ActiveRecord::Base.connection.execute(
      "INSERT INTO phoenix.rails_commands(kind,payload) VALUES('posters.progress',#{quoted}::jsonb)"
    )
    latest = capture_broadcasts(stream) { expect(RailsCommands::Poller.drain_once).to eq(1) }.sole
    tag = Turbo::StreamsChannel.turbo_stream_action_tag(:replace, target: "poster_#{poster.id}", template: expected)
    expect(latest).to eq(tag.to_s)
    expect(first).not_to eq(latest)
    expect(latest).to include('Synthetic current error')
    expect(capture_broadcasts(stream) { handler.call(payload.merge('user_id' => create(:user).id)) }).to be_empty
    poster.delete
    expect(capture_broadcasts(stream) { handler.call(payload) }).to be_empty
  end
end
