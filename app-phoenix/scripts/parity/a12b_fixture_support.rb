# frozen_string_literal: true

require 'open3'

module A12bFixtureSupport
  SECRET = JSON.parse(Rails.root.join('app-phoenix/test/fixtures/rails_cookies.json').read).fetch('rails_test_secret')
  ARCHIVE_PHRASE = 'phoenix-a12b-archive-phrase-not-for-production'
  ROTATED_BASE = 'phoenix-a12b-rotated-base-not-for-production'
  NOW = Time.utc(2026, 10, 2, 12, 0, 0)
  DIR = Rails.root.join('app-phoenix/test/fixtures/a12b')

  module_function

  def write?
    ENV['WRITE_PHOENIX_FIXTURES'] == '1'
  end

  def read(name)
    JSON.parse(DIR.join(name).read)
  end

  def write(name, data)
    FileUtils.mkdir_p(DIR)
    DIR.join(name).write("#{Oj.dump(FixtureRecording.normalize(data), mode: :strict, indent: 2)}\n")
  end

  def normalized(data)
    JSON.parse(Oj.dump(FixtureRecording.normalize(data), mode: :strict))
  end

  def phoenix(code)
    env = { 'MIX_ENV' => 'test', 'PATH' => "#{Dir.home}/.asdf/shims:#{ENV.fetch('PATH')}",
            'PHOENIX_TEST_REDIS_URL' => ENV.fetch('PHOENIX_TEST_REDIS_URL'), 'DATABASE_HOST' => '127.0.0.1' }
    out, status = Open3.capture2e(env, 'mix', 'run', '--no-start', '-e', code,
                                  chdir: Rails.root.join('app-phoenix').to_s)
    raise out unless status.success?

    JSON.parse(out.lines.last)
  end

  def set_cookie_line(response, name)
    Array(response.headers['Set-Cookie']).flat_map { |line| line.split("\n") }
                                         .find { |line| line.start_with?("#{name}=") }
  end

  def cookie_value(line)
    line.split(';').first.split('=', 2).last
  end
end
