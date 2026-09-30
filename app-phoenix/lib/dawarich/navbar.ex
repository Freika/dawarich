defmodule Dawarich.Navbar do
  @moduledoc false

  import Ecto.Query

  alias Dawarich.{AppVersion, Entitlements, Repo, Supporters, UserTimeZone}
  alias Dawarich.Accounts.User

  @kinds %{0 => "info", 1 => "warning", 2 => "error"}
  @trial 2
  @pending_payment 3
  @family_plan 2
  @consents %{"declined" => 0, "granted" => 1}

  def load(nil, opts), do: %{version: version(nil, opts[:self_hosted], opts[:now])}

  def load(%User{} = user, opts) do
    now = Keyword.fetch!(opts, :now)
    self_hosted = Keyword.fetch!(opts, :self_hosted)
    running_version = AppVersion.current()

    %{
      unread: unread(user.id),
      family: family(user, now, self_hosted),
      subscription: subscription(user, now, self_hosted),
      version: version(user, self_hosted, now, running_version),
      onboarding: onboarding?(user.settings),
      supporter: Supporters.badge?(user.settings, now, running_version)
    }
  end

  def unread(user_id) do
    rows =
      from(n in "notifications",
        where: n.user_id == ^user_id and is_nil(n.read_at),
        order_by: [desc: n.created_at],
        limit: 10,
        select: {n.id, n.title, n.kind, over(count(n.id))}
      )
      |> Repo.all()

    %{
      count: rows |> List.first({nil, nil, nil, 0}) |> elem(3),
      items: for({id, title, kind, _} <- rows, do: %{id: id, title: title, kind: @kinds[kind]})
    }
  end

  def put_changelog_consent(%User{} = user, decision) do
    value = Map.fetch!(@consents, decision)

    from(u in "users", where: u.id == ^user.id)
    |> Repo.update_all(set: [changelog_consent: value, updated_at: NaiveDateTime.utc_now()])

    %{user | changelog_consent: value}
  end

  defp family(user, now, self_hosted) do
    {member, access_until, owner_plan, owner_until} =
      from(u in "users",
        left_join: m in "family_memberships",
        on: m.user_id == u.id,
        left_join: f in "families",
        on: f.id == m.family_id,
        left_join: o in "users",
        on: o.id == f.creator_id and is_nil(o.deleted_at),
        where: u.id == ^user.id,
        select: {not is_nil(m.id), f.access_until, o.plan, o.active_until}
      )
      |> Repo.one() || {false, nil, nil, nil}

    inherited = member and Entitlements.inherited?(access_until, owner_plan, owner_until, now)

    available =
      self_hosted or inherited or
        (user.plan == @family_plan and Entitlements.future?(user.active_until, now))

    %{member: member, available: available, sharing: member and sharing?(user.settings, now)}
  end

  defp sharing?(%{"family" => %{"location_sharing" => %{"enabled" => true} = sharing}}, now) do
    case sharing["expires_at"] do
      nil -> true
      value when is_binary(value) -> String.trim(value) == "" or expires_later?(value, now)
      _ -> false
    end
  end

  defp sharing?(_settings, _now), do: false

  defp expires_later?(value, now) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> DateTime.compare(at, now) == :gt
      _ -> false
    end
  end

  defp subscription(_user, _now, true), do: nil

  defp subscription(user, now, false) do
    active = Entitlements.future?(user.active_until, now)
    trial = user.status == @trial

    if (trial or not active) and not (trial and active and user.subscription_source != 0) do
      expired = is_nil(user.active_until) or DateTime.compare(user.active_until, now) == :lt

      %{
        pending: user.status == @pending_payment,
        active_until: user.active_until,
        expired: expired,
        days:
          user.active_until && not expired && days_between(user.active_until, now, user.settings)
      }
    end
  end

  defp days_between(until, now, settings) do
    %{rows: [[days]]} =
      UserTimeZone.query!(
        """
        SELECT ($1::timestamptz AT TIME ZONE z.name)::date - ($2::timestamptz AT TIME ZONE z.name)::date
        FROM z
        """,
        [until, now],
        settings
      )

    days
  end

  def changelog_host do
    host = System.get_env("CHIBICHANGE_WIDGET_HOST", "https://my.chibichange.com")
    URI.parse(host).host || host
  end

  defp version(user, self_hosted, now), do: version(user, self_hosted, now, AppVersion.current())

  defp version(user, self_hosted, now, running_version) do
    host = System.get_env("CHIBICHANGE_WIDGET_HOST", "https://my.chibichange.com")
    state = changelog_state(user, self_hosted)

    %{
      number: running_version,
      state: state,
      update: state != :widget and AppVersion.update_available?(now, running_version),
      widget_src: host <> "/w/v1/loader.js",
      widget_host: changelog_host(),
      slug:
        if(self_hosted,
          do: System.get_env("CHIBICHANGE_SLUG", "dawarich"),
          else: System.get_env("CHIBICHANGE_CLOUD_SLUG", "dawarich-cloud")
        )
    }
  end

  defp changelog_state(nil, _self_hosted), do: :badge

  defp changelog_state(%User{changelog_consent: 0}, _self_hosted), do: :badge

  defp changelog_state(%User{changelog_consent: 1}, _self_hosted), do: :widget
  defp changelog_state(_user, false), do: :widget
  defp changelog_state(_user, true), do: :prompt

  defp onboarding?(%{"onboarding_completed" => done}), do: done in [nil, false]
  defp onboarding?(_settings), do: true
end
