# frozen_string_literal: true

Grover.configure do |config|
  config.options = {
    format: 'png',
    quality: 90,
    wait_until: 'networkidle0',
    launch_args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
  }
end
