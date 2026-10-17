defmodule Dawarich.Test.NativePlaces do
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{FrameSeeds, RailsUser}

  def setup! do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Map.new(~w(SELF_HOSTED DAWARICH_RAILS), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("DAWARICH_RAILS", "off")

    ExUnit.Callbacks.on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    FrameSeeds.user!(11851)
    FrameSeeds.user!(11852)
    %{actor: Accounts.get(11851), other: Accounts.get(11852)}
  end

  def conn(actor), do: RailsUser.signed_in(actor.id) |> RailsUser.connecting_as(actor.id)
  def generation(view, key), do: :sys.get_state(view.pid).socket.assigns[key].generation

  def revoke(actor),
    do:
      Repo.query!("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
        String.duplicate("x", 60),
        actor.id
      ])
end
