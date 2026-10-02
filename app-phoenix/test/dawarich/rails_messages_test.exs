defmodule Dawarich.RailsMessagesTest do
  use ExUnit.Case, async: true

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.{MapGallery, RailsMessages}

  @corpus "test/fixtures/rails_messages.json" |> File.read!() |> Jason.decode!()

  test "blob ids equal Active Storage's signed_id for the fixture secret" do
    for %{"id" => id, "signed" => signed} <- @corpus["blobs"],
        do: assert(RailsMessages.blob_id(id, @corpus["secret"]) == signed, inspect(id))
  end

  test "stream names equal Turbo's signed_stream_name for [user, :posters]" do
    for %{"user_id" => id, "signed" => signed} <- @corpus["streams"],
        do:
          assert(RailsMessages.stream_name([{:user, id}, "posters"], @corpus["secret"]) == signed)
  end

  test "blob paths equal rails_blob_path, with and without a disposition" do
    for %{"id" => id, "filename" => name, "disposition" => d, "path" => path} <- @corpus["paths"],
        do:
          assert(
            MapGallery.blob_path(%{id: id, filename: name}, d, @corpus["secret"]) == path,
            name
          )
  end

  test "Rails JSON escapes &, <, > and the line separators, and keeps key order" do
    assert Ruby.json_text(~s({"z": "<b>&</b>", "a": "\u2028", "s": "\u2029"})) ==
             "{\"z\":\"\\u003cb\\u003e\\u0026\\u003c/b\\u003e\",\"a\":\"\\u2028\",\"s\":\"\\u2029\"}"
  end
end
