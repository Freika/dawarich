# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationController, type: :controller do
  controller do
    cattr_accessor :runs, default: 0

    def index
      self.class.runs += 1
      raise ArgumentError, 'from the action'
    end

    def show
      render plain: Time.zone.name
    end
  end

  before do
    controller.class.runs = 0
    routes.draw do
      get 'index' => 'anonymous#index'
      get 'show' => 'anonymous#show'
    end
  end

  it 'runs an action that raises ArgumentError once' do
    sign_in create(:user)

    expect { get :index }.to raise_error(ArgumentError, 'from the action')
    expect(controller.class.runs).to eq(1)
  end

  it 'falls back to the default zone when the saved zone is unknown' do
    sign_in create(:user, settings: { 'timezone' => 'Not/AZone' })

    get :show

    expect(response.body).to eq(Time.zone.name)
  end
end
