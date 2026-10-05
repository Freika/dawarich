defmodule Dawarich.Imports.PhotoprismTest do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.RawHTTP
  alias Dawarich.Imports.Integrations.{Photoprism, PhotoprismWorker}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.NormalFormats

  setup do
    Dawarich.ApiEndpointCase.clear_transport_env()
    for child <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(child)
    root = Path.join(System.tmp_dir!(), "a7-photoprism-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Ownership.put!(ScratchRepo, "command:imports.photoprism_geodata", :oban)
    Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
    Dawarich.Redis.cache_command(["UNLINK", "dawarich/photoprism_preview_token_987001"])
    %{storage: %{service: "local", stored_service: "test", root: root}}
  end

  test "photoprism pagination and generated attachment match Rails", %{storage: storage} do
    c = NormalFormats.seed!("producers/photoprism/success", ScratchRepo)
    server = listen()
    settings!(c.user_id, server.port)
    [first, last] = c.expected["requests"]
    zero = %{"Lat" => 0.0, "Lng" => 12.4, "TakenAt" => "2026-01-15T23:30:00Z"}
    full = Map.put(first, "body", Jason.encode!(List.duplicate(zero, 1000)))
    next = Map.put(first, "parameters", last["parameters"])
    ending = put_in(last, ["parameters", "offset"], ["2000"])
    task = Task.async(fn -> responses(server, [full, next, ending]) end)
    args = args(c)
    assert :ok = Photoprism.run(ScratchRepo, args, storage: storage)
    Task.await(task)

    [[id, name, 7, 5, key, filename, mime]] =
      rows(
        "SELECT i.id,i.name,i.source,i.additional_data_extraction_status,b.key,b.filename,b.content_type FROM imports i JOIN active_storage_attachments a ON a.record_type='Import' AND a.record_id=i.id JOIN active_storage_blobs b ON b.id=a.blob_id"
      )

    expected = hd(c.expected["imports"])
    assert name == expected["name"]
    assert filename == expected["file"]["filename"]
    assert mime == expected["file"]["content_type"]
    assert File.read!(Dawarich.Storage.disk_path(storage.root, key)) == expected["file"]["bytes"]

    assert Dawarich.RailsCache.get("dawarich/photoprism_preview_token_#{c.user_id}") ==
             {:ok, "synthetic-preview"}

    assert rows("SELECT command_type,payload FROM job_outbox") ==
             [
               [
                 "imports.process_normal",
                 %{"user_id" => c.user_id, "import_id" => id, "time_zone" => c.context.zone}
               ]
             ]

    duplicate = fixture("duplicate")
    task = Task.async(fn -> responses(server, c.expected["requests"]) end)

    assert :ok =
             Photoprism.run(ScratchRepo, %{args | "event_id" => Ecto.UUID.generate()},
               storage: storage
             )

    Task.await(task)
    assert rows("SELECT name FROM imports") == [[name]]

    assert rows(
             "SELECT title,content,CASE kind WHEN 0 THEN 'info' END FROM notifications ORDER BY id"
           ) == duplicate["notifications"]

    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
    assert Dawarich.RailsCache.get("dawarich/photoprism_preview_token_#{c.user_id}") == {:ok, nil}

    assert PhotoprismWorker.args_from_command(1, Map.delete(args, "event_id")) ==
             {:ok, Map.delete(args, "event_id")}

    assert PhotoprismWorker.args_from_command(1, %{"user_id" => c.user_id}) ==
             {:error, "invalid_payload"}
  end

  test "photoprism permanent authentication error is not connection retry", %{storage: storage} do
    c = NormalFormats.seed!("producers/photoprism/auth", ScratchRepo)
    server = listen()
    settings!(c.user_id, server.port)
    task = Task.async(fn -> responses(server, c.expected["requests"]) end)
    assert Photoprism.classify({:ok, 401, "application/json", "{}"}) == {:ok, []}
    assert :ok = Photoprism.run(ScratchRepo, args(c), storage: storage)
    Task.await(task)
    assert rows("SELECT count(*) FROM imports") == [[0]]
    assert rows("SELECT title,content FROM notifications") == c.expected["notifications"]
    assert Photoprism.classify({:error, :timeout}) == {:error, :connection}
    assert Photoprism.classify({:ok, 200, "text/html", "[]"}) == {:ok, []}
    assert Photoprism.classify({:ok, 200, "application/json", "invalid"}) == {:ok, []}

    assert PhotoprismWorker.perform(%Oban.Job{args: %{"event_id" => "invalid"}}) ==
             {:discard, :invalid_payload}

    success = fixture("success")

    task =
      Task.async(fn ->
        socket = accept(server)
        read_head(socket)
        Ownership.put!(ScratchRepo, "command:imports.photoprism_geodata", :sidekiq)
        answer(socket, hd(success["requests"]))
        :gen_tcp.close(socket)
      end)

    assert {:cancel, :ownership_lost} = Photoprism.run(ScratchRepo, args(c), storage: storage)
    Task.await(task)
    assert rows("SELECT count(*) FROM active_storage_blobs") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert Path.wildcard(Path.join(storage.root, "**/*")) == []
  end

  defp args(c),
    do: %{
      "user_id" => c.user_id,
      "time_zone" => c.context.zone,
      "event_id" => Ecto.UUID.generate()
    }

  defp fixture(name) do
    Path.expand("../../fixtures/imports/formats/producers/photoprism/#{name}.json", __DIR__)
    |> File.read!()
    |> Jason.decode!()
    |> NormalFormats.decode()
  end

  defp settings!(user, port) do
    rows("UPDATE users SET settings=settings || $2::jsonb WHERE id=$1", [
      user,
      %{
        "photoprism_url" => "http://127.0.0.1:#{port}",
        "photoprism_api_key" => "synthetic-provider-fixture"
      }
    ])
  end

  defp responses(server, requests) do
    Enum.each(requests, fn request ->
      socket = accept(server)
      {head, _} = read_head(socket)
      ["GET", target, "HTTP/1.1"] = String.split(request_line(head), " ")
      uri = URI.parse(target)
      assert uri.path == "/api/v1/photos"

      assert Map.new(URI.decode_query(uri.query), fn {key, value} -> {key, [value]} end) ==
               request["parameters"]

      assert header(head, "authorization") == ["Bearer synthetic-provider-fixture"]
      preview = if length(requests) == 3, do: "x-preview-token: synthetic-preview\r\n", else: ""
      answer(socket, request, preview)
      :gen_tcp.close(socket)
    end)
  end

  defp answer(socket, request, preview \\ ""),
    do:
      reply(
        socket,
        "HTTP/1.1 #{request["status"]} Fixture\r\nconnection: close\r\n#{preview}content-type: application/json\r\ncontent-length: #{byte_size(request["body"])}\r\n\r\n#{request["body"]}"
      )
end
