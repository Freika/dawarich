defmodule Dawarich.Families.WebMemberships do
  @moduledoc false
  alias Dawarich.{Notifications, I18n}
  alias Dawarich.Families.{WebCreate, Sharing}
  alias Dawarich.Mail.ExploreFeatures

  def run(repo, user, id, ctx) do
    case WebCreate.family(repo, user.id) do
      nil -> {:error, :not_in_family}
      family -> remove(repo, user, family, id, ctx)
    end
  end

  defp remove(repo, user, family, id, ctx) do
    case repo.query!(
           "SELECT m.user_id,m.role,u.email,u.settings,u.subscription_source FROM family_memberships m " <>
             "JOIN users u ON u.id=m.user_id WHERE m.id=$1 AND m.family_id=$2",
           [id, family.id],
           log: false
         ).rows do
      [] ->
        {:error, :not_found}

      [[target, role, email, settings, source]] ->
        cond do
          user.id != target and family.role != 0 ->
            {:error, :not_authorized}

          role == 0 ->
            {:refused, "family_owners_cannot_remove_their_own_membership_to_leave_the"}

          true ->
            repo.transaction(fn ->
              delete!(repo, id, target, role, settings, source, ctx)
              notify(repo, user, target, email, settings, family, ctx)
              %{self?: user.id == target, email: email}
            end)
        end
    end
  end

  def delete!(repo, id, user_id, role, settings, source, ctx) do
    repo.query!("DELETE FROM family_memberships WHERE id=$1", [id], log: false)
    at = DateTime.to_naive(ctx.now)

    if not ctx.self_hosted and role != 0 and source == 0 do
      repo.query!(
        "UPDATE users SET plan=0,status=0,active_until=NULL,updated_at=$1 WHERE id=$2",
        [at, user_id],
        log: false
      )
    end

    if Sharing.enabled?(settings, ctx.now) do
      settings =
        Map.put(
          settings,
          "family",
          Map.put(settings["family"] || %{}, "location_sharing", %{"enabled" => false})
        )

      repo.query!(
        "UPDATE users SET settings=$1,updated_at=$2 WHERE id=$3",
        [settings, at, user_id],
        log: false
      )
    end

    repo.query!(
      "UPDATE family_location_requests SET status=3,updated_at=$1 " <>
        "WHERE status=0 AND (requester_id=$2 OR target_user_id=$2)",
      [at, user_id],
      log: false
    )

    :ok
  end

  defp notify(repo, actor, target, email, settings, family, ctx) do
    self = actor.id == target
    bindings = %{"email" => actor.email, "family_name" => family.name}
    locale = ExploreFeatures.locale(settings, "en")
    title = if self, do: "left_family", else: "removed_from_family"

    content =
      if self,
        do: "you_ve_left_the_family_family_name",
        else: "you_have_been_removed_from_the_family_family_name_by"

    at = DateTime.to_naive(ctx.now)
    Notifications.create!(repo, target, :info, t(locale, title), t(locale, content, bindings), at)
    owner_id = if self, do: family.creator_id, else: actor.id

    [[owner_settings]] =
      repo.query!("SELECT settings FROM users WHERE id=$1", [owner_id], log: false).rows

    locale = ExploreFeatures.locale(owner_settings, "en")
    title = if self, do: "family_member_left", else: "member_removed"

    content =
      if self,
        do: "email_has_left_the_family_family_name",
        else: "email_has_been_removed_from_the_family_family_name"

    Notifications.create!(
      repo,
      owner_id,
      :info,
      t(locale, title),
      t(locale, content, %{"email" => email, "family_name" => family.name}),
      at
    )
  end

  defp t(locale, key, bindings \\ %{}) do
    {:ok, message} = I18n.t(locale, "services.families.memberships.destroy." <> key, bindings)
    message
  end
end
