# Family Features

Dawarich includes comprehensive family management features that allow users to create family groups, invite members, and collaborate on location tracking.

## Quick Start

### For Self-Hosted Deployments

Family features are enabled by default for self-hosted installations:

```bash
# Family features are automatically available
# No additional configuration required
```

### For Cloud Deployments

Family features require subscription validation:

```bash
# Contact support to enable family features
# Subscription-based access control
```

## Features Overview

### Family Management
- Create and name family groups
- Invite members via email
- Role-based permissions (owner/member)
- Member management and removal

### Invitation System
- Secure email-based invitations
- Automatic expiration (7 days)
- Token-based acceptance flow
- Cancellation and resending options

### Security & Privacy
- Authorization via Pundit policies
- Encrypted invitation tokens
- Email validation and verification
- Automatic cleanup of expired data

### Performance & Scalability
- Optimized database indexes
- Background job processing
- Intelligent caching strategies
- Concurrent database operations

## Getting Started

### Creating a Family

1. Navigate to the Families section
2. Click "Create Family"
3. Enter a family name
4. You become the family owner automatically

### Inviting Members

1. Go to your family page
2. Click "Invite Member"
3. Enter the email address
4. The invitation is sent automatically
5. Member receives email with acceptance link

### Accepting Invitations

1. Member receives invitation email
2. Clicks the invitation link
3. Must be logged in to Dawarich
4. Accepts or declines the invitation
5. Automatically joins the family if accepted

## API Documentation

### REST Endpoints

```bash
# List families or redirect to user's family
GET /families

# Show family details (requires authorization)
GET /families/:id

# Create new family
POST /families
Content-Type: application/json
{
  "family": {
    "name": "Smith Family"
  }
}

# Update family name
PATCH /families/:id
Content-Type: application/json
{
  "family": {
    "name": "Updated Name"
  }
}

# Delete family (owner only, requires empty family)
DELETE /families/:id

# Leave family (members only)
DELETE /families/:id/leave

# Send invitation
POST /families/:family_id/invitations
Content-Type: application/json
{
  "invitation": {
    "email": "member@example.com"
  }
}

# Cancel invitation
DELETE /families/:family_id/invitations/:id

# Accept invitation (public endpoint)
POST /family_invitations/:token/accept

# Decline invitation (public endpoint)
POST /family_invitations/:token/decline
```

### API Responses

All endpoints return JSON responses:

```json
{
  "success": true,
  "data": {
    "family": {
      "id": 1,
      "name": "Smith Family",
      "member_count": 3,
      "creator": {
        "id": 1,
        "email": "owner@example.com"
      },
      "members": [...],
      "pending_invitations": [...]
    }
  },
  "errors": []
}
```

## Configuration

### Environment Variables

```bash
# Enable/disable family features
FAMILY_FEATURE_ENABLED=true

# For cloud deployments - require subscription
FAMILY_SUBSCRIPTION_REQUIRED=true

# Email configuration for invitations
SMTP_HOST=smtp.example.com
SMTP_USERNAME=noreply@example.com
SMTP_PASSWORD=secret_password

# Background jobs
REDIS_URL=redis://localhost:6379/0
```

### Feature Gating

Family features can be controlled programmatically:

```ruby
# Check if features are enabled
DawarichSettings.family_feature_enabled?
# => true/false

# Check if available for specific user (cloud)
DawarichSettings.family_feature_available_for?(user)
# => true/false based on subscription
```

## Database Schema

### Core Tables

```sql
-- Main family entity
CREATE TABLE families (
  id bigserial PRIMARY KEY,
  name varchar(255) NOT NULL,
  creator_id bigint NOT NULL REFERENCES users(id),
  created_at timestamp NOT NULL,
  updated_at timestamp NOT NULL
);

-- User-family relationships with roles
CREATE TABLE family_memberships (
  id bigserial PRIMARY KEY,
  family_id bigint NOT NULL REFERENCES families(id),
  user_id bigint NOT NULL REFERENCES users(id),
  role integer NOT NULL DEFAULT 0, -- 0: member, 1: owner
  created_at timestamp NOT NULL,
  updated_at timestamp NOT NULL,
  UNIQUE(family_id, user_id)
);

-- Invitation management
CREATE TABLE family_invitations (
  id bigserial PRIMARY KEY,
  family_id bigint NOT NULL REFERENCES families(id),
  email varchar(255) NOT NULL,
  invited_by_id bigint NOT NULL REFERENCES users(id),
  token varchar(255) NOT NULL UNIQUE,
  status integer NOT NULL DEFAULT 0, -- 0: pending, 1: accepted, 2: declined, 3: expired, 4: cancelled
  expires_at timestamp NOT NULL,
  created_at timestamp NOT NULL,
  updated_at timestamp NOT NULL
);
```

### Performance Indexes

```sql
-- Optimized for common queries
CREATE INDEX CONCURRENTLY idx_family_invitations_family_status_expires
  ON family_invitations (family_id, status, expires_at);

CREATE INDEX CONCURRENTLY idx_family_memberships_family_role
  ON family_memberships (family_id, role);

CREATE INDEX CONCURRENTLY idx_family_invitations_email
  ON family_invitations (email);

CREATE INDEX CONCURRENTLY idx_family_invitations_status_expires
  ON family_invitations (status, expires_at);
```

## Testing

### Running Tests

```bash
# Run all family-related tests
bundle exec rspec spec/models/family_spec.rb
bundle exec rspec spec/services/families/
bundle exec rspec spec/controllers/families_controller_spec.rb
bundle exec rspec spec/requests/families_spec.rb

# Run specific test categories
bundle exec rspec --tag family
bundle exec rspec --tag invitation
```

### Test Coverage

The family features include comprehensive test coverage:

- **Unit Tests**: Models, services, helpers
- **Integration Tests**: Controllers, API endpoints
- **System Tests**: End-to-end user workflows
- **Job Tests**: Background email processing

## Deployment

### Production Deployment

```bash
# 1. Run database migrations
RAILS_ENV=production bundle exec rails db:migrate

# 2. Precompile assets (includes family JS/CSS)
RAILS_ENV=production bundle exec rails assets:precompile

# 3. Start background job workers
bundle exec sidekiq -e production -d

# 4. Verify deployment
curl -H "Authorization: Bearer $API_TOKEN" \
     https://your-app.com/families
```

### Zero-Downtime Deployment

The family feature supports zero-downtime deployment:

- Database indexes created with `CONCURRENTLY`
- Backward-compatible migrations
- Feature flags for gradual rollout
- Background job graceful shutdown

### Monitoring

Key metrics to monitor:

```yaml
# Family creation rate
family_creation_rate: rate(families_created_total[5m])

# Invitation success rate
invitation_success_rate:
  rate(invitations_accepted_total[5m]) /
  rate(invitations_sent_total[5m])

# Email delivery rate
email_delivery_success_rate:
  rate(family_emails_delivered_total[5m]) /
  rate(family_emails_sent_total[5m])

# API response times
family_api_p95_response_time:
  histogram_quantile(0.95, family_api_duration_seconds)
```

## Security

### Authorization Model

Family features use Pundit policies for authorization:

```ruby
# Family access control
class FamilyPolicy < ApplicationPolicy
  def show?
    user_is_member?
  end

  def update?
    user_is_owner?
  end

  def destroy?
    user_is_owner? && family.members.count <= 1
  end
end
```

### Data Protection

- All invitation tokens are cryptographically secure
- Email addresses are validated before storage
- Automatic cleanup of expired invitations
- User data protected through proper authorization

### Security Best Practices

- Never log invitation tokens
- Validate all email addresses
- Use HTTPS for all invitation links
- Implement rate limiting on invitation sending
- Monitor for suspicious activity patterns

## Troubleshooting

### Common Issues

**1. Email Delivery Failures**
```bash
# Check SMTP configuration
RAILS_ENV=production bundle exec rails console
> ActionMailer::Base.smtp_settings

# Monitor Sidekiq queue
bundle exec sidekiq -e production
> Sidekiq::Queue.new('mailer').size
```

**2. Authorization Errors**
```bash
# Verify user permissions
RAILS_ENV=production bundle exec rails console
> user = User.find(1)
> family = Family.find(1)
> FamilyPolicy.new(user, family).show?
```

**3. Performance Issues**
```sql
-- Check index usage
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE tablename LIKE 'family%'
ORDER BY idx_scan DESC;

-- Monitor slow queries
SELECT query, mean_time, calls
FROM pg_stat_statements
WHERE query LIKE '%family%'
ORDER BY mean_time DESC;
```

## Support

### Documentation
- [Family Features Guide](FAMILY_FEATURES.md)
- [Deployment Guide](FAMILY_DEPLOYMENT.md)
- [API Documentation](/api-docs)

### Community
- [GitHub Issues](https://github.com/Freika/dawarich/issues)
- [Discord Server](https://discord.gg/pHsBjpt5J8)
- [GitHub Discussions](https://github.com/Freika/dawarich/discussions)

### Contributing

Contributions to family features are welcome:

1. Check existing issues for family-related bugs
2. Follow the existing code patterns and conventions
3. Include comprehensive tests for new features
4. Update documentation for any API changes
5. Follow the contribution guidelines in CONTRIBUTING.md