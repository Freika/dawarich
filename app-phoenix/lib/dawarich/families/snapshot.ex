defmodule Dawarich.Families.Snapshot do
  @moduledoc false
  alias Dawarich.{FamilyPageAccess, Repo}
  alias Dawarich.Families.{Sharing, WebCreate}

  def read(user, opts, reader) do
    with :ok <- zone_ready(user, Keyword.get(opts, :repo, Repo)), do: snapshot(user, opts, reader)
  end

  defp zone_ready(user, repo) do
    setting = Map.get(user, :timezone) || System.get_env("TIME_ZONE", "UTC")
    zone = if is_binary(setting), do: Dawarich.TimeZoneName.to_iana(setting), else: ""

    if zone =~ ~r{\A[A-Z][A-Za-z_\-]*(?:/[A-Za-z0-9_+\-]+)+\z} do
      [[known]] =
        repo.query!("SELECT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=$1)", [zone],
          log: false
        ).rows

      if known, do: :ok, else: {:replay, "PostgreSQL does not know time zone #{zone}"}
    else
      :ok
    end
  end

  defp snapshot(user, opts, reader) do
    started = System.monotonic_time(:microsecond)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    hosted = Keyword.get_lazy(opts, :self_hosted, &Dawarich.ReleaseMigration.self_hosted?/0)

    clock =
      Keyword.get(opts, :clock, fn ->
        DateTime.add(now, System.monotonic_time(:microsecond) - started, :microsecond)
      end)

    repo = Keyword.get(opts, :repo, Repo)

    case repo.transaction(fn ->
           version = epoch(repo, user.id, clock.(), hosted)
           result = reader.()
           result = Keyword.get(opts, :after_read, &Function.identity/1).(result)

           if valid?(repo, user.id, version, clock.(), hosted),
             do: result,
             else: {:error, :grant_changed}
         end) do
      {:ok, result} -> result
      {:error, _} -> {:error, :unavailable}
    end
  end

  defp valid?(repo, id, version, now, hosted) do
    version == epoch(repo, id, now, hosted)
  end

  def actor(repo, id) do
    result =
      repo.query!("SELECT * FROM users WHERE id=$1 AND deleted_at IS NULL", [id], log: false)

    case result.rows do
      [row] ->
        user = Repo.load(Dawarich.Accounts.User, {result.columns, row})
        if Dawarich.Accounts.unlocked?(user, DateTime.utc_now()), do: user

      [] ->
        nil
    end
  end

  defp epoch(repo, id, now, hosted) do
    family = WebCreate.family(repo, id)
    actor = actor(repo, id)
    family_id = if family, do: family.id

    rows =
      repo.query!(
        "SELECT m.id,m.user_id,m.role,u.settings,u.deleted_at,f.id,f.name,f.access_until,o.plan,o.active_until,o.deleted_at,u.plan,u.active_until " <>
          "FROM family_memberships m JOIN users u ON u.id=m.user_id JOIN families f ON f.id=m.family_id " <>
          "LEFT JOIN users o ON o.id=f.creator_id WHERE m.family_id=$1 ORDER BY m.id",
        [family_id],
        log: false
      ).rows

    consent =
      for [_, member, _, settings, nil | _] <- rows, do: {member, Sharing.enabled?(settings, now)}

    invitations =
      repo.query!(
        "SELECT id,status,expires_at > $2,email,invited_by_id FROM family_invitations WHERE family_id=$1 ORDER BY id",
        [family_id, DateTime.to_naive(now)],
        log: false
      ).rows

    requests =
      repo.query!(
        "SELECT id,status,expires_at > $2,target_user_id,requester_id FROM family_location_requests WHERE family_id=$1 ORDER BY id",
        [family_id, DateTime.to_naive(now)],
        log: false
      ).rows

    available = actor && FamilyPageAccess.available?(actor, family, hosted, now)

    :crypto.hash(
      :sha256,
      :erlang.term_to_binary({actor, rows, consent, invitations, requests, available})
    )
  end
end
