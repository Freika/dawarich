defmodule Dawarich.RailsMessagesTest do
  use ExUnit.Case, async: true

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.{MapGallery, RailsMessages}
  alias Dawarich.Test.A12b

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

  @crypto Dawarich.Test.A12b.fixture("crypto.json")
  @ordered Dawarich.Test.A12b.fixture("crypto.json", objects: :ordered_objects)

  test "blob_key and blob_token messages equal Rails' bytes at the same instant and verify back" do
    datas = Enum.map(@ordered["messages"]["storage"], & &1["data"])

    for {%{"purpose" => purpose, "expires_at" => exp, "signed" => signed}, data} <-
          Enum.zip(@crypto["messages"]["storage"], datas) do
      at = DateTime.add(A12b.now(), 300)
      assert RailsMessages.iso8601_ms(at) == exp
      assert RailsMessages.sign_storage(data, purpose, at, A12b.secret()) == signed

      assert RailsMessages.verify_storage(signed, purpose, A12b.now(), A12b.secret()) ==
               {:ok, Jason.decode!(Jason.encode!(data))}
    end
  end

  test "blob ids verify, expiring ones strictly before their exp, legacy-envelope ones too" do
    for %{"id" => id, "signed" => signed} <-
          @crypto["messages"]["blob_ids"] ++ @crypto["messages"]["legacy_blob_ids"],
        do: assert(RailsMessages.verified_blob_id(signed, A12b.now(), A12b.secret()) == {:ok, id})

    [expiring] = Enum.filter(@crypto["messages"]["blob_ids"], & &1["expires_at"])
    {:ok, at, 0} = DateTime.from_iso8601(expiring["expires_at"])
    before = DateTime.add(at, -1, :millisecond)

    assert RailsMessages.verified_blob_id(expiring["signed"], before, A12b.secret()) ==
             {:ok, expiring["id"]}

    assert RailsMessages.verified_blob_id(expiring["signed"], at, A12b.secret()) == :error
  end

  test "refuses what Rails refuses: other purpose, no purpose, expired, other secret, tampered, garbage" do
    for %{"signed" => signed, "purpose" => purpose} <- @crypto["messages"]["refused"],
        do:
          assert(
            RailsMessages.verify_storage(signed, purpose, A12b.now(), A12b.secret()) == :error
          )

    [%{"signed" => good} | _] = @crypto["messages"]["blob_ids"]
    other = "phoenix-a12b-other-base-not-for-production"
    assert RailsMessages.verified_blob_id(good, A12b.now(), other) == :error
    assert RailsMessages.verified_blob_id(A12b.flip(good, 3), A12b.now(), A12b.secret()) == :error

    for garbage <- [
          "",
          "--",
          "a--b",
          String.duplicate("-", 50),
          <<255, 0>> <> String.duplicate("a", 60),
          nil
        ],
        do: assert(RailsMessages.verified_blob_id(garbage, A12b.now(), A12b.secret()) == :error)
  end

  test "Turbo stream names equal Rails' signed names and verify back to the stream name" do
    for %{"parts" => parts, "name" => name, "signed" => signed} <- @crypto["turbo"] do
      parts =
        Enum.map(parts, fn
          [model, id] -> {String.to_atom(model), id}
          part -> part
        end)

      assert RailsMessages.stream_name(parts, A12b.secret()) == signed
      assert RailsMessages.verified_stream_name(signed, A12b.secret()) == {:ok, name}
    end

    [%{"signed" => signed} | _] = @crypto["turbo"]
    assert RailsMessages.verified_stream_name(A12b.flip(signed, 2), A12b.secret()) == :error
  end

  test "property: storage messages verify only for their purpose, only before exp, never after a flip" do
    A12b.seeded(fn n ->
      data =
        Jason.OrderedObject.new(
          key: A12b.text(),
          disposition: A12b.text(),
          content_type: Enum.random([nil, "application/json"]),
          service_name: "local"
        )

      purpose = Enum.random(["blob_key", "blob_token"])
      at = DateTime.add(A12b.now(), :rand.uniform(600) - 300)
      signed = RailsMessages.sign_storage(data, purpose, at, A12b.secret())

      expected =
        if DateTime.compare(A12b.now(), at) == :lt,
          do: {:ok, Jason.decode!(Jason.encode!(data))},
          else: :error

      assert RailsMessages.verify_storage(signed, purpose, A12b.now(), A12b.secret()) == expected
      assert RailsMessages.verify_storage(signed, "other", A12b.now(), A12b.secret()) == :error
      flipped = A12b.flip(signed, rem(n * 7, byte_size(signed)))
      assert RailsMessages.verify_storage(flipped, purpose, A12b.now(), A12b.secret()) == :error
    end)
  end

  test "property: Turbo names round-trip for any user/trip id and text part" do
    A12b.seeded(fn _ ->
      parts = [{Enum.random([:user, :trip]), :rand.uniform(9_999_999)}, A12b.text()]
      signed = RailsMessages.stream_name(parts, A12b.secret())
      assert {:ok, name} = RailsMessages.verified_stream_name(signed, A12b.secret())
      assert String.ends_with?(name, ":" <> List.last(parts))
    end)
  end
end
