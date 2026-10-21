defmodule Dawarich.Families do
  @moduledoc false

  def page(scope, action, opts \\ []),
    do: Dawarich.Families.NativeReads.page(scope, action, opts)

  def locations(scope, opts \\ []),
    do: Dawarich.Families.NativeReads.locations(scope, opts)

  def deadline(scope, opts \\ []), do: Dawarich.Families.NativeDeadline.read(scope, opts)

  def history(scope, params, opts \\ []),
    do: Dawarich.Families.NativeReads.history(scope, params, opts)

  def reveal_invitation(scope, id, opts \\ []) when is_integer(id) and id > 0 do
    with {:ok, user, ctx} <- Dawarich.Families.NativeReads.actor(scope, opts),
         {:ok, page} <-
           Dawarich.FamilyPage.read(user, :invitations, Keyword.merge(opts, Map.to_list(ctx))),
         %{token: token} <- Enum.find(page.invitations, &(&1.id == id)) do
      {:ok, token}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  def subscribe_changes(scope, opts \\ []) do
    with {:ok, user, _} <- Dawarich.Families.NativeReads.actor(scope, opts),
         do: Dawarich.Families.Events.subscribe(user.id)
  end

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

  def expire_invitations(repo, now),
    do: Dawarich.Families.NativeHousekeeping.invitations(repo, now)

  def expire_location_requests(repo, now),
    do: Dawarich.Families.NativeHousekeeping.requests(repo, now)
end
