defmodule Dawarich.Auth.AccountLink.SignIn do
  @moduledoc false
  alias Dawarich.Auth.Trackable
  alias Dawarich.Repo

  def commit(%{kind: :link_only} = linked, _context), do: {:ok, linked}

  def commit(%{kind: :sign_in} = linked, context) do
    user = linked.user

    user =
      if user.failed_attempts in [nil, 0],
        do: user,
        else: save(user, %{failed_attempts: 0}, context)

    changes = Trackable.changes(user, clock(context), Map.fetch!(context, :ip))
    user = save(user, changes, context)
    {:ok, %{linked | user: user}}
  end

  defp save(user, changes, context) do
    user
    |> Ecto.Changeset.change(Map.put(changes, :updated_at, clock(context)))
    |> Map.get(context, :repo, Repo).update!(log: false)
  end

  defp clock(context), do: Map.get(context, :clock, &DateTime.utc_now/0).()
end
