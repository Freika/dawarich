# Patreon Integration

Dawarich Cloud includes Patreon OAuth integration that allows users to connect their Patreon accounts. This enables checking if users are patrons of specific creators.

## Features

- **OAuth Authentication**: Users can connect their Patreon accounts via OAuth 2.0
- **Patron Status Checking**: Check if a user is an active patron of specific creators
- **Membership Data**: Access detailed information about user's Patreon memberships
- **Token Management**: Automatic token refresh to maintain API access

## Setup

### Environment Variables

Configure the following environment variables for Dawarich Cloud:

```bash
PATREON_CLIENT_ID=your_patreon_client_id
PATREON_CLIENT_SECRET=your_patreon_client_secret
```

### Getting Patreon OAuth Credentials

1. Go to [Patreon Developer Portal](https://www.patreon.com/portal/registration/register-clients)
2. Create a new OAuth client
3. Set the redirect URI to: `https://your-domain.com/users/auth/patreon/callback`
4. Copy the Client ID and Client Secret

## Usage

### User Connection

Users can connect their Patreon account in the account settings:

1. Navigate to Settings
2. Find the "Connected Accounts" section
3. Click "Connect" next to Patreon
4. Authorize the application on Patreon
5. Get redirected back to Dawarich

### Checking Patron Status

#### Check if User is a Patron of Specific Creator

```ruby
# Get Dawarich creator's Patreon ID (find it in your Patreon campaign URL)
dawarich_creator_id = 'your_creator_id'

# Check if current user is a patron
if current_user.patron_of?(dawarich_creator_id)
  # User is an active patron!
  # Grant special features, show badge, etc.
end
```

#### Get All Memberships

```ruby
# Get all campaigns the user is supporting
memberships = current_user.patreon_memberships

memberships.each do |membership|
  campaign = membership['campaign']

  puts "Supporting: #{campaign['attributes']['vanity']}"
  puts "URL: #{campaign['attributes']['url']}"
  puts "Status: #{membership['attributes']['patron_status']}"
  puts "Since: #{membership['attributes']['pledge_relationship_start']}"
end
```

#### Get Specific Membership Details

```ruby
creator_id = 'your_creator_id'

membership = Patreon::PatronChecker.new(current_user).membership_for(creator_id)

if membership
  # User is a patron
  status = membership.dig('attributes', 'patron_status')
  started_at = membership.dig('attributes', 'pledge_relationship_start')

  # Access campaign details
  campaign = membership['campaign']
  campaign_name = campaign.dig('attributes', 'vanity')
end
```

### Patron Status Values

The `patron_status` field can have the following values:

- `active_patron` - Currently an active patron
- `declined_patron` - Payment declined
- `former_patron` - Was a patron but not anymore

### Example: Show Patron Badge

```ruby
# In a view or helper
def show_patron_badge?(user)
  dawarich_creator_id = ENV['DAWARICH_PATREON_CREATOR_ID']
  return false unless dawarich_creator_id.present?

  user.patron_of?(dawarich_creator_id)
end
```

```erb
<!-- In a view -->
<% if show_patron_badge?(current_user) %>
  <span class="badge badge-primary">
    ❤️ Patreon Supporter
  </span>
<% end %>
```

### Example: Grant Premium Features

```ruby
class User < ApplicationRecord
  def premium_access?
    return true if admin?
    return true if active_subscription? # existing subscription logic

    # Check Patreon support
    dawarich_creator_id = ENV['DAWARICH_PATREON_CREATOR_ID']
    return false unless dawarich_creator_id

    patron_of?(dawarich_creator_id)
  end
end
```

## Token Management

The integration automatically handles token refresh:

- Access tokens are stored securely in the database
- Tokens are automatically refreshed when expired
- If refresh fails, the user needs to reconnect their account

## Disconnecting Patreon

Users can disconnect their Patreon account at any time:

```ruby
current_user.disconnect_patreon!
```

This will:
- Remove the provider/uid linkage
- Clear all stored tokens
- Revoke API access

## Security Considerations

- Access tokens are stored in the database (consider encrypting at rest)
- Tokens are automatically refreshed to maintain access
- API requests are made server-side only
- Users can revoke access at any time from their Patreon settings

## API Rate Limits

Patreon API has rate limits. The service handles this by:
- Caching membership data when possible
- Using efficient API queries
- Handling API errors gracefully

## Troubleshooting

### Token Expired Errors

If users see authentication errors:
1. Ask them to disconnect and reconnect their Patreon account
2. Check that the refresh token is still valid
3. Verify environment variables are set correctly

### Creator ID Not Found

To find a Patreon creator ID:
1. Go to the creator's Patreon page
2. Use the Patreon API: `GET https://www.patreon.com/api/oauth2/v2/campaigns`
3. The campaign ID is the creator ID you need

## Future Enhancements

Potential future features:
- Tier-based access (check pledge amount)
- Lifetime pledge amount tracking
- Patron anniversary badges
- Direct campaign data caching
