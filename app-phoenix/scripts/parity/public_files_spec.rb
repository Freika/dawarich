# frozen_string_literal: true

require 'rails_helper'
require 'puma'
require 'puma/server'
require 'socket'

RSpec.describe 'Phoenix fixture: the public/ files Rails serves through Puma' do
  let(:mtime) { Time.utc(2026, 9, 1, 12, 0, 0).to_i }
  let(:application_hosts) { 'dawarich.example, .example.org' }
  let(:host) { 'dawarich.example' }
  let(:png) { "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b }

  def text_files
    {
      'robots.txt' => "User-agent: *\n", 'app.css' => "body { color: red; }\n", 'app.css.gz' => 'gzipped css',
      'app.css.br' => 'brotli css', 'app.js' => "console.log('app')\n", 'app.js.gz' => 'gzipped js',
      'only-gz.css.gz' => 'gzipped only', 'logo.svg' => '<svg xmlns="http://www.w3.org/2000/svg"/>',
      'logo.svg.br' => 'brotli svg', 'data.json' => '{"a":1}', 'data.json.gz' => 'gzipped json',
      'app.js.map' => '{"version":3}', 'site.webmanifest' => '{"name":"Dawarich"}', 'module.mjs' => 'export {}',
      'page.html' => '<p>page</p>', 'docs/index.html' => '<p>docs</p>', 'docs/index.html.gz' => 'gzipped docs',
      'noext' => 'no extension', 'UPPER.CSS' => 'p {}', 'space name.txt' => 'spaced', 'empty.txt' => '',
      'sub/deep/file.txt' => 'deep', '.hidden.txt' => 'hidden', '.well-known/apple-app-site-association' => '{}',
      'weird.xyz' => 'unknown extension', 'doc.pdf' => '%PDF-1.4', 'sub%5Cdeep.txt' => 'percent in name'
    }
  end

  def binary_files
    %w[icon.png icon.png.gz tiles.pmtiles font.woff2 font.woff font.ttf image.webp photo.jpg photo.jpeg anim.gif
       favicon.ico blob.bin].index_with { |name| png + name.b }
  end

  def tree
    files = text_files.merge(binary_files, '../outside.txt' => 'outside public/').map do |path, content|
      { 'path' => path, 'content' => Base64.strict_encode64(content.b),
        'mtime' => path == 'app.css.gz' ? mtime + 3600 : mtime }
    end
    symlinks = [{ 'path' => 'link.txt', 'target' => 'robots.txt' },
                { 'path' => 'escape.txt', 'target' => '../outside.txt' },
                { 'path' => 'linkdir', 'target' => 'sub' }]
    { 'files' => files.sort_by { |file| file['path'] }, 'symlinks' => symlinks }
  end

  def request(name, target, headers = {}, method: 'GET', stack: 'plain', host: self.host, version: '1.1')
    headers = [*([['Host', host]] if host), *headers.to_a]
    headers << %w[Content-Length 0] if method == 'POST'
    { 'name' => name, 'stack' => stack, 'method' => method, 'target' => target, 'version' => version,
      'headers' => headers }
  end

  def served_requests
    stamp = Time.at(mtime).httpdate
    [
      request('robots', '/robots.txt'), request('robots-head', '/robots.txt', method: 'HEAD'),
      request('robots-query', '/robots.txt?vsn=1'), request('robots-trailing-slash', '/robots.txt/'),
      request('robots-escaped', '/%72obots.txt'), request('css', '/app.css'),
      request('css-gzip', '/app.css', { 'Accept-Encoding' => 'gzip' }),
      request('css-br', '/app.css', { 'Accept-Encoding' => 'br' }),
      request('css-browser', '/app.css', { 'Accept-Encoding' => 'gzip, deflate, br, zstd' }),
      request('css-br-q0', '/app.css', { 'Accept-Encoding' => 'br;q=0' }),
      request('css-star', '/app.css', { 'Accept-Encoding' => '*' }),
      request('css-brotli-word', '/app.css', { 'Accept-Encoding' => 'brotli' }),
      request('css-x-gzip', '/app.css', { 'Accept-Encoding' => 'x-gzip' }),
      request('css-upper', '/app.css', { 'Accept-Encoding' => 'GZIP' }),
      request('css-parameter', '/app.css', { 'Accept-Encoding' => 'identity;q=gzip' }),
      request('css-head-gzip', '/app.css', { 'Accept-Encoding' => 'gzip' }, method: 'HEAD'),
      request('css-two-accepts', '/app.css', [%w[Accept-Encoding deflate], %w[Accept-Encoding gzip]]),
      request('js-br', '/app.js', { 'Accept-Encoding' => 'br' }),
      request('js-gzip', '/app.js', { 'Accept-Encoding' => 'gzip' }),
      request('only-gz', '/only-gz.css', { 'Accept-Encoding' => 'gzip' }),
      request('svg-br', '/logo.svg', { 'Accept-Encoding' => 'br' }), request('svg', '/logo.svg'),
      request('png-gzip', '/icon.png', { 'Accept-Encoding' => 'gzip' }),
      request('json-gzip', '/data.json', { 'Accept-Encoding' => 'gzip' }),
      request('map', '/app.js.map'), request('webmanifest', '/site.webmanifest'),
      request('pmtiles', '/tiles.pmtiles'), request('mjs', '/module.mjs'),
      request('page', '/page'), request('page-html', '/page.html'), request('docs', '/docs'),
      request('docs-slash', '/docs/'), request('docs-gzip', '/docs', { 'Accept-Encoding' => 'gzip' }),
      request('docs-index', '/docs/index.html'), request('noext', '/noext'), request('upper', '/UPPER.CSS'),
      request('space', '/space%20name.txt'), request('percent-name', '/sub%255Cdeep.txt'),
      *%w[font.woff2 font.woff font.ttf image.webp photo.jpg photo.jpeg anim.gif favicon.ico blob.bin].map do |name|
        request(name, "/#{name}")
      end,
      request('empty', '/empty.txt'), request('empty-head', '/empty.txt', method: 'HEAD'),
      request('deep', '/sub/deep/file.txt'), request('encoded-slash', '/sub%2Fdeep%2Ffile.txt'),
      request('ims-exact', '/robots.txt', { 'If-Modified-Since' => stamp }),
      request('ims-exact-head', '/robots.txt', { 'If-Modified-Since' => stamp }, method: 'HEAD'),
      request('ims-other', '/robots.txt', { 'If-Modified-Since' => Time.at(mtime - 1).httpdate }),
      request('ims-twice', '/robots.txt', [['If-Modified-Since', stamp], ['If-Modified-Since', stamp]]),
      request('ims-variant-stale', '/app.css', { 'Accept-Encoding' => 'gzip', 'If-Modified-Since' => stamp }),
      request('ims-variant', '/app.css', { 'Accept-Encoding' => 'gzip',
                                           'If-Modified-Since' => Time.at(mtime + 3600).httpdate }),
      request('host-port', '/robots.txt', host: 'dawarich.example:3000'),
      request('host-subdomain', '/robots.txt', host: 'maps.example.org'),
      request('host-apex', '/robots.txt', host: 'example.org:8080'),
      request('host-upper', '/robots.txt', host: 'DAWARICH.EXAMPLE'),
      request('forwarded-host', '/robots.txt', { 'X-Forwarded-Host' => 'dawarich.example' }),
      request('forwarded-host-list', '/robots.txt', { 'X-Forwarded-Host' => 'evil.example, dawarich.example' }),
      request('forwarded-host-comma', '/robots.txt', { 'X-Forwarded-Host' => 'dawarich.example,' }),
      request('forwarded-host-blank', '/robots.txt', { 'X-Forwarded-Host' => ' ' }),
      request('cors-origin', '/robots.txt', { 'Origin' => 'https://dawarich.app' }),
      request('ssl-css-gzip', '/app.css', { 'Accept-Encoding' => 'gzip', 'X-Forwarded-Proto' => 'https' },
              stack: 'force_ssl'),
      request('ssl-forwarded-ssl', '/robots.txt', { 'X-Forwarded-Ssl' => 'on' }, stack: 'force_ssl'),
      request('ssl-ims', '/robots.txt', { 'X-Forwarded-Proto' => 'https', 'If-Modified-Since' => stamp },
              stack: 'force_ssl')
    ]
  end

  def proxied_requests
    [
      request('post', '/robots.txt', method: 'POST'), request('options', '/robots.txt', method: 'OPTIONS'),
      request('range', '/robots.txt', { 'Range' => 'bytes=0-3' }),
      request('range-multi', '/robots.txt', { 'Range' => 'bytes=0-1,3-4' }),
      request('dotdot', '/../robots.txt'), request('dotdot-encoded', '/%2e%2e/robots.txt'),
      request('dot-segment', '/./robots.txt'), request('docs-dotdot', '/docs/../robots.txt'),
      request('double-slash', '//robots.txt'), request('inner-double-slash', '/sub//deep/file.txt'),
      request('dotfile', '/.hidden.txt'), request('dotdir', '/.well-known/apple-app-site-association'),
      request('symlink', '/link.txt'), request('symlink-escape', '/escape.txt'),
      request('symlink-dir', '/linkdir/deep/file.txt'), request('nul', '/robots.txt%00'),
      request('bad-escape', '/%zz'), request('invalid-utf8', '/%ff.txt'),
      request('backslash', '/sub%5Cdeep.txt'), request('unknown-extension', '/weird.xyz'),
      request('pdf', '/doc.pdf'), request('missing', '/missing.css'), request('only-gz-plain', '/only-gz.css'),
      request('root', '/'), request('dir-without-index', '/sub'),
      request('host-blocked', '/robots.txt', host: 'evil.example'),
      request('no-host', '/robots.txt', host: nil, version: '1.0'),
      request('forwarded-host-blocked', '/robots.txt', { 'X-Forwarded-Host' => 'evil.example' }),
      request('forwarded-host-list-blocked', '/robots.txt', { 'X-Forwarded-Host' => 'dawarich.example, evil.example' }),
      request('ssl-http', '/robots.txt', stack: 'force_ssl'),
      request('ssl-forwarded-http', '/robots.txt', { 'X-Forwarded-Proto' => 'http' }, stack: 'force_ssl')
    ]
  end

  def serve(app)
    server = Puma::Server.new(app, nil, min_threads: 0, max_threads: 4, log_writer: Puma::LogWriter.null)
    server.add_tcp_listener('127.0.0.1', 0)
    server.run
    [server, server.connected_ports.first]
  end

  def raw_request(request)
    lines = request['headers'].map { |name, value| "#{name}: #{value}\r\n" }
    "#{request['method']} #{request['target']} HTTP/#{request['version']}\r\n#{lines.join}Connection: close\r\n\r\n"
  end

  def puma_answer(port, request)
    socket = TCPSocket.new('127.0.0.1', port)
    socket.write(raw_request(request))
    raw = socket.read.b
    socket.close
    head, body = raw.split("\r\n\r\n", 2)
    status_line, *lines = head.split("\r\n")
    headers = lines.map { |line| line.split(':', 2).map(&:strip) }
    PhoenixPublicFilesFixture.response(status_line.split[1].to_i, headers, body.to_s)
  end

  it 'writes app-phoenix/test/fixtures/public_files.json' do
    Dir.mktmpdir do |dir|
      root = File.join(dir, 'public')
      PhoenixPublicFilesFixture.build_tree(root, tree)
      stacks = PhoenixPublicFilesFixture.stacks(root, application_hosts)
      servers = stacks.transform_values { |app| serve(app) }

      requests = (served_requests + proxied_requests).map do |request|
        answer = puma_answer(servers.fetch(request['stack']).last, request)
        expect(PhoenixPublicFilesFixture.rack_answer(stacks.fetch(request['stack']), request))
          .to eq(answer), request['name']
        request.merge('response' => answer)
      end
      servers.each_value { |server, _| server.stop(true) }

      expect(requests.map { |request| request['name'] }).to eq(requests.map { |request| request['name'] }.uniq)
      extensions = tree['files'].map { |file| File.extname(file['path']).downcase }.uniq.sort
      fixture = {
        rails_settings: PhoenixPublicFilesFixture.settings,
        rails_mime_types: PhoenixPublicFilesFixture.mime_types(extensions),
        application_hosts: application_hosts,
        tree: tree,
        requests: requests
      }
      File.write(Rails.root.join(PhoenixPublicFilesFixture::PATH), "#{JSON.pretty_generate(fixture)}\n")
    end
  end
end
