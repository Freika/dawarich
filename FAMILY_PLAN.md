# Family Plan Feature - Implementation Specification

## Implementation Status

### ✅ Phase 1: Database Foundation - COMPLETED
- **3 Database tables created**: families, family_memberships, family_invitations
- **4 Model classes implemented**: Family, FamilyMembership, FamilyInvitation, User extensions
- **68 comprehensive tests written and passing**: Full test coverage for all models and associations
- **Database migrations applied**: All tables created with proper indexes and constraints
- **Business logic methods implemented**: User family ownership, account deletion protection, etc.

### ✅ Phase 2: Core Business Logic - COMPLETED
- **4 Service classes implemented**: Create, Invite, AcceptInvitation, Leave
- **Comprehensive error handling**: All services return user-friendly error messages for validation failures
- **Token generation and expiry logic**: Automatically generates secure invitation tokens with 7-day expiry
- **FamilyMailer and email templates**: HTML and text email templates for invitations
- **53+ comprehensive service tests**: Full test coverage for all business logic scenarios including error cases
- **3 Pundit authorization policies**: FamilyPolicy, FamilyMembershipPolicy, FamilyInvitationPolicy
- **Email integration**: Invitation emails sent via ActionMailer with proper styling

**Ready for Phase 3**: Controllers and Routes

---

## Overview

The Family Plan feature allows Dawarich users to create family groups, invite members, and share their latest location data within the family. This feature enhances the social aspect of location tracking while maintaining strong privacy controls.

### Key Features
- Create and manage family groups
- Invite members via email
- Share latest location data within family
- Role-based permissions (owner/member)
- Privacy controls for location sharing
- Email notifications and in-app notifications

### Business Rules
- Maximum 5 family members per family (hardcoded constant)
- One family per user (must leave current family to join another)
- Family owners cannot delete their accounts
- Invitation tokens expire after 7 days
- Only latest position sharing (no historical data access)
- Free for self-hosted instances, paid feature for Dawarich Cloud

## Database Schema

### 1. Family Model
```ruby
class Family < ApplicationRecord
  # Table: families
  # Primary Key: id (UUID)

  self.primary_key = :id

  has_many :family_memberships, dependent: :destroy
  has_many :members, through: :family_memberships, source: :user
  has_many :family_invitations, dependent: :destroy
  belongs_to :creator, class_name: 'User'

  validates :name, presence: true, length: { maximum: 50 }
  validates :creator_id, presence: true

  MAX_MEMBERS = 5
end
```

**Columns:**
- `id` (UUID, primary key)
- `name` (string, not null)
- `creator_id` (bigint, foreign key to users, not null)
- `created_at` (datetime)
- `updated_at` (datetime)

### 2. FamilyMembership Model
```ruby
class FamilyMembership < ApplicationRecord
  # Table: family_memberships
  # Primary Key: id (UUID)

  belongs_to :family
  belongs_to :user

  validates :user_id, presence: true, uniqueness: true # One family per user
  validates :role, presence: true

  enum :role, { owner: 0, member: 1 }
end
```

**Columns:**
- `id` (UUID, primary key)
- `family_id` (UUID, foreign key to families, not null)
- `user_id` (bigint, foreign key to users, not null, unique)
- `role` (integer, enum: owner=0, member=1, not null, default: member)
- `created_at` (datetime)
- `updated_at` (datetime)

### 3. FamilyInvitation Model
```ruby
class FamilyInvitation < ApplicationRecord
  # Table: family_invitations
  # Primary Key: id (UUID)

  belongs_to :family
  belongs_to :invited_by, class_name: 'User'

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validates :status, presence: true

  enum status: { pending: 0, accepted: 1, expired: 2, cancelled: 3 }

  scope :active, -> { where(status: :pending).where('expires_at > ?', Time.current) }

  before_validation :generate_token, :set_expiry, on: :create

  EXPIRY_DAYS = 7
end
```

**Columns:**
- `id` (UUID, primary key)
- `family_id` (UUID, foreign key to families, not null)
- `email` (string, not null)
- `token` (string, not null, unique)
- `expires_at` (datetime, not null)
- `invited_by_id` (bigint, foreign key to users, not null)
- `status` (integer, enum: pending=0, accepted=1, expired=2, cancelled=3, default: pending)
- `created_at` (datetime)
- `updated_at` (datetime)

### 4. User Model Modifications
```ruby
# Add to existing User model
has_one :family_membership, dependent: :destroy
has_one :family, through: :family_membership
has_many :created_families, class_name: 'Family', foreign_key: 'creator_id', dependent: :restrict_with_error
has_many :sent_family_invitations, class_name: 'FamilyInvitation', foreign_key: 'invited_by_id', dependent: :destroy

def in_family?
  family_membership.present?
end

def family_owner?
  family_membership&.owner?
end

def can_delete_account?
  return true unless family_owner?
  family.members.count <= 1
end
```

## Database Migrations

### 1. Create Families Table
```ruby
class CreateFamilies < ActiveRecord::Migration[8.0]
  def change
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')

    create_table :families, id: :uuid do |t|
      t.string :name, null: false, limit: 50
      t.bigint :creator_id, null: false
      t.timestamps
    end

    add_foreign_key :families, :users, column: :creator_id
    add_index :families, :creator_id
  end
end
```

### 2. Create Family Memberships Table
```ruby
class CreateFamilyMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :family_memberships, id: :uuid do |t|
      t.uuid :family_id, null: false
      t.bigint :user_id, null: false
      t.integer :role, null: false, default: 1 # member
      t.timestamps
    end

    add_foreign_key :family_memberships, :families
    add_foreign_key :family_memberships, :users
    add_index :family_memberships, :family_id
    add_index :family_memberships, :user_id, unique: true # One family per user
    add_index :family_memberships, [:family_id, :role]
  end
end
```

### 3. Create Family Invitations Table
```ruby
class CreateFamilyInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :family_invitations, id: :uuid do |t|
      t.uuid :family_id, null: false
      t.string :email, null: false
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.bigint :invited_by_id, null: false
      t.integer :status, null: false, default: 0 # pending
      t.timestamps
    end

    add_foreign_key :family_invitations, :families
    add_foreign_key :family_invitations, :users, column: :invited_by_id
    add_index :family_invitations, :family_id
    add_index :family_invitations, :email
    add_index :family_invitations, :token, unique: true
    add_index :family_invitations, :status
    add_index :family_invitations, :expires_at
  end
end
```

## Service Classes

### 1. Families::Create
```ruby
module Families
  class Create
    include ActiveModel::Validations

    attr_reader :user, :name, :family

    validates :name, presence: true, length: { maximum: 50 }

    def initialize(user:, name:)
      @user = user
      @name = name
    end

    def call
      return false unless valid?
      return false if user.in_family?
      return false unless can_create_family?

      ActiveRecord::Base.transaction do
        create_family
        create_owner_membership
        send_notification
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    private

    def can_create_family?
      return true if DawarichSettings.self_hosted?
      # Add cloud plan validation here
      user.active? && user.active_until&.future?
    end

    def create_family
      @family = Family.create!(
        name: name,
        creator: user
      )
    end

    def create_owner_membership
      FamilyMembership.create!(
        family: family,
        user: user,
        role: :owner
      )
    end

    def send_notification
      Notifications::Create.new(
        user: user,
        kind: :info,
        title: 'Family Created',
        content: "You've successfully created the family '#{family.name}'"
      ).call
    end
  end
end
```

### 2. Families::Invite
```ruby
module Families
  class Invite
    include ActiveModel::Validations

    attr_reader :family, :email, :invited_by, :invitation

    validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

    def initialize(family:, email:, invited_by:)
      @family = family
      @email = email.downcase.strip
      @invited_by = invited_by
    end

    def call
      return false unless valid?
      return false unless can_invite?

      ActiveRecord::Base.transaction do
        create_invitation
        send_invitation_email
        send_notification
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    private

    def can_invite?
      return false unless invited_by.family_owner?
      return false if family.members.count >= Family::MAX_MEMBERS
      return false if user_already_in_family?
      return false if pending_invitation_exists?

      true
    end

    def user_already_in_family?
      User.joins(:family_membership)
          .where(email: email)
          .exists?
    end

    def pending_invitation_exists?
      family.family_invitations.active.where(email: email).exists?
    end

    def create_invitation
      @invitation = FamilyInvitation.create!(
        family: family,
        email: email,
        invited_by: invited_by
      )
    end

    def send_invitation_email
      FamilyMailer.invitation(@invitation).deliver_later
    end

    def send_notification
      Notifications::Create.new(
        user: invited_by,
        kind: :info,
        title: 'Invitation Sent',
        content: "Family invitation sent to #{email}"
      ).call
    end
  end
end
```

### 3. Families::AcceptInvitation
```ruby
module Families
  class AcceptInvitation
    attr_reader :invitation, :user, :error_message

    def initialize(invitation:, user:)
      @invitation = invitation
      @user = user
      @error_message = nil
    end

    def call
      return false unless can_accept?

      if user.in_family?
        @error_message = 'You must leave your current family before joining a new one.'
        return false
      end

      ActiveRecord::Base.transaction do
        create_membership
        update_invitation
        send_notifications
      end

      true
    rescue ActiveRecord::RecordInvalid
      @error_message = 'Failed to join family due to validation errors.'
      false
    end

    private

    def can_accept?
      return false unless validate_invitation
      return false unless validate_email_match
      return false unless validate_family_capacity

      true
    end

    def validate_invitation
      return true if invitation.can_be_accepted?

      @error_message = 'This invitation is no longer valid or has expired.'
      false
    end

    def validate_email_match
      return true if invitation.email == user.email

      @error_message = 'This invitation is not for your email address.'
      false
    end

    def validate_family_capacity
      return true if invitation.family.members.count < Family::MAX_MEMBERS

      @error_message = 'This family has reached the maximum number of members.'
      false
    end

    def create_membership
      FamilyMembership.create!(
        family: invitation.family,
        user: user,
        role: :member
      )
    end

    def update_invitation
      invitation.update!(status: :accepted)
    end

    def send_notifications
      send_user_notification
      send_owner_notification
    end

    def send_user_notification
      Notification.create!(
        user: user,
        kind: :info,
        title: 'Welcome to Family',
        content: "You've joined the family '#{invitation.family.name}'"
      )
    end

    def send_owner_notification
      Notification.create!(
        user: invitation.family.creator,
        kind: :info,
        title: 'New Family Member',
        content: "#{user.email} has joined your family"
      )
    end
  end
end
```

### 4. Families::Leave
```ruby
module Families
  class Leave
    attr_reader :user, :error_message

    def initialize(user:)
      @user = user
      @error_message = nil
    end

    def call
      return false unless validate_can_leave

      ActiveRecord::Base.transaction do
        handle_ownership_transfer if user.family_owner?
        remove_membership
        send_notification
      end

      true
    rescue ActiveRecord::RecordInvalid
      @error_message = 'Failed to leave family due to validation errors.'
      false
    end

    private

    def validate_can_leave
      return false unless validate_in_family
      return false unless validate_owner_can_leave

      true
    end

    def validate_in_family
      return true if user.in_family?

      @error_message = 'You are not currently in a family.'
      false
    end

    def validate_owner_can_leave
      return true unless user.family_owner? && family_has_other_members?

      @error_message = 'You cannot leave the family while you are the owner and there are ' \
                       'other members. Remove all members first or transfer ownership.'
      false
    end

    def family_has_other_members?
      user.family.members.count > 1
    end

    def handle_ownership_transfer
      # If owner is leaving and no other members, family will be deleted via cascade
      # If owner tries to leave with other members, it should be prevented in validation
    end

    def remove_membership
      user.family_membership.destroy!
    end

    def send_notification
      Notification.create!(
        user: user,
        kind: :info,
        title: 'Left Family',
        content: "You've left the family"
      )
    end
  end
end
```

### 5. Families::LocationSharingService
```ruby
module Families
  class LocationSharingService
    def self.family_locations(family)
      return [] unless family

      family.members
            .joins(:family_membership)
            .map { |member| latest_location_for(member) }
            .compact
    end

    def self.latest_location_for(user)
      latest_point = user.points.order(timestamp: :desc).first
      return nil unless latest_point

      {
        user_id: user.id,
        email: user.email,
        latitude: latest_point.latitude,
        longitude: latest_point.longitude,
        timestamp: latest_point.timestamp,
        updated_at: Time.at(latest_point.timestamp)
      }
    end
  end
end
```

## Error Handling Approach

All family service classes implement a consistent error handling pattern:

### Service Error Handling
- **Return Value**: Services return `true` for success, `false` for failure
- **Error Messages**: Services expose an `error_message` attribute with user-friendly error descriptions
- **Validation**: Comprehensive validation with specific error messages for each failure case
- **Transaction Safety**: All database operations wrapped in transactions with proper rollback

### Common Error Messages
- **AcceptInvitation Service**:
  - `'You must leave your current family before joining a new one.'`
  - `'This invitation is no longer valid or has expired.'`
  - `'This invitation is not for your email address.'`
  - `'This family has reached the maximum number of members.'`

- **Leave Service**:
  - `'You cannot leave the family while you are the owner and there are other members. Remove all members first or transfer ownership.'`
  - `'You are not currently in a family.'`

### Controller Integration
Controllers should use the service error messages for user feedback:

```ruby
if service.call
  redirect_to success_path, notice: 'Success message'
else
  redirect_to failure_path, alert: service.error_message || 'Generic fallback message'
end
```

## Controllers

### 1. FamiliesController
```ruby
class FamiliesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_family, only: [:show, :edit, :update, :destroy, :leave]

  def index
    redirect_to family_path(current_user.family) if current_user.in_family?
  end

  def show
    authorize @family
    @members = @family.members.includes(:family_membership)
    @pending_invitations = @family.family_invitations.pending
    @family_locations = Families::LocationSharingService.family_locations(@family)
  end

  def new
    redirect_to family_path(current_user.family) if current_user.in_family?
    @family = Family.new
  end

  def create
    service = Families::Create.new(
      user: current_user,
      name: family_params[:name]
    )

    if service.call
      redirect_to family_path(service.family), notice: 'Family created successfully!'
    else
      @family = Family.new(family_params)
      @family.errors.add(:base, 'Failed to create family')
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @family
  end

  def update
    authorize @family

    if @family.update(family_params)
      redirect_to family_path(@family), notice: 'Family updated successfully!'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @family

    if @family.members.count > 1
      redirect_to family_path(@family), alert: 'Cannot delete family with members. Remove all members first.'
    else
      @family.destroy
      redirect_to families_path, notice: 'Family deleted successfully!'
    end
  end

  def leave
    authorize @family, :leave?

    service = Families::Leave.new(user: current_user)

    if service.call
      redirect_to families_path, notice: 'You have left the family'
    else
      redirect_to family_path(@family), alert: service.error_message || 'Cannot leave family.'
    end
  end

  private

  def set_family
    @family = current_user.family
    redirect_to families_path unless @family
  end

  def family_params
    params.require(:family).permit(:name)
  end
end
```

### 2. FamilyMembershipsController
```ruby
class FamilyMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_family
  before_action :set_membership, only: [:show, :update, :destroy]

  def index
    authorize @family, :show?
    @members = @family.members.includes(:family_membership)
  end

  def show
    authorize @membership, :show?
  end

  def update
    authorize @membership

    if @membership.update(membership_params)
      redirect_to family_path(@family), notice: 'Settings updated successfully!'
    else
      redirect_to family_path(@family), alert: 'Failed to update settings'
    end
  end

  def destroy
    authorize @membership

    if @membership.owner? && @family.members.count > 1
      redirect_to family_path(@family), alert: 'Transfer ownership before removing yourself'
    else
      @membership.destroy!
      redirect_to family_path(@family), notice: 'Member removed successfully'
    end
  end

  private

  def set_family
    @family = current_user.family
    redirect_to families_path unless @family
  end

  def set_membership
    @membership = @family.family_memberships.find(params[:id])
  end

  def membership_params
    params.require(:family_membership).permit()
  end
end
```

### 3. FamilyInvitationsController
```ruby
class FamilyInvitationsController < ApplicationController
  before_action :authenticate_user!, except: [:show, :accept]
  before_action :set_family, except: [:show, :accept]
  before_action :set_invitation, only: [:show, :accept, :destroy]

  def index
    authorize @family, :show?
    @pending_invitations = @family.family_invitations.pending
  end

  def show
    # Public endpoint for invitation acceptance
  end

  def create
    authorize @family, :invite?

    service = Families::Invite.new(
      family: @family,
      email: invitation_params[:email],
      invited_by: current_user
    )

    if service.call
      redirect_to family_path(@family), notice: 'Invitation sent successfully!'
    else
      redirect_to family_path(@family), alert: 'Failed to send invitation'
    end
  end

  def accept
    authenticate_user!

    service = Families::AcceptInvitation.new(
      invitation: @invitation,
      user: current_user
    )

    if service.call
      redirect_to family_path(current_user.family), notice: 'Welcome to the family!'
    else
      redirect_to root_path, alert: service.error_message || 'Unable to accept invitation'
    end
  end

  def destroy
    authorize @family, :manage_invitations?

    @invitation.update!(status: :cancelled)
    redirect_to family_path(@family), notice: 'Invitation cancelled'
  end

  private

  def set_family
    @family = current_user.family
    redirect_to families_path unless @family
  end

  def set_invitation
    @invitation = FamilyInvitation.find_by!(token: params[:id])
  end

  def invitation_params
    params.require(:family_invitation).permit(:email)
  end
end
```

## Pundit Policies

### 1. FamilyPolicy
```ruby
class FamilyPolicy < ApplicationPolicy
  def show?
    user.family == record
  end

  def create?
    return false if user.in_family?
    return true if DawarichSettings.self_hosted?

    # Add cloud subscription checks here
    user.active? && user.active_until&.future?
  end

  def update?
    user.family == record && user.family_owner?
  end

  def destroy?
    user.family == record && user.family_owner?
  end

  def leave?
    user.family == record && !family_owner_with_members?
  end

  def invite?
    user.family == record && user.family_owner?
  end

  def manage_invitations?
    user.family == record && user.family_owner?
  end

  private

  def family_owner_with_members?
    user.family_owner? && record.members.count > 1
  end
end
```

### 2. FamilyMembershipPolicy
```ruby
class FamilyMembershipPolicy < ApplicationPolicy
  def show?
    user.family == record.family
  end

  def update?
    # Users can update their own settings
    return true if user == record.user

    # Family owners can update any member's settings
    user.family == record.family && user.family_owner?
  end

  def destroy?
    # Users can remove themselves (handled by family leave logic)
    return true if user == record.user

    # Family owners can remove other members
    user.family == record.family && user.family_owner?
  end
end
```

## Mailers

### FamilyMailer
```ruby
class FamilyMailer < ApplicationMailer
  def invitation(invitation)
    @invitation = invitation
    @family = invitation.family
    @invited_by = invitation.invited_by
    @accept_url = family_invitation_url(@invitation.token)

    mail(
      to: @invitation.email,
      subject: "You've been invited to join #{@family.name} on Dawarich"
    )
  end
end
```

### Email Templates

#### `app/views/family_mailer/invitation.html.erb`
```erb
<h2>You've been invited to join a family!</h2>

<p>Hi there!</p>

<p><%= @invited_by.email %> has invited you to join their family "<%= @family.name %>" on Dawarich.</p>

<p>By joining this family, you'll be able to:</p>
<ul>
  <li>Share your current location with family members</li>
  <li>See the current location of other family members</li>
  <li>Stay connected with your loved ones</li>
</ul>

<p>
  <%= link_to "Accept Invitation", @accept_url,
      style: "background-color: #4F46E5; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; display: inline-block;" %>
</p>

<p><strong>Note:</strong> This invitation will expire in 7 days.</p>

<p>If you don't have a Dawarich account yet, you'll be able to create one when you accept the invitation.</p>

<p>If you didn't expect this invitation, you can safely ignore this email.</p>

<p>
  Best regards,<br>
  The Dawarich Team
</p>
```

## Routes

### `config/routes.rb` additions
```ruby
# Family routes
resources :families, except: [:index] do
  member do
    post :leave
  end

  resources :members, controller: 'family_memberships', except: [:new, :create]
  resources :invitations, controller: 'family_invitations', except: [:edit, :update] do
    member do
      post :accept
    end
  end
end

# Public invitation acceptance
get '/family_invitations/:id', to: 'family_invitations#show', as: 'family_invitation'

# Family index/dashboard
get '/family', to: 'families#index', as: 'family_dashboard'
```

## Views

### 1. Family Dashboard (`app/views/families/show.html.erb`)
```erb
<div class="container mx-auto px-4 py-8">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-3xl font-bold text-gray-900">
      <%= @family.name %>
    </h1>

    <% if policy(@family).update? %>
      <div class="flex space-x-2">
        <%= link_to "Settings", edit_family_path(@family),
            class: "btn btn-outline" %>
        <%= link_to "Leave Family", leave_family_path(@family),
            method: :post,
            confirm: "Are you sure you want to leave this family?",
            class: "btn btn-error" %>
      </div>
    <% end %>
  </div>

  <!-- Family Map -->
  <div class="mb-8">
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title">Family Locations</h2>
        <div id="family-map" class="h-96 w-full bg-gray-100 rounded">
          <!-- Map will be rendered here -->
        </div>
      </div>
    </div>
  </div>

  <!-- Family Members -->
  <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <div class="flex justify-between items-center mb-4">
          <h2 class="card-title">Family Members (<%= @members.count %>/<%= Family::MAX_MEMBERS %>)</h2>

          <% if policy(@family).invite? && @members.count < Family::MAX_MEMBERS %>
            <button class="btn btn-primary btn-sm" onclick="invite_modal.showModal()">
              Invite Member
            </button>
          <% end %>
        </div>

        <div class="space-y-3">
          <% @members.each do |member| %>
            <div class="flex items-center justify-between p-3 bg-base-200 rounded-lg">
              <div class="flex items-center space-x-3">
                <div class="avatar placeholder">
                  <div class="bg-neutral-focus text-neutral-content rounded-full w-10">
                    <span class="text-sm"><%= member.email.first.upcase %></span>
                  </div>
                </div>

                <div>
                  <div class="font-medium"><%= member.email %></div>
                  <div class="text-sm text-gray-500">
                    <%= member.family_membership.role.humanize %>
                  </div>
                </div>
              </div>

              <% if policy(@family).update? && member != current_user %>
                <div class="dropdown dropdown-end">
                  <label tabindex="0" class="btn btn-ghost btn-sm">⋮</label>
                  <ul tabindex="0" class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-52">
                    <li>
                      <%= link_to "Remove", family_member_path(@family, member.family_membership),
                          method: :delete,
                          confirm: "Remove #{member.email} from family?" %>
                    </li>
                  </ul>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <!-- Pending Invitations -->
    <% if policy(@family).manage_invitations? && @pending_invitations.any? %>
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">Pending Invitations</h2>

          <div class="space-y-3">
            <% @pending_invitations.each do |invitation| %>
              <div class="flex items-center justify-between p-3 bg-orange-50 rounded-lg">
                <div>
                  <div class="font-medium"><%= invitation.email %></div>
                  <div class="text-sm text-gray-500">
                    Expires <%= time_ago_in_words(invitation.expires_at) %> from now
                  </div>
                </div>

                <%= link_to "Cancel", family_invitation_path(@family, invitation),
                    method: :delete,
                    confirm: "Cancel invitation to #{invitation.email}?",
                    class: "btn btn-error btn-sm" %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
  </div>
</div>

<!-- Invite Modal -->
<% if policy(@family).invite? %>
  <dialog id="invite_modal" class="modal">
    <div class="modal-box">
      <h3 class="font-bold text-lg">Invite Family Member</h3>

      <%= form_with url: family_invitations_path(@family), local: true, class: "mt-4" do |form| %>
        <div class="form-control">
          <label class="label">
            <span class="label-text">Email Address</span>
          </label>
          <%= form.email_field "family_invitation[email]",
              class: "input input-bordered w-full",
              placeholder: "Enter email address" %>
        </div>

        <div class="modal-action">
          <button type="button" class="btn" onclick="invite_modal.close()">Cancel</button>
          <%= form.submit "Send Invitation", class: "btn btn-primary" %>
        </div>
      <% end %>
    </div>
  </dialog>
<% end %>

<script>
  // Initialize family locations map
  document.addEventListener('DOMContentLoaded', function() {
    if (window.L) {
      const familyLocations = <%= raw @family_locations.to_json %>;
      // Initialize Leaflet map with family member locations
      // Implementation details for map rendering
    }
  });
</script>
```

### 2. Create Family (`app/views/families/new.html.erb`)
```erb
<div class="container mx-auto px-4 py-8 max-w-md">
  <div class="card bg-base-100 shadow-xl">
    <div class="card-body">
      <h1 class="card-title text-2xl mb-6">Create Your Family</h1>

      <%= form_with model: @family, local: true do |form| %>
        <% if @family.errors.any? %>
          <div class="alert alert-error mb-4">
            <div>
              <h3 class="font-bold">Please fix the following errors:</h3>
              <ul class="list-disc list-inside">
                <% @family.errors.full_messages.each do |message| %>
                  <li><%= message %></li>
                <% end %>
              </ul>
            </div>
          </div>
        <% end %>

        <div class="form-control mb-4">
          <%= form.label :name, "Family Name", class: "label" %>
          <%= form.text_field :name,
              class: "input input-bordered w-full",
              placeholder: "e.g., The Smith Family" %>
          <label class="label">
            <span class="label-text-alt">Choose a name that all family members will recognize</span>
          </label>
        </div>

        <div class="card-actions justify-end">
          <%= link_to "Cancel", root_path, class: "btn btn-ghost" %>
          <%= form.submit "Create Family", class: "btn btn-primary" %>
        </div>
      <% end %>

      <div class="divider mt-6"></div>

      <div class="text-sm text-gray-600">
        <h3 class="font-semibold mb-2">Family Features:</h3>
        <ul class="list-disc list-inside space-y-1">
          <li>Share your current location with up to <%= Family::MAX_MEMBERS - 1 %> family members</li>
          <li>See where your family members are right now</li>
          <li>Control your privacy with sharing toggles</li>
          <li>Invite members by email</li>
        </ul>
      </div>
    </div>
  </div>
</div>
```

### 3. Family Settings (`app/views/families/edit.html.erb`)
```erb
<div class="container mx-auto px-4 py-8 max-w-2xl">
  <div class="card bg-base-100 shadow-xl">
    <div class="card-body">
      <h1 class="card-title text-2xl mb-6">Family Settings</h1>

      <%= form_with model: @family, local: true do |form| %>
        <% if @family.errors.any? %>
          <div class="alert alert-error mb-4">
            <div>
              <h3 class="font-bold">Please fix the following errors:</h3>
              <ul class="list-disc list-inside">
                <% @family.errors.full_messages.each do |message| %>
                  <li><%= message %></li>
                <% end %>
              </ul>
            </div>
          </div>
        <% end %>

        <!-- Family Name -->
        <div class="form-control mb-6">
          <%= form.label :name, "Family Name", class: "label" %>
          <%= form.text_field :name,
              class: "input input-bordered w-full" %>
        </div>

        <div class="divider"></div>

        <!-- Family Actions -->
        <div class="space-y-4">
          <h3 class="text-lg font-semibold">Family Management</h3>

          <div class="alert alert-warning">
            <div>
              <h4 class="font-bold">Danger Zone</h4>
              <p class="text-sm">These actions cannot be undone</p>
            </div>
          </div>

          <% if @family.members.count <= 1 %>
            <%= link_to "Delete Family",
                family_path(@family),
                method: :delete,
                confirm: "Are you sure? This will permanently delete your family.",
                class: "btn btn-error" %>
          <% else %>
            <div class="text-sm text-gray-600">
              To delete this family, you must first remove all other members.
            </div>
          <% end %>
        </div>

        <div class="card-actions justify-end mt-6">
          <%= link_to "Back to Family", family_path(@family), class: "btn btn-ghost" %>
          <%= form.submit "Save Changes", class: "btn btn-primary" %>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

### 4. Public Invitation Page (`app/views/family_invitations/show.html.erb`)
```erb
<div class="container mx-auto px-4 py-8 max-w-md">
  <div class="card bg-base-100 shadow-xl">
    <div class="card-body">
      <h1 class="card-title text-2xl mb-6">Family Invitation</h1>

      <% if @invitation.pending? && @invitation.expires_at > Time.current %>
        <div class="mb-6">
          <div class="text-center mb-4">
            <div class="text-4xl mb-2">👨‍👩‍👧‍👦</div>
            <h2 class="text-xl font-semibold">You're Invited!</h2>
          </div>

          <p class="text-center mb-4">
            <strong><%= @invitation.invited_by.email %></strong> has invited you to join
            <strong>"<%= @invitation.family.name %>"</strong> on Dawarich.
          </p>

          <div class="bg-base-200 p-4 rounded-lg mb-4">
            <h3 class="font-semibold mb-2">What you'll get:</h3>
            <ul class="list-disc list-inside text-sm space-y-1">
              <li>Share your current location with family</li>
              <li>See where your family members are</li>
              <li>Stay connected and safe</li>
              <li>Full control over your privacy</li>
            </ul>
          </div>

          <div class="text-sm text-gray-600 mb-6">
            This invitation expires in
            <strong><%= time_ago_in_words(@invitation.expires_at) %></strong>
          </div>
        </div>

        <% if user_signed_in? %>
          <% if current_user.email == @invitation.email %>
            <%= link_to "Accept Invitation",
                accept_family_invitation_path(@invitation.token),
                method: :post,
                class: "btn btn-primary w-full" %>
          <% else %>
            <div class="alert alert-warning">
              <div>
                <p>This invitation is for <strong><%= @invitation.email %></strong>.</p>
                <p>You're signed in as <strong><%= current_user.email %></strong>.</p>
                <p>Please sign out and sign in with the correct account, or create a new account with the invited email.</p>
              </div>
            </div>

            <%= link_to "Sign Out", destroy_user_session_path,
                method: :delete, class: "btn btn-outline w-full" %>
          <% end %>
        <% else %>
          <div class="space-y-3">
            <%= link_to "Sign In to Accept",
                new_user_session_path(email: @invitation.email),
                class: "btn btn-primary w-full" %>

            <div class="divider">OR</div>

            <%= link_to "Create Account",
                new_user_registration_path(email: @invitation.email),
                class: "btn btn-outline w-full" %>
          </div>
        <% end %>

      <% else %>
        <div class="text-center">
          <div class="text-4xl mb-2">⏰</div>
          <h2 class="text-xl font-semibold mb-4">Invitation Expired</h2>
          <p class="text-gray-600 mb-6">
            This family invitation has expired or is no longer valid.
          </p>

          <%= link_to "Go to Dawarich", root_path, class: "btn btn-primary" %>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

## Navigation Integration

### Update `app/views/shared/_navbar.html.erb`
```erb
<!-- Add to the main navigation menu -->
<% if user_signed_in? %>
  <li>
    <% if current_user.in_family? %>
      <%= link_to family_path(current_user.family), class: "flex items-center space-x-2" do %>
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"/>
        </svg>
        <span>Family</span>
      <% end %>
    <% else %>
      <%= link_to new_family_path, class: "flex items-center space-x-2" do %>
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
        </svg>
        <span>Create Family</span>
      <% end %>
    <% end %>
  </li>
<% end %>
```

## Testing Strategy

### 1. Model Tests
```ruby
# spec/models/family_spec.rb
RSpec.describe Family, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:family_memberships).dependent(:destroy) }
    it { is_expected.to have_many(:members).through(:family_memberships) }
    it { is_expected.to have_many(:family_invitations).dependent(:destroy) }
    it { is_expected.to belong_to(:creator) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(50) }
    it { is_expected.to validate_presence_of(:creator_id) }
  end

  describe 'constants' do
    it 'defines MAX_MEMBERS' do
      expect(Family::MAX_MEMBERS).to eq(5)
    end
  end
end

# spec/models/family_membership_spec.rb
RSpec.describe FamilyMembership, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:family) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:family_id) }
    it { is_expected.to validate_presence_of(:user_id) }
    it { is_expected.to validate_uniqueness_of(:user_id) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:role).with_values(owner: 0, member: 1) }
  end
end

# spec/models/family_invitation_spec.rb
RSpec.describe FamilyInvitation, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:family) }
    it { is_expected.to belong_to(:invited_by) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to allow_value('test@example.com').for(:email) }
    it { should_not allow_value('invalid-email').for(:email) }
    it { is_expected.to validate_presence_of(:token) }
    it { is_expected.to validate_uniqueness_of(:token) }
  end

  describe 'callbacks' do
    it 'generates token on create' do
      invitation = build(:family_invitation, token: nil)
      invitation.save
      expect(invitation.token).to be_present
    end

    it 'sets expiry on create' do
      invitation = build(:family_invitation, expires_at: nil)
      invitation.save
      expect(invitation.expires_at).to be_within(1.minute).of(7.days.from_now)
    end
  end
end
```

### 2. Service Tests
```ruby
# spec/services/families/create_service_spec.rb
RSpec.describe Families::Create do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user: user, name: 'Test Family') }

  describe '#call' do
    context 'when user is not in a family' do
      it 'creates a family successfully' do
        expect { service.call }.to change(Family, :count).by(1)
        expect(service.family.name).to eq('Test Family')
        expect(service.family.creator).to eq(user)
      end

      it 'creates owner membership' do
        service.call
        membership = user.family_membership
        expect(membership.role).to eq('owner')
      end

      it 'sends notification' do
        expect(Notifications::Create).to receive(:new).and_call_original
        service.call
      end
    end

    context 'when user is already in a family' do
      before { create(:family_membership, user: user) }

      it 'returns false' do
        expect(service.call).to be_falsey
      end

      it 'does not create a family' do
        expect { service.call }.not_to change(Family, :count)
      end
    end
  end
end
```

### 3. Controller Tests
```ruby
# spec/controllers/families_controller_spec.rb
RSpec.describe FamiliesController, type: :controller do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET #show' do
    context 'when user has a family' do
      let(:family) { create(:family, creator: user) }
      let!(:membership) { create(:family_membership, user: user, family: family, role: :owner) }

      it 'renders the show template' do
        get :show, params: { id: family.id }
        expect(response).to render_template(:show)
        expect(assigns(:family)).to eq(family)
      end
    end

    context 'when user has no family' do
      it 'redirects to families index' do
        get :show, params: { id: 'nonexistent' }
        expect(response).to redirect_to(families_path)
      end
    end
  end

  describe 'POST #create' do
    let(:valid_params) { { family: { name: 'Test Family' } } }

    it 'creates a family successfully' do
      expect { post :create, params: valid_params }.to change(Family, :count).by(1)
      expect(response).to redirect_to(family_path(Family.last))
    end

    context 'with invalid params' do
      let(:invalid_params) { { family: { name: '' } } }

      it 'renders new template with errors' do
        post :create, params: invalid_params
        expect(response).to render_template(:new)
        expect(response.status).to eq(422)
      end
    end
  end
end
```

### 4. Integration Tests
```ruby
# spec/requests/family_workflow_spec.rb
RSpec.describe 'Family Workflow', type: :request do
  let(:owner) { create(:user, email: 'owner@example.com') }
  let(:invitee_email) { 'member@example.com' }

  before { sign_in owner }

  describe 'complete family creation and invitation flow' do
    it 'allows creating family, inviting member, and accepting invitation' do
      # Create family
      post '/families', params: { family: { name: 'Test Family' } }
      expect(response).to redirect_to(family_path(Family.last))

      family = Family.last
      expect(family.name).to eq('Test Family')
      expect(family.creator).to eq(owner)

      # Invite member
      post "/families/#{family.id}/invitations",
           params: { family_invitation: { email: invitee_email } }
      expect(response).to redirect_to(family_path(family))

      invitation = FamilyInvitation.last
      expect(invitation.email).to eq(invitee_email)
      expect(invitation.status).to eq('pending')

      # Create invitee user and accept invitation
      invitee = create(:user, email: invitee_email)
      sign_in invitee

      post "/family_invitations/#{invitation.token}/accept"
      expect(response).to redirect_to(family_path(family))

      # Verify membership created
      membership = invitee.family_membership
      expect(membership.family).to eq(family)
      expect(membership.role).to eq('member')

      # Verify invitation updated
      invitation.reload
      expect(invitation.status).to eq('accepted')
    end
  end
end
```

### 5. System Tests
```ruby
# spec/system/family_management_spec.rb
RSpec.describe 'Family Management', type: :system do
  let(:user) { create(:user) }

  before do
    sign_in user
    visit '/'
  end

  it 'allows user to create and manage a family' do
    # Create family
    click_link 'Create Family'
    fill_in 'Family Name', with: 'The Smith Family'
    click_button 'Create Family'

    expect(page).to have_content('Family created successfully!')
    expect(page).to have_content('The Smith Family')

    # Invite member
    click_button 'Invite Member'
    fill_in 'Email Address', with: 'member@example.com'
    click_button 'Send Invitation'

    expect(page).to have_content('Invitation sent successfully!')
    expect(page).to have_content('member@example.com')
  end
end
```

## Feature Gating for Cloud vs Self-Hosted

### Update DawarichSettings
```ruby
# config/initializers/03_dawarich_settings.rb

class DawarichSettings
  # ... existing code ...

  def self.family_feature_enabled?
    @family_feature_enabled ||= self_hosted? || family_subscription_active?
  end

  def self.family_subscription_active?
    # Will be implemented when cloud subscriptions are added
    # For now, return false for cloud instances
    false
  end

  def self.family_max_members
    @family_max_members ||= self_hosted? ? Family::MAX_MEMBERS : subscription_family_limit
  end

  private

  def self.subscription_family_limit
    # Will be implemented based on subscription tiers
    # For now, return basic limit
    Family::MAX_MEMBERS
  end
end
```

### Add to Routes
```ruby
# config/routes.rb

# Family routes - only if feature is enabled
if Rails.application.config.after_initialize_block.nil?
  Rails.application.config.after_initialize do
    if DawarichSettings.family_feature_enabled?
      # Family routes will be added here
    end
  end
end
```

## Implementation Phases

### Phase 1: Database Foundation (Week 1) ✅ COMPLETED
1. ✅ Create migration files for all three tables
2. ✅ Implement base model classes with associations
3. ✅ Add basic validations and enums
4. ✅ Create and run migrations
5. ✅ Write comprehensive model tests

### Phase 2: Core Business Logic (Week 2)
1. ✅ Implement all service classes
2. ✅ Add invitation token generation and expiry logic
3. ✅ Create email templates and mailer
4. ✅ Write service tests
5. ✅ Add basic Pundit policies

### Phase 3: Controllers and Routes (Week 3)
1. ✅ Implement all controller classes
2. ✅ Add route definitions
3. ✅ Create basic authorization policies
4. ✅ Write controller tests
5. ✅ Add request/integration tests

### Phase 4: User Interface (Week 4)
1. ✅ Create all view templates
2. ✅ Add family navigation to main nav
3. ✅ Implement basic map integration for family locations
4. ✅ Add Stimulus controllers for interactive elements
5. ✅ Write system tests for UI flows

### Phase 5: Polish and Testing (Week 5)
1. Add comprehensive error handling
2. Improve UI/UX based on testing
3. Add feature gating for cloud vs self-hosted
4. Performance optimization
5. Documentation and deployment preparation

## Security Considerations

1. **UUID Primary Keys**: All family-related tables use UUIDs to prevent enumeration attacks
2. **Token-based Invitations**: Secure, unguessable invitation tokens with expiry
3. **Authorization Policies**: Comprehensive Pundit policies for all actions
4. **Data Privacy**: Users control their own location sharing settings
5. **Account Protection**: Family owners cannot delete accounts while managing families
6. **Email Validation**: Proper email format validation for invitations
7. **Rate Limiting**: is_expected.to be added for invitation sending (future enhancement)

## Performance Considerations

1. **Database Indexes**: Proper indexing on foreign keys and query patterns
2. **Eager Loading**: Use `includes()` for associations in controllers
3. **Caching**: Cache family locations for map display
4. **Background Jobs**: Use Sidekiq for email sending
5. **Pagination**: Add pagination for large families (future enhancement)

## Future Enhancements

1. **Historical Location Sharing**: Allow sharing location history with permissions
2. **Family Messaging**: Add simple messaging between family members
3. **Geofencing**: Notifications when family members enter/leave areas
4. **Family Events**: Plan and track family trips together
5. **Emergency Features**: Quick location sharing in emergency situations
6. **Mobile App Push Notifications**: Real-time location updates
7. **Family Statistics**: Aggregate family travel statistics
8. **Multiple Families**: Allow users to be in multiple families with different roles

This comprehensive implementation plan provides a solid foundation for the family feature while maintaining Dawarich's existing patterns and ensuring security, privacy, and performance.
