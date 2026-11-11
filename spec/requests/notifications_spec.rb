# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/notifications', type: :request do
  context 'when user is not logged in' do
    it 'does not open a notification' do
      notification = create(:notification, action_path: '/exports')

      get open_notification_url(notification)

      expect(response).to redirect_to(new_user_session_path)
      expect(notification.reload).not_to be_read
    end

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

      it 'says how long read notifications are kept' do
        get notifications_url

        expect(response.body).to include('Read notifications are deleted after 30 days.')
      end
    end

    describe 'GET /show' do
      let(:notification) { create(:notification, user:) }

      it 'renders a successful response' do
        get notification_url(notification)

        expect(response).to be_successful
      end

      context 'with an error notification' do
        let(:notification) { create(:notification, user:, kind: :error) }
        let(:bug_report_link) { 'https://github.com/Freika/dawarich/issues' }

        it 'asks a self-hosted user to report the bug with container logs' do
          get notification_url(notification)

          expect(response.body).to include(bug_report_link)
        end

        it 'does not ask a Cloud user for container logs they cannot reach' do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

          get notification_url(notification)

          expect(response.body).not_to include(bug_report_link)
        end

        it 'tells a Cloud user where to write instead' do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

          get notification_url(notification)

          card = Nokogiri::HTML(response.body).at_css('[id^="detail_notification"]')
          expect(card.at_css('a[href="mailto:hi@dawarich.app"]')).to be_present
        end

        it 'does not send a self-hosted user to Cloud support' do
          get notification_url(notification)

          card = Nokogiri::HTML(response.body).at_css('[id^="detail_notification"]')
          expect(card.css('a[href^="mailto:"]')).to be_empty
        end
      end

      context 'with a stored XSS payload in content' do
        let(:xss_payload) do
          %(<script>window.xss=true</script><img src=x onerror=alert(1)>)
        end
        let(:notification) do
          create(:notification, user:, content: "joined the family '#{xss_payload}'")
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

    describe 'GET /open' do
      let(:notification) { create(:notification, user:, action_path: '/exports') }

      it 'marks the notification read and goes where it leads' do
        get open_notification_url(notification)

        expect(response).to redirect_to('/exports')
        expect(notification.reload).to be_read
      end

      it 'opens the notification page for an error, where the message and what to do are' do
        failed = create(:notification, user:, kind: :error, action_path: '/exports')

        get open_notification_url(failed)

        expect(response).to redirect_to(notification_url(failed))
        expect(failed.reload).to be_read
      end

      it 'falls back to the notification page when there is nowhere to go' do
        plain = create(:notification, user:)

        get open_notification_url(plain)

        expect(response).to redirect_to(notification_url(plain))
        expect(plain.reload).to be_read
      end

      it 'never leaves the site, even for a path stored without validation' do
        ['//evil.example', "/\t/evil.example"].each do |path|
          notification.update_column(:action_path, path)

          get open_notification_url(notification)

          expect(response).to redirect_to(notification_url(notification))
        end
      end

      it "does not open another user's notification" do
        foreign = create(:notification, action_path: '/exports')

        get open_notification_url(foreign)

        expect(response).to have_http_status(:not_found)
        expect(foreign.reload).not_to be_read
      end
    end

    describe 'the destination button on the notification page' do
      def open_buttons
        Nokogiri::HTML(response.body).css('a.btn-primary').select { |link| link.text.strip == 'Open' }
      end

      it 'links to where the notification leads' do
        notification = create(:notification, user:, action_path: '/exports')

        get notification_url(notification)

        expect(open_buttons.map { |link| link['href'] }).to eq(['/exports'])
      end

      it 'is absent when there is nowhere to go' do
        get notification_url(create(:notification, user:))

        expect(open_buttons).to be_empty
      end

      it 'is absent for a path stored without validation' do
        notification = create(:notification, user:)
        notification.update_column(:action_path, '//evil.example')

        get notification_url(notification)

        expect(response.body).not_to include('evil.example')
      end
    end

    describe 'link prefetch' do
      it 'is switched off for the bell list and the notification list' do
        create(:notification, user:)

        get notifications_url

        page = Nokogiri::HTML(response.body)
        expect(page.at_css('#notifications-list')['data-turbo-prefetch']).to eq('false')
        expect(page.at_css('#notifications')['data-turbo-prefetch']).to eq('false')
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

      it 'still redirects when inline is switched off explicitly' do
        post mark_notifications_as_read_url(inline: 'false')

        expect(response).to redirect_to(notifications_url)
      end

      context 'from the bell (inline)' do
        it 'marks everything read and answers with a stream instead of leaving the page' do
          post mark_notifications_as_read_url(inline: true)

          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq('text/vnd.turbo-stream.html')
          expect(notification.reload).to be_read
        end

        it 'clears the bell items and shows the real unread count' do
          post mark_notifications_as_read_url(inline: true)

          streams = Nokogiri::HTML.fragment(response.body).css('turbo-stream')
          expect(streams.map { |stream| [stream['action'], stream['target'] || stream['targets']] })
            .to contain_exactly(%w[replace notifications-badge], %w[remove .notification-item])
          expect(streams.first.to_s).to match(/hidden[^>]*>\s*0\s*</)
        end

        it 'refreshes notification pages in the asking tab too, which Turbo would otherwise skip' do
          stream = Turbo::StreamsChannel.send(:stream_name_from, [user, :notification_pages])

          post mark_notifications_as_read_url(inline: true), headers: { 'X-Turbo-Request-Id' => 'tab-1' }

          refreshes = ActionCable.server.pubsub.broadcasts(stream)
                                 .map { |message| ActiveSupport::JSON.decode(message) }
                                 .grep(/action="refresh"/)
          expect(refreshes).to be_present
          expect(refreshes).to all(satisfy { |html| html.exclude?('tab-1') })
        end

        it "leaves another user's notifications unread" do
          foreign = create(:notification)

          post mark_notifications_as_read_url(inline: true)

          expect(foreign.reload).not_to be_read
        end
      end
    end

    describe 'the bell' do
      let!(:notification) do
        create(:notification, user:, title: 'Import failed', action_path: '/imports',
                              content: 'Import Tom &amp; Jerry.gpx failed. <a href="/imports/1">Open</a>')
      end
      let(:page) { Nokogiri::HTML(response.body) }

      before { get notifications_url }

      it 'shows what happened, when, and opens the destination' do
        item = page.at_css('#notifications-list .notification-item')

        expect(item.at_css('a')['href']).to eq(open_notification_path(notification))
        expect(item.text).to include('Import failed', 'Tom & Jerry.gpx failed', 'ago')
        expect(item.to_s).not_to include('&amp;amp;')
      end

      it 'shows escaped markup from the text as text' do
        create(:notification, user:, title: 'Joined', content: 'joined &lt;b&gt;bold&lt;/b&gt; family')

        get notifications_url

        item = page.css('#notifications-list .notification-item').find { |li| li.text.include?('Joined') }
        expect(item.css('b')).to be_empty
        expect(item.text).to include('<b>bold</b>')
      end

      it 'keeps only notifications inside the live list, so new ones land below the header' do
        children = page.at_css('#notifications-list').element_children

        expect(children.map { |child| child['class'] }).to all(include('notification-item'))
      end

      it 'offers mark all as read without leaving the page' do
        link = page.css('[data-controller="notifications"] a').find { |a| a.text.strip == 'Mark all as read' }

        expect(link['href']).to eq(mark_notifications_as_read_path(inline: true))
        expect(link['data-turbo-method']).to eq('post')
      end
    end
  end
end
