# frozen_string_literal: true

module PhoenixPublicFilesFixture
  PATH = 'app-phoenix/test/fixtures/public_files.json'
  SERVING_ENVIRONMENTS = %w[production staging].freeze
  SETTING_LINES = /^\s*(?:config\.(?:public_file_server|action_dispatch\.x_sendfile_header|host_authorization|hosts|
                    force_ssl|assume_ssl|ssl_options)\b|hosts\s*=)/x
  HOP_BY_HOP = %w[connection keep-alive date].freeze

  module_function

  def read
    JSON.parse(Rails.root.join(PATH).read)
  end

  def settings
    handler = ActionDispatch::FileHandler.new(Dir.tmpdir)
    {
      'environments' => SERVING_ENVIRONMENTS.index_with { |name| environment_lines(name) },
      'middleware_before_static' => middleware_before_static,
      'index_name' => Rails.application.config.public_file_server.index_name,
      'default_static_extension' => ActionController::Base.default_static_extension,
      'precompressed' => handler.instance_variable_get(:@precompressed),
      'compressible_content_types' => handler.instance_variable_get(:@compressible_content_types).source
    }
  end

  def environment_lines(name)
    Rails.root.join("config/environments/#{name}.rb").readlines.grep(SETTING_LINES).map(&:strip)
  end

  def middleware_before_static
    Rails.application.middleware.map(&:klass).take_while { |klass| klass != ActionDispatch::Static }.map(&:name)
  end

  def mime_types(extensions)
    extensions.index_with { |extension| Rack::Mime.mime_type(extension, nil) }
  end

  def build_tree(dir, tree)
    tree.fetch('files').each do |file|
      path = File.join(dir, file.fetch('path'))
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, Base64.strict_decode64(file.fetch('content')))
      File.utime(file.fetch('mtime'), file.fetch('mtime'), path)
    end
    tree.fetch('symlinks').each do |link|
      path = File.join(dir, link.fetch('path'))
      FileUtils.mkdir_p(File.dirname(path))
      File.symlink(link.fetch('target'), path)
    end
  end

  def stacks(root, application_hosts)
    { 'plain' => false, 'force_ssl' => true }.transform_values do |force_ssl|
      stack(root, application_hosts: application_hosts, force_ssl: force_ssl)
    end
  end

  def stack(root, application_hosts:, force_ssl:)
    config = Rails.application.config
    app = ActionDispatch::Static.new(->(_env) { [404, { 'x-phoenix-fixture' => 'rails-app' }, ['rails app']] },
                                     root, index: config.public_file_server.index_name, headers: {})
    app = Rack::Sendfile.new(app, nil)
    if force_ssl
      redirect_status = config.action_dispatch.ssl_default_redirect_status
      app = ActionDispatch::SSL.new(app, **config.ssl_options, ssl_default_redirect_status: redirect_status)
    end
    hosts = application_hosts.split(',').map(&:strip)
    app = ActionDispatch::HostAuthorization.new(app, hosts, exclude: ->(request) { request.path == '/api/v1/health' })
    Rails.application.middleware.find { |middleware| middleware.klass == Rack::Cors }.build(app)
  end

  def rack_answer(app, request)
    target, query = request.fetch('target').split('?', 2)
    env = Rack::MockRequest.env_for('/', method: request.fetch('method'))
    env.merge!('PATH_INFO' => target.b, 'QUERY_STRING' => query.to_s.b, 'REQUEST_URI' => request.fetch('target').b)
    request.fetch('headers').each do |name, value|
      key = name.casecmp?('content-length') ? 'CONTENT_LENGTH' : "HTTP_#{name.upcase.tr('-', '_')}"
      env[key] = env.key?(key) ? "#{env[key]}, #{value}".b : value.b
    end
    status, headers, body = app.call(env)
    content = +''.b
    body.each { |part| content << part.b }
    body.close if body.respond_to?(:close)
    response(status, puma_framing(headers, content), request.fetch('method') == 'HEAD' ? '' : content)
  end

  def puma_framing(headers, content)
    headers = headers.to_h
    return headers if headers.key?('content-length') || headers.key?('transfer-encoding')

    headers.merge('content-length' => content.bytesize.to_s)
  end

  def response(status, headers, body)
    {
      'status' => status,
      'headers' => headers.map { |name, value| [name.downcase, value] }
                          .reject { |name, _| HOP_BY_HOP.include?(name) }.sort,
      'body' => Base64.strict_encode64(body)
    }
  end
end
