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

  def create(scope, attrs, opts \\ []), do: command(scope, :create, attrs, opts)
  def update(scope, attrs, opts \\ []), do: command(scope, :update, attrs, opts)
  def delete(scope, opts \\ []), do: command(scope, :delete, %{}, opts)
  def invite(scope, attrs, opts \\ []), do: command(scope, :invite, attrs, opts)

  def cancel_invitation(scope, id, opts \\ []),
    do: command(scope, :cancel_invitation, %{"id" => id}, opts)

  def accept_invitation(scope, token, opts \\ []),
    do: command(scope, :accept_invitation, %{"token" => token}, opts)

  def remove_member(scope, id, opts \\ []),
    do: command(scope, :remove_member, %{"id" => id}, opts)

  def request_location(scope, attrs, opts \\ []),
    do: command(scope, :request_location, attrs, opts)

  def set_sharing(scope, attrs, opts \\ []), do: command(scope, :set_sharing, attrs, opts)
  def respond_location(scope, id, decision, attrs, opts \\ [])

  def respond_location(scope, id, decision, attrs, opts) when is_map(attrs),
    do:
      command(
        scope,
        :respond_location,
        Map.merge(attrs, %{"id" => id, "decision" => decision}),
        opts
      )

  def respond_location(_, _, _, _, _), do: {:error, :invalid_input}

  defp command(scope, action, attrs, opts),
    do: Dawarich.Families.NativeCommands.run(scope, action, attrs, opts)

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
