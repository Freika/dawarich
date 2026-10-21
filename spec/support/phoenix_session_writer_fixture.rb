# frozen_string_literal: true

module PhoenixSessionWriterFixture
  PATH = 'app-phoenix/test/fixtures/rails_session_writer.json'
  SSL_CONFIG = /^\s*config\.(?:force_ssl|assume_ssl|ssl_options)\b/
  SAMPLE_CHARACTERS = [*(0..0x7F).map(&:chr), "\u00a0", "\u00e9", "\u2028", "\u2029", "\ufeff", "\u{1F600}"].freeze
  OVERFLOW = { 'unit' => "&<>\u2028\u2029", 'units' => 60, 'extra' => '&', 'counts' => (30..90) }.freeze

  module_function

  def read
    JSON.parse(Rails.root.join(PATH).read)
  end

  def settings
    config = Rails.application.config
    {
      'ssl_default_redirect_status' => config.action_dispatch.ssl_default_redirect_status,
      'ssl_options' => config.ssl_options.as_json,
      'assume_ssl' => config.assume_ssl,
      'session_store' => config.session_store.name,
      'session_options' => config.session_options.as_json,
      'cookies_same_site_protection' => config.action_dispatch.cookies_same_site_protection.to_s,
      'cookies_serializer' => config.action_dispatch.cookies_serializer.to_s,
      'environments' => environment_ssl_lines
    }
  end

  def environment_ssl_lines
    Rails.root.glob('config/environments/*.rb').sort.to_h do |path|
      [path.basename('.rb').to_s, path.readlines.grep(SSL_CONFIG).map(&:strip)]
    end
  end

  def cookie_jar
    ActionDispatch::Request.new(Rails.application.env_config.dup).cookie_jar
  end

  def cookie_json
    serializer = cookie_jar.encrypted.send(:serializer)
    SAMPLE_CHARACTERS.map { |character| [character, serializer.dump([character])] }
  end

  def overflow
    OVERFLOW.except('counts').merge('fits' => OVERFLOW['counts'].to_h { |count| [count.to_s, fits?(count)] })
  end

  def fits?(count)
    notice = (OVERFLOW['unit'] * OVERFLOW['units']) + (OVERFLOW['extra'] * count)
    session = { 'flash' => { 'discard' => [], 'flashes' => { 'notice' => notice } } }
    cookie_jar.encrypted['_dawarich_session'] = { value: session }
    true
  rescue ActionDispatch::Cookies::CookieOverflow
    false
  end

  def force_ssl(app = ->(_env) { [200, {}, []] })
    config = Rails.application.config
    ActionDispatch::SSL.new(app, **config.ssl_options,
                                 ssl_default_redirect_status: config.action_dispatch.ssl_default_redirect_status)
  end

  def answer(ssl, request)
    env = request.fetch('headers').to_h { |name, value| ["HTTP_#{name.upcase.tr('-', '_')}", value] }
    status, headers, = ssl.call(Rack::MockRequest.env_for(request.fetch('url'), env.merge(method: request['method'])))
    request.merge('status' => status, 'location' => headers['location'],
                  'hsts' => headers['strict-transport-security'], 'content_type' => headers['content-type'])
  end

  def cookie_attributes(line)
    line.split(';').drop(1).map { |attribute| attribute.strip.downcase }.sort
  end
end
