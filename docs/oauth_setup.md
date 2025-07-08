# OAuth/OpenID Connect Setup Guide

This guide explains how to configure OAuth2 and OpenID Connect authentication for the application.

## Supported Providers

The application supports the following authentication providers:

- **Google OAuth2** - Google accounts
- **GitHub OAuth** - GitHub accounts  
- **Microsoft Office 365** - Microsoft accounts
- **Authentik** - OpenID Connect provider
- **Authelia** - OpenID Connect provider
- **Keycloak** - OpenID Connect provider

## Prerequisites

1. Ensure you have the required gems installed (they should be in your Gemfile):
   - `omniauth`
   - `omniauth-google-oauth2`
   - `omniauth-github`
   - `omniauth-microsoft-office365`
   - `omniauth-openid-connect`

2. Run the database migration to add OAuth fields:
   ```bash
   rails db:migrate
   ```

## Environment Configuration

Copy the example environment file and configure your OAuth providers:

```bash
cp config/oauth_example.env .env
```

### Required Environment Variables

#### Application URL
```
APP_URL=https://your-app-domain.com
```

#### Google OAuth2 Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the Google+ API
4. Go to "Credentials" and create an OAuth 2.0 Client ID
5. Add your domain to authorized origins
6. Add `https://your-app-domain.com/users/auth/google_oauth2/callback` to authorized redirect URIs

```
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret
```

#### GitHub OAuth Setup

1. Go to [GitHub Developer Settings](https://github.com/settings/developers)
2. Create a new OAuth App
3. Set the Authorization callback URL to `https://your-app-domain.com/users/auth/github/callback`

```
GITHUB_CLIENT_ID=your_github_client_id
GITHUB_CLIENT_SECRET=your_github_client_secret
```

#### Microsoft Office 365 Setup

1. Go to [Azure Portal](https://portal.azure.com/)
2. Register a new application
3. Add redirect URI: `https://your-app-domain.com/users/auth/microsoft_office365/callback`
4. Grant appropriate permissions (User.Read)

```
MICROSOFT_CLIENT_ID=your_microsoft_client_id
MICROSOFT_CLIENT_SECRET=your_microsoft_client_secret
```

#### Authentik OpenID Connect Setup

1. In your Authentik instance, create a new OAuth2/OpenID Provider
2. Set the redirect URI to `https://your-app-domain.com/users/auth/authentik/callback`
3. Note the Client ID and Client Secret

```
AUTHENTIK_HOST=your-authentik-domain.com
AUTHENTIK_ISSUER=https://your-authentik-domain.com/application/o/your-app-name/
AUTHENTIK_CLIENT_ID=your_authentik_client_id
AUTHENTIK_CLIENT_SECRET=your_authentik_client_secret
```

#### Authelia OpenID Connect Setup

1. Configure Authelia with OpenID Connect
2. Create a new client with redirect URI: `https://your-app-domain.com/users/auth/authelia/callback`

```
AUTHELIA_HOST=your-authelia-domain.com
AUTHELIA_ISSUER=https://your-authelia-domain.com/
AUTHELIA_CLIENT_ID=your_authelia_client_id
AUTHELIA_CLIENT_SECRET=your_authelia_client_secret
```

#### Keycloak OpenID Connect Setup

1. In Keycloak, create a new client
2. Set Client Protocol to "openid-connect"
3. Add redirect URI: `https://your-app-domain.com/users/auth/keycloak/callback`
4. Set Access Type to "confidential"

```
KEYCLOAK_HOST=your-keycloak-domain.com
KEYCLOAK_ISSUER=https://your-keycloak-domain.com/realms/your-realm
KEYCLOAK_CLIENT_ID=your_keycloak_client_id
KEYCLOAK_CLIENT_SECRET=your_keycloak_client_secret
```

## Usage

Once configured, users will see OAuth login buttons on both the login and registration pages. Users can:

1. Click on any OAuth provider button
2. Authenticate with the provider
3. Be automatically signed in/registered

## User Account Linking

When a user signs in via OAuth for the first time:
- A new user account is created with their email
- The provider and UID are stored for future authentication
- Users can link multiple OAuth providers to the same email address

## Security Considerations

1. **HTTPS Required**: OAuth requires HTTPS in production
2. **Secret Management**: Store client secrets securely, never commit them to version control
3. **Redirect URIs**: Always use exact redirect URIs to prevent authorization code interception
4. **Scope Limitation**: Request only the minimum required scopes from providers

## Troubleshooting

### Common Issues

1. **"Invalid redirect URI"**: Ensure the redirect URI in your OAuth provider matches exactly
2. **"Client not found"**: Verify client ID and secret are correct
3. **"Invalid scope"**: Check that requested scopes are allowed by the provider

### Debug Mode

To enable OAuth debugging, add to your environment:

```
OAUTH_DEBUG=true
```

### Provider-Specific Issues

#### Google
- Ensure Google+ API is enabled
- Check that your domain is in authorized origins

#### GitHub
- Verify the OAuth app is properly configured
- Check that the callback URL is correct

#### Microsoft
- Ensure the app has proper permissions
- Verify the redirect URI format

#### OpenID Connect Providers
- Check that the issuer URL is correct
- Verify discovery endpoint is accessible
- Ensure client credentials are correct

## Testing

You can test OAuth providers in development by:

1. Setting up local OAuth apps with redirect URIs like `http://localhost:3000/users/auth/google_oauth2/callback`
2. Using tools like ngrok to expose localhost for testing
3. Using provider-specific test environments where available

## Migration from Local Accounts

Existing users can link their OAuth accounts by:

1. Signing in with their existing email/password
2. Going to their profile settings
3. Linking additional OAuth providers

The system will automatically match OAuth accounts with existing local accounts based on email address.