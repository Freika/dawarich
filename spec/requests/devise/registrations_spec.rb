require 'rails_helper'

RSpec.describe 'users', type: :request do
  describe 'POST /create' do
    context 'when registers as master' do
      let(:services) { FactoryBot.create_list(:service, 3) }
      let(:master_params) do
        { user: FactoryBot.attributes_for(:master).merge(services_ids: services.pluck(:id)) }
      end

      it 'creates master' do
        expect do
          post '/users', params: master_params
        end.to change(User, :count).by(1)
        expect(User.masters.count).to eq(1)

        master = User.masters.first

        expect(master.whatsapp).to eq(master_params[:user][:whatsapp])
        expect(master.viber).to eq(master_params[:user][:viber])
        expect(master.telegram).to eq(master_params[:user][:telegram])
        expect(master.facebook).to eq(master_params[:user][:facebook])
        expect(master.portfolio_url).to eq(master_params[:user][:portfolio_url])
      end

      it 'creates master services' do
        expect do
          post '/users', params: master_params
        end.to change(UserService, :count).by(3)

        expect(User.masters.last.services).to eq(services)
      end
    end

    context 'when registers as client'
  end
end
