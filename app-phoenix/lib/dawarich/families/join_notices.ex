defmodule Dawarich.Families.JoinNotices do
  @moduledoc false
  alias Dawarich.{I18n, Notifications}

  def create!(repo, user, creator, name, at) do
    locale = Dawarich.Mail.ExploreFeatures.locale(Dawarich.UserSettings.get(user), "en")

    Notifications.create!(
      repo,
      user.id,
      :info,
      t(locale, "welcome_to_family"),
      t(locale, "you_ve_joined_the_family_name", %{"name" => name}),
      at
    )

    [[settings]] =
      repo.query!("SELECT settings FROM users WHERE id=$1", [creator], log: false).rows

    locale = Dawarich.Mail.ExploreFeatures.locale(settings, "en")

    Notifications.create!(
      repo,
      creator,
      :info,
      t(locale, "new_family_member"),
      t(locale, "email_has_joined_your_family", %{"email" => user.email}),
      at
    )
  end

  defp t(locale, key, args \\ %{}) do
    {:ok, message} =
      I18n.t(locale, "services.families.accept_invitation." <> key, args)

    message
  end
end
