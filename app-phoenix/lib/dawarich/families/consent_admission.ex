defmodule Dawarich.Families.ConsentAdmission do
  @moduledoc false
  alias Dawarich.{Accounts.User, FamilyPageAccess, ReleaseMigration}
  alias Dawarich.Families.WebCreate

  def allowed?(repo, user_id, family_id, now) do
    user = repo.get(User, user_id, log: false)
    family = WebCreate.family(repo, user_id)

    (user && is_nil(user.deleted_at) && family && family.id == family_id &&
       FamilyPageAccess.available?(user, family, ReleaseMigration.self_hosted?(), now)) || false
  end
end
