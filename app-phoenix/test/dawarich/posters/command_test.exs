defmodule Dawarich.Posters.CommandTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Posters.Persistence

  @tag mutation: "owner"
  test "poster producer follows Oban owner and Sidekiq fallback without double enqueue" do
    id = user!()
    Ownership.put!(Repo, "command:posters.create", :oban)
    assert {:ok, poster} = Persistence.create(%{"title" => ""}, %{id: id}, "de")
    assert commands() == []

    assert [["posters.create", 1, payload, metadata, ^poster, dedupe, scheduled]] =
             Repo.query!(
               "SELECT command_type, command_version, payload, metadata, aggregate_id, dedupe_key, scheduled_at FROM public.job_outbox WHERE aggregate_id = $1 AND command_type = 'posters.create'",
               [poster]
             ).rows

    assert payload == %{"poster_id" => poster, "user_id" => id, "locale" => "de"}
    assert metadata == %{"producer" => "Phoenix PostersCreate"}
    assert dedupe == "poster-create:#{poster}"
    assert %DateTime{} = scheduled
    Ownership.put!(Repo, "command:posters.create", :sidekiq)
    assert {:ok, fallback} = Persistence.create(%{}, %{id: id}, "en")

    assert commands() == [
             ["posters.created", %{"poster_id" => fallback, "user_id" => id, "locale" => "en"}]
           ]

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM public.job_outbox WHERE command_type = 'posters.create'"
             ).rows
  end
end
