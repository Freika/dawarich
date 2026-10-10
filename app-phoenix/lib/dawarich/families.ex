defmodule Dawarich.Families do
  @moduledoc false

  import Ecto.Query

  @invitation_pending 0
  @invitation_expired 2
  @invitation_cancelled 3
  @request_pending 0
  @request_expired 3
  @invitation_retention_days 30

  def page(scope, action, opts \\ []),
    do: Dawarich.Families.NativeReads.page(scope, action, opts)

  def locations(scope, opts \\ []),
    do: Dawarich.Families.NativeReads.locations(scope, opts)

  def history(scope, params, opts \\ []),
    do: Dawarich.Families.NativeReads.history(scope, params, opts)

  def subscribe(scope, opts \\ []) do
    with {:ok, user, _ctx} <- Dawarich.Families.NativeReads.admitted(scope, opts),
         do: Dawarich.Families.Events.subscribe(user.id)
  end

  def expire_invitations(repo, now) do
    {expired, _} =
      from(i in "family_invitations",
        where: i.status == @invitation_pending and i.expires_at < ^now
      )
      |> repo.update_all(set: [status: @invitation_expired])

    threshold = NaiveDateTime.add(now, -@invitation_retention_days, :day)

    {deleted, _} =
      from(i in "family_invitations",
        where:
          i.status in [@invitation_expired, @invitation_cancelled] and
            i.updated_at < ^threshold
      )
      |> repo.delete_all()

    {expired, deleted}
  end

  def expire_location_requests(repo, now) do
    {expired, _} =
      from(r in "family_location_requests",
        where: r.status == @request_pending and r.expires_at <= ^now
      )
      |> repo.update_all(set: [status: @request_expired, updated_at: now])

    expired
  end
end
