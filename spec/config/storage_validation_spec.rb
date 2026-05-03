# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'StorageValidation' do
  let(:validator) do
    require Rails.root.join('config/initializers/storage_validation')
    Dawarich::StorageValidation
  end

  let(:required_vars) { %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_BUCKET] }

  def stub_env(overrides)
    allow(ENV).to receive(:[]).and_call_original
    overrides.each do |key, value|
      allow(ENV).to receive(:[]).with(key).and_return(value)
    end
  end

  context 'when STORAGE_BACKEND is not s3' do
    it 'is a no-op when STORAGE_BACKEND is unset' do
      stub_env('STORAGE_BACKEND' => nil)

      expect { validator.validate! }.not_to raise_error
    end

    it 'is a no-op for the local backend' do
      stub_env('STORAGE_BACKEND' => 'local')

      expect { validator.validate! }.not_to raise_error
    end
  end

  context 'when STORAGE_BACKEND=s3' do
    it 'passes when every required AWS_* var is set' do
      env = required_vars.each_with_object('STORAGE_BACKEND' => 's3') { |v, h| h[v] = 'value' }
      stub_env(env)

      expect { validator.validate! }.not_to raise_error
    end

    required_vars = %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_BUCKET]
    required_vars.each do |missing_var|
      it "raises a clear error when #{missing_var} is missing" do
        env = required_vars.each_with_object('STORAGE_BACKEND' => 's3') { |v, h| h[v] = 'value' }
        env[missing_var] = nil
        stub_env(env)

        expect { validator.validate! }.to raise_error(
          Dawarich::StorageValidation::MissingEnvError,
          /#{missing_var}/
        )
      end
    end

    it 'lists every missing var when more than one is missing' do
      stub_env(
        'STORAGE_BACKEND' => 's3',
        'AWS_ACCESS_KEY_ID' => nil,
        'AWS_SECRET_ACCESS_KEY' => nil,
        'AWS_REGION' => 'eu-west-1',
        'AWS_BUCKET' => 'my-bucket'
      )

      expect { validator.validate! }.to raise_error(
        Dawarich::StorageValidation::MissingEnvError
      ) do |e|
        expect(e.message).to include('AWS_ACCESS_KEY_ID')
        expect(e.message).to include('AWS_SECRET_ACCESS_KEY')
      end
    end

    it 'treats blank strings as missing' do
      stub_env(
        'STORAGE_BACKEND' => 's3',
        'AWS_ACCESS_KEY_ID' => '',
        'AWS_SECRET_ACCESS_KEY' => 'secret',
        'AWS_REGION' => 'eu-west-1',
        'AWS_BUCKET' => 'my-bucket'
      )

      expect { validator.validate! }.to raise_error(
        Dawarich::StorageValidation::MissingEnvError,
        /AWS_ACCESS_KEY_ID/
      )
    end
  end
end
