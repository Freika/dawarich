defmodule Dawarich.Sharing.Events do
  @moduledoc false

  def enqueue(repo, user_id, public_ids) do
    Dawarich.AfterCommit.enqueue(repo, Dawarich.Sharing.EventsWorker, %{
      "user_id" => user_id,
      "public_refs" => public_ids |> Enum.map(&reference/1) |> Enum.sort(),
      "event_id" => Ecto.UUID.generate()
    })
  end

  def reference(id), do: :crypto.hash(:sha256, id) |> Base.encode16(case: :lower)
  def topic(id), do: "sharing:public:" <> reference(id)
end
