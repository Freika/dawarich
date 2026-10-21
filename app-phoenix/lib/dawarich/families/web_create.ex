defmodule Dawarich.Families.WebCreate do
  @moduledoc false
  alias Dawarich.{Notifications, I18n}
  alias Dawarich.Mail.ExploreFeatures

  def run(repo, user, attrs, ctx, opts \\ []) do
    cond do
      family(repo, user.id) != nil ->
        {:error, :not_authorized}

      not ctx.self_hosted and user.plan != 2 ->
        {:error, :not_authorized}

      true ->
        name =
          if is_binary(attrs["name"]),
            do: String.replace(attrs["name"], ~r/\A[\0\t\n\v\f\r ]+|[\0\t\n\v\f\r ]+\z/, ""),
            else: nil

        case validate(name, ctx.locale) do
          [] -> create(repo, user, name, ctx, opts)
          errors -> {:invalid, errors, name}
        end
    end
  end

  def family(repo, user_id) do
    case repo.query!(
           "SELECT f.id,f.name,f.creator_id,m.role,f.access_until,o.plan,o.active_until " <>
             "FROM family_memberships m JOIN families f ON f.id=m.family_id " <>
             "LEFT JOIN users o ON o.id=f.creator_id AND o.deleted_at IS NULL WHERE m.user_id=$1",
           [user_id],
           log: false
         ).rows do
      [[id, name, creator, role, access, plan, until]] ->
        %{
          id: id,
          name: name,
          creator_id: creator,
          role: role,
          access_until: access,
          owner_plan: plan,
          owner_until: until
        }

      [] ->
        nil
    end
  end

  def refresh_access(_repo, _family, access, _plan, _until, true), do: access
  def refresh_access(_repo, _family, access, _plan, nil, false), do: access

  def refresh_access(repo, family, access, plan, until, false) do
    effective =
      cond do
        plan == 2 -> until
        is_nil(access) -> nil
        NaiveDateTime.compare(access, until) == :gt -> until
        true -> access
      end

    if effective != access,
      do:
        repo.query!("UPDATE families SET access_until=$1 WHERE id=$2", [effective, family],
          log: false
        )

    effective
  end

  def validate(name, locale) do
    cond do
      is_nil(name) or String.trim(name) == "" ->
        [
          Dawarich.WebValidation.message(
            locale,
            "family",
            "name",
            "services.families.create.family_name_is_required"
          )
        ]

      length(String.codepoints(name)) > 50 ->
        [
          Dawarich.WebValidation.message(
            locale,
            "family",
            "name",
            "services.families.create.family_name_must_be_50_characters_or_less"
          )
        ]

      true ->
        []
    end
  end

  defp create(repo, user, name, ctx, opts) do
    repo.transaction(fn ->
      repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [user.id], log: false)
      if family(repo, user.id), do: repo.rollback(:not_authorized)
      at = DateTime.to_naive(ctx.now)

      [[id]] =
        repo.query!(
          "INSERT INTO families(name,creator_id,created_at,updated_at) VALUES($1,$2,$3,$3) RETURNING id",
          [name, user.id, at],
          log: false
        ).rows

      repo.query!(
        "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,0,$3,$3)",
        [id, user.id, at],
        log: false
      )

      locale = ExploreFeatures.locale(Dawarich.UserSettings.get(user), "en")

      notify(fn ->
        Keyword.get(opts, :notify, fn ->
          Notifications.create!(
            repo,
            user.id,
            :info,
            t(locale, "family_created"),
            t(locale, "you_ve_successfully_created_the_family_name", %{"name" => name}),
            at
          )
        end).()
      end)

      id
    end)
  end

  def notify(callback) do
    callback.()
  rescue
    _error -> :ok
  end

  defp t(locale, key, params \\ %{}) do
    {:ok, text} = I18n.t(locale, "services.families.create." <> key, params)
    text
  end
end
