# frozen_string_literal: true

module InstanceGeocodingHelpers
  # Configures geocoding for the whole instance the way an admin would, so
  # Geocoding::Config resolves an enabled provider. With no arguments it stores
  # a Photon host, which is enough for any spec that only needs geocoding on.
  def configure_instance_geocoding(**settings)
    settings = { photon_api_host: 'photon.test.example.com' } if settings.empty?
    settings.each { |key, value| InstanceSetting.create!(key: key.to_s, value: value) }
    InstanceSettings::Resolver.reset!
  end

  # For specs that assert on the HTTP request a provider lookup makes.
  def use_real_geocoding_lookups
    allow(Geocoding::UserLookup).to receive(:build).and_call_original
  end
end

RSpec.configure do |config|
  config.include InstanceGeocodingHelpers

  # A developer's .env can set a provider variable, and the resolver reads the
  # environment first, so each example starts from an unconfigured instance.
  config.around(:each) do |example|
    variables = InstanceSettings::Registry::DEFINITIONS.values.map(&:env_var)
    saved = variables.index_with { |name| ENV.fetch(name, nil) }
    variables.each { |name| ENV.delete(name) }
    InstanceSettings::Resolver.reset!
    example.run
  ensure
    saved&.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    InstanceSettings::Resolver.reset!
  end

  config.before(:each) do
    allow(Geocoder).to receive(:search).and_return(
      [
        double(
          data: {
            'properties' => {
              'countrycode' => 'US',
              'country' => 'United States',
              'state' => 'New York',
              'name' => 'Test Location'
            }
          },
          address: 'Test Location, New York, United States',
          latitude: 40.7128,
          longitude: -74.0060
        )
      ]
    )

    # Configured lookups answer from the same Geocoder.search stub, so a spec
    # controls provider results in one place whichever provider is configured.
    allow(Geocoding::UserLookup).to receive(:build) do
      Class.new do
        def search(query)
          Geocoder.search(query.text, **query.options.except(:lookup))
        end
      end.new
    end
  end
end
