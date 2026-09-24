# frozen_string_literal: true

# A user whose Membership survives but whose Entitlement has gone. The payload
# carries only what is needed to explain the state — the family's name and
# whether this user is the Family owner, so the client can offer renewal to the
# one person who can act on it. Member identities and locations are deliberately
# absent: a lapsed user has no entitlement to them.
class Api::LapsedFamilySerializer
  def initialize(user)
    @user = user
  end

  def call
    {
      lapsed: true,
      family: { name: user.family&.name },
      me: {
        user_id: user.id,
        owner: user.family_owner?
      }
    }
  end

  private

  attr_reader :user
end
