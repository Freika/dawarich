# frozen_string_literal: true

require 'rails_helper'

# The web and API gates must agree on who may write.
RSpec.describe 'Account standing gates' do
  let(:user) { create(:user) }

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted) }

  def set_standing(status, active_until)
    user.update_columns(status: User.statuses[status], active_until: active_until)
  end

  def web_admitted?
    sign_in user
    get new_import_path
    response.successful?
  end

  def api_admitted?
    post api_v1_points_path, params: { locations: [] }, headers: { 'Authorization' => "Bearer #{user.api_key}" }
    !response.unauthorized?
  end

  context 'on Cloud' do
    let(:self_hosted) { false }

    [
      [:active, -> { 1.day.from_now }, true],
      [:trial, -> { 1.day.from_now }, true],
      [:active, -> { 1.day.ago }, false],
      [:active, -> {}, false],
      [:trial, -> {}, false],
      [:inactive, -> { 1.day.from_now }, false],
      [:inactive, -> {}, false]
    ].each do |status, active_until, admitted|
      description = "#{status} until #{active_until.call&.then { |time| time.future? ? 'later' : 'earlier' } || 'nil'}"

      it "#{admitted ? 'admits' : 'rejects'} #{description} on web and API alike" do
        set_standing(status, active_until.call)

        expect([web_admitted?, api_admitted?]).to eq([admitted, admitted])
      end
    end
  end

  context 'when self-hosted' do
    let(:self_hosted) { true }

    it 'admits an active account with no end date' do
      set_standing(:active, nil)

      expect([web_admitted?, api_admitted?]).to eq([true, true])
    end

    it 'rejects an account whose end date has passed' do
      set_standing(:active, 1.day.ago)

      expect([web_admitted?, api_admitted?]).to eq([false, false])
    end

    it 'rejects an inactive account' do
      set_standing(:inactive, 1000.years.from_now)

      expect([web_admitted?, api_admitted?]).to eq([false, false])
    end
  end
end
