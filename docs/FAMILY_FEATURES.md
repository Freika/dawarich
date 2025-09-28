# Family Features Documentation

## Overview

The Family Features system allows users to create and manage family groups for shared location tracking and collaboration. This feature is designed with flexibility for both self-hosted and cloud deployments.

## Architecture

### Core Models

- **Family**: Central entity representing a family group
- **FamilyMembership**: Join table linking users to families with roles
- **FamilyInvitation**: Manages invitation flow for new family members

### Database Schema

```sql
-- families table
CREATE TABLE families (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  creator_id BIGINT NOT NULL REFERENCES users(id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- family_memberships table
CREATE TABLE family_memberships (
  id BIGSERIAL PRIMARY KEY,
  family_id BIGINT NOT NULL REFERENCES families(id),
  user_id BIGINT NOT NULL REFERENCES users(id),
  role INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- family_invitations table
CREATE TABLE family_invitations (
  id BIGSERIAL PRIMARY KEY,
  family_id BIGINT NOT NULL REFERENCES families(id),
  email VARCHAR(255) NOT NULL,
  invited_by_id BIGINT NOT NULL REFERENCES users(id),
  status INTEGER NOT NULL DEFAULT 0,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
```

### Performance Optimizations

The system includes several performance optimizations:

- **Database Indexes**: Optimized indexes for common queries
- **Caching**: Model-level caching for frequently accessed data
- **Background Jobs**: Asynchronous email processing
- **Query Optimization**: Includes and preloading for N+1 prevention

## Feature Gating

### Configuration

Family features can be enabled/disabled through `DawarichSettings`:

```ruby
# Check if family feature is enabled
DawarichSettings.family_feature_enabled?

# Check if feature is available for specific user
DawarichSettings.family_feature_available_for?(user)
```

### Deployment Types

- **Self-hosted**: Family features are enabled by default
- **Cloud hosted**: Features require subscription validation
- **Disabled**: All family routes and UI elements are hidden

## API Endpoints

### REST API

```
GET    /families                    # List/redirect to user's family
GET    /families/:id                # Show family details
POST   /families                    # Create new family
PATCH  /families/:id                # Update family
DELETE /families/:id                # Delete family
DELETE /families/:id/leave          # Leave family

# Family Invitations
GET    /families/:family_id/invitations     # List invitations
POST   /families/:family_id/invitations     # Send invitation
GET    /families/:family_id/invitations/:id # Show invitation
DELETE /families/:family_id/invitations/:id # Cancel invitation

# Family Members
GET    /families/:family_id/members         # List members
GET    /families/:family_id/members/:id     # Show member
DELETE /families/:family_id/members/:id     # Remove member

# Public Invitation Acceptance
GET    /family_invitations/:token           # Show invitation
POST   /family_invitations/:token/accept    # Accept invitation
POST   /family_invitations/:token/decline   # Decline invitation
```

### API Responses

All endpoints return consistent JSON responses:

```json
{
  "success": true,
  "data": { ... },
  "errors": []
}
```

## Security

### Authorization

The system uses Pundit policies for authorization:

- **FamilyPolicy**: Controls family access and modifications
- **FamilyInvitationPolicy**: Manages invitation permissions
- **FamilyMembershipPolicy**: Controls member management

### Access Control

- Only family owners can send invitations
- Only family owners can remove members
- Members can only leave families voluntarily
- Invitations expire automatically for security

### Data Protection

- Email addresses in invitations are validated
- Invitation tokens are cryptographically secure
- User data is protected through proper authorization

## Error Handling

### Service Layer

All family services implement comprehensive error handling:

```ruby
class Families::Create
  include ActiveModel::Validations

  def call
    return false unless valid?
    # ... implementation
  rescue ActiveRecord::RecordInvalid => e
    handle_record_invalid_error(e)
    false
  rescue StandardError => e
    handle_generic_error(e)
    false
  end

  def error_message
    return errors.full_messages.first if errors.any?
    return @custom_error_message if @custom_error_message
    'Operation failed'
  end
end
```

### Error Types

- **Validation Errors**: Invalid input data
- **Authorization Errors**: Insufficient permissions
- **Business Logic Errors**: Family limits, existing memberships
- **System Errors**: Database, email delivery failures

## UI Components

### Interactive Elements

- **Family Creation Form**: Real-time validation
- **Invitation Management**: Dynamic invite sending
- **Member Management**: Role-based controls
- **Flash Messages**: Animated feedback system

### Stimulus Controllers

JavaScript controllers provide enhanced interactivity:

- `family_invitation_controller.js`: Invitation form validation
- `family_member_controller.js`: Member management actions
- `flash_message_controller.js`: Animated notifications

## Background Jobs

### Email Processing

```ruby
# Invitation emails are sent asynchronously
FamilyMailer.invitation(@invitation).deliver_later(
  queue: :mailer,
  retry: 3,
  wait: 30.seconds
)
```

### Cleanup Jobs

```ruby
# Automatic cleanup of expired invitations
class FamilyInvitationsCleanupJob < ApplicationJob
  def perform
    # Update expired invitations
    # Remove old expired/cancelled invitations
  end
end
```

## Configuration

### Environment Variables

```bash
# Feature toggles
FAMILY_FEATURE_ENABLED=true

# Email configuration for invitations
SMTP_HOST=smtp.example.com
SMTP_USERNAME=user@example.com
SMTP_PASSWORD=secret

# Background job configuration
REDIS_URL=redis://localhost:6379/0
```

### Cron Jobs

```ruby
# config/schedule.rb
every 1.hour do
  runner "FamilyInvitationsCleanupJob.perform_later"
end
```

## Testing

### Test Coverage

The family features include comprehensive test coverage:

- **Unit Tests**: Service classes, models, helpers
- **Integration Tests**: Controller actions, API endpoints
- **System Tests**: End-to-end user workflows
- **Job Tests**: Background job processing

### Test Patterns

```ruby
# Service testing pattern
RSpec.describe Families::Create do
  describe '#call' do
    context 'with valid parameters' do
      it 'creates a family successfully' do
        # ... test implementation
      end
    end

    context 'with invalid parameters' do
      it 'returns false and sets error message' do
        # ... test implementation
      end
    end
  end
end
```

## Deployment

### Database Migrations

Run migrations to set up family tables:

```bash
rails db:migrate
```

### Index Creation

Performance indexes are created concurrently:

```bash
# Handled automatically in migration
# Uses disable_ddl_transaction! for zero-downtime deployment
```

### Background Jobs

Ensure Sidekiq is running for email processing:

```bash
bundle exec sidekiq
```

### Cron Jobs

Set up periodic cleanup:

```bash
# Add to crontab or use whenever gem
0 * * * * cd /app && bundle exec rails runner "FamilyInvitationsCleanupJob.perform_later"
```

## Monitoring

### Metrics

Key metrics to monitor:

- Family creation rate
- Invitation acceptance rate
- Email delivery success rate
- Background job processing time

### Logging

Important events are logged:

```ruby
Rails.logger.info "Family created: #{family.id}"
Rails.logger.warn "Failed to send invitation email: #{error.message}"
Rails.logger.error "Unexpected error in family service: #{error.message}"
```

## Troubleshooting

### Common Issues

1. **Email Delivery Failures**
   - Check SMTP configuration
   - Verify email credentials
   - Monitor Sidekiq queue

2. **Authorization Errors**
   - Verify Pundit policies
   - Check user permissions
   - Review family membership status

3. **Performance Issues**
   - Monitor database indexes
   - Check query optimization
   - Review caching implementation

### Debug Commands

```bash
# Check family feature status
rails console
> DawarichSettings.family_feature_enabled?

# Monitor background jobs
bundle exec sidekiq
> Sidekiq::Queue.new('mailer').size

# Check database indexes
rails dbconsole
> \d family_invitations
```

## Future Enhancements

### Planned Features

- **Family Statistics**: Shared analytics dashboard
- **Location Sharing**: Real-time family member locations
- **Group Trips**: Collaborative trip planning
- **Enhanced Permissions**: Granular access controls

### Scalability Considerations

- **Horizontal Scaling**: Stateless service design
- **Database Sharding**: Family-based data partitioning
- **Caching Strategy**: Redis-based family data caching
- **API Rate Limiting**: Per-family API quotas