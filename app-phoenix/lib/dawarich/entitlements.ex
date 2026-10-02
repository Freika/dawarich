defmodule Dawarich.Entitlements do
  @moduledoc false

  import Ecto.Query

  alias Dawarich.Repo

  @lite 0
  @family 2

  def full_access?(_user, true, _now), do: true
  def full_access?(%{plan: plan}, false, _now) when plan != @lite, do: true
  def full_access?(user, false, now), do: inherited_family_access?(user.id, now)

  @plan_names %{0 => "lite", 1 => "pro", 2 => "family"}

  def access(user, true, _now), do: {true, Map.get(@plan_names, user.plan, "")}

  def access(user, false, now) do
    inherited = inherited_family_access?(user.id, now)

    {user.plan != @lite or inherited,
     if(inherited, do: "family", else: Map.get(@plan_names, user.plan, ""))}
  end

  def inherited?(nil, @family, owner_until, now), do: future?(owner_until, now)
  def inherited?(nil, _plan, _owner_until, _now), do: false
  def inherited?(access_until, _plan, _owner_until, now), do: future?(access_until, now)

  def future?(nil, _now), do: false

  def future?(%NaiveDateTime{} = at, now),
    do: NaiveDateTime.compare(at, DateTime.to_naive(now)) == :gt

  def future?(%DateTime{} = at, now), do: DateTime.compare(at, now) == :gt

  defp inherited_family_access?(user_id, now) do
    from(m in "family_memberships",
      join: f in "families",
      on: f.id == m.family_id,
      left_join: o in "users",
      on: o.id == f.creator_id and is_nil(o.deleted_at),
      where: m.user_id == ^user_id,
      select: {f.access_until, o.plan, o.active_until}
    )
    |> Repo.one()
    |> case do
      nil -> false
      {access_until, plan, owner_until} -> inherited?(access_until, plan, owner_until, now)
    end
  end
end
