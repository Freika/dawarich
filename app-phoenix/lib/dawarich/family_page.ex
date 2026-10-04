defmodule Dawarich.FamilyPage do
  @moduledoc false

  alias Dawarich.{FamilyPageAccess, Repo, UserTimeZone}

  def read(user, action, opts) do
    FamilyPageAccess.validate_settings!(user.settings)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    self_hosted = Keyword.fetch!(opts, :self_hosted)
    family = membership(user)

    case FamilyPageAccess.state(user, family, action, self_hosted, now) do
      {:page, state} -> document(user, family, state, now, self_hosted)
      redirect -> redirect
    end
  rescue
    ArgumentError -> :rails
  end

  defp membership(user) do
    case query(
           user,
           """
           SELECT f.id, f.name, f.created_at, f.access_until, m.role,
                  o.plan, o.active_until, o.email, f.updated_at
           FROM family_memberships m JOIN families f ON f.id = m.family_id
           LEFT JOIN users o ON o.id = f.creator_id AND o.deleted_at IS NULL
           WHERE m.user_id = $1 ORDER BY m.id LIMIT 1
           """,
           [user.id]
         ).rows do
      [] ->
        nil

      [
        [
          id,
          name,
          created_at,
          access_until,
          role,
          owner_plan,
          owner_until,
          creator_email,
          updated_at
        ]
      ] ->
        %{
          id: id,
          name: name,
          created_at: created_at,
          access_until: access_until,
          role: role,
          owner_plan: owner_plan,
          owner_until: owner_until,
          creator_email: creator_email,
          updated_at: updated_at
        }
    end
  end

  defp document(user, nil, state, _now, _self_hosted),
    do: {:ok, %{state: state, actor_id: user.id, owner?: false, family: nil, members: []}}

  defp document(user, family, :invitations, now, self_hosted) do
    {:ok,
     %{
       state: :invitations,
       actor_id: user.id,
       owner?: family.role == 0,
       live?: FamilyPageAccess.available?(user, family, self_hosted, now),
       members: [],
       family: Map.take(family, [:id, :name, :created_at]),
       invitations: invitations(user, family.id, now, nil)
     }}
  end

  defp document(user, family, {:request, id}, now, _self_hosted) do
    case query(
           user,
           """
           SELECT r.id, r.target_user_id, r.requester_id, u.email, r.status,
                  r.created_at, r.expires_at, r.responded_at, r.suggested_duration
           FROM family_location_requests r LEFT JOIN users u ON u.id = r.requester_id AND u.deleted_at IS NULL
           WHERE r.family_id = $1 AND r.id = $2
           """,
           [family.id, id]
         ).rows do
      [] ->
        {:error, 404}

      [[_id, target_id | _rest]] when target_id != user.id ->
        {:redirect, "/family", :not_request_target}

      [
        [
          id,
          target_id,
          requester_id,
          email,
          status,
          created_at,
          expires_at,
          responded_at,
          duration
        ]
      ] ->
        display =
          cond do
            status == 3 or NaiveDateTime.compare(expires_at, DateTime.to_naive(now)) != :gt ->
              :expired

            status == 0 ->
              :pending

            status == 1 ->
              :accepted

            status == 2 ->
              :declined
          end

        {:ok,
         %{
           state: :request,
           actor_id: user.id,
           members: [],
           owner?: family.role == 0,
           family: Map.take(family, [:id, :name, :created_at]),
           request: %{
             id: id,
             target_id: target_id,
             requester_id: requester_id,
             requester_email: email,
             status: status,
             display: display,
             created_at: created_at,
             expires_at: expires_at,
             responded_at: responded_at,
             suggested_duration: duration
           }
         }}
    end
  end

  defp document(user, %{role: role} = family, :lapsed, now, _self_hosted) when role != 0 do
    [me] = members(user, family.id, now, false, user.id)

    {:ok,
     %{
       state: :lapsed,
       actor_id: user.id,
       owner?: false,
       family: Map.take(family, [:id, :name, :created_at]),
       members: [],
       me: me
     }}
  end

  defp document(user, family, action, now, self_hosted) do
    members = members(user, family.id, now, action == :show, nil)
    invitations = invitations(user, family.id, now, "created_at")

    created_date =
      UserTimeZone.local(user.settings, family.created_at).local |> NaiveDateTime.to_date()

    updated_date =
      UserTimeZone.local(user.settings, family.updated_at).local |> NaiveDateTime.to_date()

    {:ok,
     %{
       state: action,
       actor_id: user.id,
       owner?: family.role == 0,
       family:
         Map.take(family, [:id, :name, :created_at, :creator_email])
         |> Map.merge(%{created_date: created_date, updated_date: updated_date}),
       members: members,
       me: Enum.find(members, &(&1.id == user.id)),
       trial_ends:
         if(user.status == 0 and not is_nil(user.active_until),
           do:
             UserTimeZone.local(user.settings, DateTime.to_naive(user.active_until)).local
             |> NaiveDateTime.to_date()
         ),
       pending_requests: if(action == :show, do: pending_requests(user, now), else: %{}),
       member_count: length(members),
       pending_count: length(invitations),
       invitations: invitations,
       can_invite?: self_hosted or length(members) + length(invitations) < 5
     }}
  end

  defp members(user, family_id, now, latest?, only_id) do
    latest =
      if latest?,
        do: """
        (SELECT max(p.timestamp) FROM points p WHERE p.user_id = u.id
         AND p.lonlat IS NOT NULL AND (p.anomaly = false OR p.anomaly IS NULL))
        """,
        else: "NULL"

    query(
      user,
      """
      SELECT u.id, u.email, m.id, m.role, m.created_at, u.settings, #{latest}
      FROM family_memberships m JOIN users u ON u.id = m.user_id
      WHERE m.family_id = $1 AND u.deleted_at IS NULL AND ($2::bigint IS NULL OR u.id = $2)
      ORDER BY u.email
      """,
      [family_id, only_id]
    ).rows
    |> Enum.map(&FamilyPageAccess.member(&1, now))
  end

  defp pending_requests(user, now) do
    query(
      user,
      """
      SELECT target_user_id, id FROM family_location_requests
      WHERE requester_id = $1 AND status = 0 AND expires_at > $2 ORDER BY id
      """,
      [user.id, DateTime.to_naive(now)]
    ).rows
    |> Map.new(fn [target, id] -> {target, id} end)
  end

  defp invitations(user, family_id, now, order) do
    order = if order, do: " ORDER BY i.#{order}", else: ""

    query(
      user,
      """
      SELECT i.id, i.token, i.email, i.expires_at, i.created_at, u.email
      FROM family_invitations i LEFT JOIN users u ON u.id = i.invited_by_id AND u.deleted_at IS NULL
      WHERE i.family_id = $1 AND i.status = 0 AND i.expires_at > $2#{order}
      """,
      [family_id, DateTime.to_naive(now)]
    ).rows
    |> Enum.map(fn [id, token, email, expires_at, created_at, invited_by] ->
      %{
        id: id,
        token: token,
        email: email,
        expires_at: expires_at,
        created_at: created_at,
        created_date:
          UserTimeZone.local(user.settings, created_at).local |> NaiveDateTime.to_date(),
        expires_local: UserTimeZone.local(user.settings, expires_at).local,
        invited_by: invited_by
      }
    end)
  end

  defp query(user, sql, params), do: UserTimeZone.query!(sql, params, user.settings, Repo)
end
