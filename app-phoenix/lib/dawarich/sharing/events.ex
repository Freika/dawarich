defmodule Dawarich.Sharing.Events do
  @moduledoc false

  def enqueue(repo, user_id, public_ids) do
    Dawarich.AfterCommit.enqueue(repo, Dawarich.Sharing.EventsWorker, %{
      "user_id" => user_id,
      "public_ids" => Enum.sort(public_ids),
      "event_id" => Ecto.UUID.generate()
    })
  end
end
