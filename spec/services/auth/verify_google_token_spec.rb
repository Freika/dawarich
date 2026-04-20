require 'rails_helper'

RSpec.describe Auth::VerifyGoogleToken do
  let(:id_token) { 'fake.google.id.token' }
  let(:ios_client_id) { 'ios-client-id.apps.googleusercontent.com' }
  let(:android_client_id) { 'android-client-id.apps.googleusercontent.com' }

  describe '#call' do
    context 'when validator accepts the token' do
      it 'returns symbolized claims' do
        stub_const(
          'ENV',
          ENV.to_hash.merge(
            'GOOGLE_IOS_CLIENT_ID' => ios_client_id,
            'GOOGLE_ANDROID_CLIENT_ID' => android_client_id
          )
        )

        validator = instance_double(GoogleIDToken::Validator)
        allow(GoogleIDToken::Validator).to receive(:new).and_return(validator)
        allow(validator).to receive(:check)
          .with(id_token, [ios_client_id, android_client_id])
          .and_return({ 'sub' => 'google-user-id', 'email' => 'user@example.com' })

        result = described_class.new(id_token).call

        expect(result).to eq(sub: 'google-user-id', email: 'user@example.com')
      end
    end

    context 'when validator raises ValidationError' do
      it 'raises InvalidToken' do
        stub_const(
          'ENV',
          ENV.to_hash.merge(
            'GOOGLE_IOS_CLIENT_ID' => ios_client_id,
            'GOOGLE_ANDROID_CLIENT_ID' => android_client_id
          )
        )

        validator = instance_double(GoogleIDToken::Validator)
        allow(GoogleIDToken::Validator).to receive(:new).and_return(validator)
        allow(validator).to receive(:check)
          .and_raise(GoogleIDToken::ValidationError.new('bad signature'))

        expect { described_class.new(id_token).call }
          .to raise_error(Auth::VerifyGoogleToken::InvalidToken, /bad signature/)
      end
    end

    context 'when no client IDs are configured' do
      it 'raises InvalidToken' do
        env_without_clients = ENV.to_hash.dup
        env_without_clients.delete('GOOGLE_IOS_CLIENT_ID')
        env_without_clients.delete('GOOGLE_ANDROID_CLIENT_ID')
        stub_const('ENV', env_without_clients)

        expect { described_class.new(id_token).call }
          .to raise_error(Auth::VerifyGoogleToken::InvalidToken, /not configured/)
      end
    end
  end
end
