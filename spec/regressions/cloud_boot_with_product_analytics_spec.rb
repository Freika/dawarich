# frozen_string_literal: true

require 'spec_helper'
require 'open3'

RSpec.describe 'Cloud boot with product analytics configured' do
  it 'boots the application' do
    env = {
      'SELF_HOSTED' => 'false',
      'PRODUCT_POSTHOG_API_KEY' => 'phc_test',
      'PRODUCT_POSTHOG_PERSONAL_API_KEY' => 'personal_test',
      'PRODUCT_POSTHOG_PROJECT_ID' => '123'
    }

    stdout, stderr, status = Open3.capture3(env, 'bin/rails', 'runner', 'print :booted',
                                            chdir: File.expand_path('../..', __dir__))

    expect(stderr).not_to include('NameError')
    expect(status).to be_success
    expect(stdout).to end_with('booted')
  end
end
