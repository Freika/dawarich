# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: the notification pages as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:fixtures) { Rails.root.join('app-phoenix/test/fixtures') }
  let(:now) { Time.utc(2026, 9, 26, 12, 0, 0) }

  def write_json(name, data) = FixtureRecording.verify(fixtures.join(name), "#{JSON.pretty_generate(data)}\n")

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  def reader(id, email, locale = nil)
    user = create(:user, id:, email:, changelog_consent: :declined)
    user.update_columns(settings: user.settings.merge({ 'onboarding_completed' => true, 'locale' => locale }.compact))
    user
  end

  def seed(user, count, first_id)
    1.upto(count).each do |number|
      error = number == count
      user.notifications.create!(id: first_id + number, title: format('Parity %02d', number),
                                 kind: error ? :error : %i[info warning][number % 2],
                                 content: error ? 'Error <b>detail</b> <script>x()</script>' : "Detail #{number}",
                                 read_at: number <= 3 ? now : nil, created_at: now - number.minutes)
    end
  end

  def page(name, user, path)
    get path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML5(response.body)
    doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
    FixtureRecording.verify(fixtures.join("notifications/#{name}.html"),
                            doc.at_css('body > div.container > div.w-full > div.flex').inner_html)
    notifications = user.notifications.order(:id).map do |n|
      { id: n.id, title: n.title, content: n.content, kind: Notification.kinds[n.kind], read: n.read_at.present?,
        offset: (now - n.created_at).round }
    end
    write_json("notifications/#{name}.json",
               { path:, title: doc.at_css('title').text,
                 user: { id: user.id, email: user.email, settings: user.reload.settings }, notifications: })
  end

  it 'writes the notification pages' do
    FileUtils.mkdir_p(fixtures.join('notifications'))
    travel_to now do
      en = reader(9101, 'parity-en@dawarich.test')
      seed(en, 22, 910_000)
      sign_in en
      page('index_first_en', en, '/notifications')
      page('index_second_en', en, '/notifications?page=2')
      page('show_error_en', en, "/notifications/#{en.notifications.find_by(kind: :error).id}")
      page('show_info_en', en, "/notifications/#{en.notifications.order(:id).first.id}")
      sign_out en

      de = reader(9102, 'parity-de@dawarich.test', 'de')
      seed(de, 3, 920_000)
      sign_in de
      %w[de es fr pl ca zh].each do |locale|
        de.update_columns(settings: de.settings.merge('locale' => locale))
        page("index_#{locale}", de, '/notifications')
        page("show_#{locale}", de, "/notifications/#{de.notifications.order(:id).last.id}")
      end
      sign_out de

      many = reader(9103, 'parity-many@dawarich.test')
      Notification.insert_all(Array.new(250) do |i|
        { id: 930_001 + i, user_id: many.id, title: "Many #{i}", content: 'x', kind: 0, read_at: now,
          created_at: now - (i + 1).minutes, updated_at: now }
      end)
      sign_in many
      page('index_page7_en', many, '/notifications?page=7')
      page('index_page20_en', many, '/notifications?page=20&locale=en')
      sign_out many

      empty = reader(9104, 'parity-empty@dawarich.test')
      sign_in empty
      page('index_empty_en', empty, '/notifications')
    end
  end

  it 'writes the sanitize corpus' do
    inputs = [
      'plain text & more', 'B9 safe detail <script>window.b9Xss=true</script>',
      "joined the family '<script>window.xss=true</script><img src=x onerror=alert(1)>'",
      '<a href="https://dawarich.app/x?a=1&b=2" target="_blank" onclick="x()">link</a>',
      '<a href="javascript:alert(1)">js</a>', '<a href="JaVaScRiPt:alert(1)">js</a>',
      '<a href="java&#x09;script:alert(1)">js</a>', '<a href="java&#58script:alert(1)">js</a>',
      '<a href="javascript&colon;alert(1)">js</a>', '<a href="&amp;#106avascript:alert(1)">js</a>',
      '<a href="/relative path">rel</a>',
      '<a href="mailto:hi@dawarich.app" name="n m">mail</a>', '<a href="a"b">quote</a>',
      '<img src="data:image/png;base64,AAAA" alt="ok">', '<img src="data:text/html;base64,AAAA">',
      '<img src="data&#58;text/html,x">', '<img src="  " alt="blank">', '<img src="x" width="10" height="5" title="t">',
      '<p style="color:red" class="c">styled</p>', '<div><span lang="de" xml:lang="de">Hallo</span></div>',
      '<ul><li>one<li>two</ul>', '<b>bold <i>both</b> italic</i>', '<table><tr><td>cell</td></tr></table>',
      '<iframe src="https://evil.example"></iframe>after', '<style>p{color:red}</style>kept',
      '<svg><a href="x">in svg</a></svg>tail', '<math><mi>x</mi></math>tail', '<!-- comment -->visible',
      '<template><b>t</b></template>after', '<noscript><b>n</b></noscript>after', 'Line<br>break<br/>again',
      '<h1>H</h1><h6>H6</h6><hr>', '<code>x &lt; y</code>', '<pre>  pre  </pre>',
      '<time datetime="2026-09-28">today</time>',
      '<blockquote cite="javascript:x">q</blockquote>', '<form action="/x"><input value="v"></form>text',
      'a < b and c > d', 'unclosed <b>bold', '<del>d</del><ins>i</ins><mark>m</mark><sub>s</sub><sup>s</sup>',
      '<a href="https://x.example/?q=a b">space</a>', '<abbr title="t" abbr="a">A</abbr><cite>c</cite><dfn>d</dfn>'
    ]
    corpus = inputs.map { |input| { input:, output: ApplicationController.helpers.sanitize(input).to_s } }
    write_json('sanitize.json', corpus)
  end

  it 'writes the distance-in-words corpus' do
    offsets = [0, 29, 30, 59, 89, 90, 119, 2669, 2670, 5369, 5370, 86_369, 86_370, 151_169, 151_170, 2_591_969,
               2_591_970, 5_183_969, 5_183_970, 31_535_969, 31_536_000, 47_304_000, 63_072_000, 94_608_000,
               126_230_400, 315_360_000]
    corpus = travel_to(now) do
      %w[en de es fr pl ca zh].flat_map do |locale|
        offsets.map do |seconds|
          words = I18n.with_locale(locale) { ApplicationController.helpers.relative_distance_in_words(now - seconds) }
          { locale:, seconds:, words: }
        end
      end
    end
    write_json('time_ago.json', corpus)
  end

  it 'writes the zoned distance-in-words corpus across a leap-year February' do
    spans = [%w[2028-02-29T23:30:00Z 2029-03-01T00:30:00Z], %w[2028-03-01T02:00:00Z 2029-03-01T04:00:00Z]]
    system_zone = ENV.fetch('TZ', nil)
    ENV['TZ'] = 'UTC'
    zones = %w[UTC Europe/Berlin America/New_York Pacific/Kiritimati]
    corpus = spans.product(zones, %w[en de es fr pl ca zh]).map do |(from, to), zone, locale|
      words = travel_to(Time.iso8601(to)) do
        Time.use_zone(zone) do
          created_at = Time.iso8601(from).in_time_zone
          I18n.with_locale(locale) { ApplicationController.helpers.relative_distance_in_words(created_at) }
        end
      end
      { zone:, locale:, from:, to:, words: }
    end
    write_json('time_ago_zones.json', corpus)
  ensure
    ENV['TZ'] = system_zone
  end
  it 'characterizes legacy owner actions and invalid read validation' do
    actor = create(:user)
    other = create(:user)
    own = create(:notification, user: actor)
    foreign = create(:notification, user: other)
    sign_in actor
    get '/notifications'
    token = Nokogiri::HTML5(response.body).at_css('meta[name=csrf-token]')['content']
    post '/notifications/mark_as_read', params: { authenticity_token: token }
    expect(response.status).to eq(303)
    expect(response.location).to end_with('/notifications')
    expect(own.reload.read_at).to be_present
    expect(foreign.reload.read_at).to be_nil
    delete "/notifications/#{foreign.id}", params: { authenticity_token: token }
    expect(response.status).to eq(404)
    own.update_columns(title: '', content: '', read_at: nil)
    get "/notifications/#{own.id}"
    expect(response.status).to eq(422)
    expect(own.reload.read_at).to be_nil
    post '/notifications/destroy_all', params: { authenticity_token: token }
    expect(response.status).to eq(303)
    expect(actor.notifications.count).to eq(0)
    expect(other.notifications.count).to eq(1)
  end
end
