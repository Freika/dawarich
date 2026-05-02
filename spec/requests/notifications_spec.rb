# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/notifications', type: :request do
  context 'when user is not logged in' do
    it 'redirects to the login page' do
      get notifications_url

      expect(response).to redirect_to(new_user_session_url)
    end
  end

  context 'when user is logged in' do
    let(:user) { create(:user) }

    before do
      sign_in user
    end

    describe 'GET /index' do
      it 'renders a successful response' do
        get notifications_url

        expect(response).to be_successful
      end
    end

    describe 'GET /show' do
      let(:notification) { create(:notification, user:) }

      it 'renders a successful response' do
        get notification_url(notification)

        expect(response).to be_successful
      end

      context 'with a stored XSS payload in content' do
        let(:notification) do
          create(:notification, user:,
                                content: %(joined the family '<script>window.xss=true</script><img src=x onerror=alert(1)>'))
        end

        it 'does not render <script> or event-handler attributes' do
          get notification_url(notification)

          expect(response.body).not_to include('<script>window.xss=true</script>')
          expect(response.body).not_to match(/onerror\s*=/i)
        end

        it 'preserves the safe text content' do
          get notification_url(notification)

          expect(response.body).to include('joined the family')
        end
      end
    end

    describe 'DELETE /destroy' do
      let!(:notification) { create(:notification, user:) }

      it 'destroys the requested notification' do
        expect do
          delete notification_url(notification)
        end.to change(Notification, :count).by(-1)
      end

      it 'redirects to the notifications list' do
        delete notification_url(notification)

        expect(response).to redirect_to(notifications_url)
      end
    end

    describe 'POST /mark_as_read' do
      let!(:notification) { create(:notification, user:, read_at: nil) }

      it 'marks all notifications as read' do
        post mark_notifications_as_read_url

        expect(notification.reload.read_at).to be_present
      end

      it 'redirects to the notifications list' do
        post mark_notifications_as_read_url

        expect(response).to redirect_to(notifications_url)
      end
    end
  end
end
