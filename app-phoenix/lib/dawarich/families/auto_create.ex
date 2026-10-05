defmodule Dawarich.Families.AutoCreate do
  @moduledoc false
  require Logger

  alias Dawarich.{I18n, Notifications}
  alias Dawarich.Families.{AutoCreateSharing, MemberSync}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Mail.ExploreFeatures
  alias DawarichWeb.LayoutAssigns

  def run(repo, user_id, opts \\ []) do
    if LayoutAssigns.self_hosted?() do
      false
    else
      {:ok, result} = repo.transaction(fn -> create(repo, user_id, opts) end)
      result
    end
  end

  defp create(repo, user_id, opts) do
    Ownership.lock(repo, "command:mail.family_lapse")

    case repo.query!(
           "SELECT plan, settings FROM users WHERE id = $1 AND deleted_at IS NULL FOR UPDATE",
           [user_id],
           log: false
         ).rows do
      [[2, settings]] ->
        hook(opts, :locked)

        [[existing]] =
          repo.query!(
            "SELECT EXISTS (SELECT 1 FROM family_memberships WHERE user_id = $1 UNION ALL SELECT 1 FROM families WHERE creator_id = $1)",
            [user_id],
            log: false
          ).rows

        if existing, do: false, else: finish(repo, user_id, settings, opts)

      _ ->
        false
    end
  end

  defp finish(repo, user_id, settings, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    locale = ExploreFeatures.locale(settings, "en")
    {:ok, name} = I18n.t(locale, "services.families.auto_create.default_name")

    case create_membership(repo, user_id, name, now) do
      false -> false
      family -> complete(repo, user_id, family, settings, locale, name, now, opts)
    end
  end

  defp create_membership(repo, user_id, name, now) do
    repo.query!("SAVEPOINT family_auto_create", [], log: false)

    try do
      [[family]] =
        repo.query!(
          "INSERT INTO families (name, creator_id, created_at, updated_at) VALUES ($1, $2, $3, $3) RETURNING id",
          [String.trim(name), user_id, DateTime.to_naive(now)],
          log: false
        ).rows

      repo.query!(
        "INSERT INTO family_memberships (family_id, user_id, role, created_at, updated_at) VALUES ($1, $2, 0, $3, $3)",
        [family, user_id, DateTime.to_naive(now)],
        log: false
      )

      repo.query!("RELEASE SAVEPOINT family_auto_create", [], log: false)
      family
    rescue
      error ->
        repo.query!("ROLLBACK TO SAVEPOINT family_auto_create", [], log: false)
        repo.query!("RELEASE SAVEPOINT family_auto_create", [], log: false)
        Logger.warning("Family creation failed: #{inspect(error.__struct__)}")
        false
    end
  end

  defp complete(repo, user_id, family, settings, locale, name, now, opts) do
    hook(opts, :joined)

    updated =
      AutoCreateSharing.enable(
        repo,
        settings,
        now,
        Keyword.get(opts, :time_zone, System.get_env("TIME_ZONE", "Europe/Berlin"))
      )

    repo.query!(
      "UPDATE users SET settings = $2, updated_at = $3 WHERE id = $1",
      [user_id, updated, DateTime.to_naive(now)],
      log: false
    )

    hook(opts, :shared)
    true = MemberSync.run(repo, family, Keyword.merge(opts, now: now, locale: locale))
    notice(repo, user_id, locale, name, now)
    true
  end

  defp notice(repo, user_id, locale, name, now) do
    repo.query!("SAVEPOINT family_auto_notice", [], log: false)

    try do
      {:ok, title} = I18n.t(locale, "services.families.auto_create.notification_title")

      {:ok, content} =
        I18n.t(locale, "services.families.auto_create.notification_content", %{
          "name" => name,
          "seats" => 4
        })

      Notifications.create!(repo, user_id, :info, title, content, DateTime.to_naive(now))
      repo.query!("RELEASE SAVEPOINT family_auto_notice", [], log: false)
    rescue
      error ->
        repo.query!("ROLLBACK TO SAVEPOINT family_auto_notice", [], log: false)
        repo.query!("RELEASE SAVEPOINT family_auto_notice", [], log: false)
        Logger.warning("Family auto-creation notice failed: #{inspect(error.__struct__)}")
    end
  end

  defp hook(opts, stage), do: Keyword.get(opts, :hook, fn _ -> :ok end).(stage)
end
