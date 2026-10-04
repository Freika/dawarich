defmodule Dawarich.Imports.ImmichTest do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.RawHTTP
  alias Dawarich.Imports.Integrations.Immich
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.NormalFormats

  setup do
    Dawarich.ApiEndpointCase.clear_transport_env()
    root = Path.join(System.tmp_dir!(), "a7-immich-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Ownership.put!(ScratchRepo, "command:imports.immich_geodata", :oban)
    Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
    %{storage: %{service: "local", stored_service: "test", root: root}}
  end

  test "immich generated import matches name bytes and duplicate notification", %{
    storage: storage
  } do
    c = NormalFormats.seed!("producers/immich/success", ScratchRepo)
    duplicate = fixture("duplicate")
    server = listen()
    settings!(c.user_id, server.port)

    task =
      Task.async(fn -> responses(server, duplicate["requests"]) end)

    args = %{
      "user_id" => c.user_id,
      "time_zone" => c.context.zone,
      "event_id" => Ecto.UUID.generate()
    }

    assert :ok = Immich.run(ScratchRepo, args, storage: storage)

    [[id, name, 5, 5, key, filename, mime]] =
      rows(
        "SELECT i.id,i.name,i.source,i.additional_data_extraction_status,b.key,b.filename,b.content_type FROM imports i JOIN active_storage_attachments a ON a.record_type='Import' AND a.record_id=i.id JOIN active_storage_blobs b ON b.id=a.blob_id"
      )

    expected = hd(c.expected["imports"])
    assert name == expected["name"]
    assert filename == expected["file"]["filename"]
    assert mime == expected["file"]["content_type"]
    assert File.read!(Dawarich.Storage.disk_path(storage.root, key)) == expected["file"]["bytes"]

    assert rows("SELECT command_type,payload FROM job_outbox") ==
             [
               [
                 "imports.process_normal",
                 %{"user_id" => c.user_id, "import_id" => id, "time_zone" => c.context.zone}
               ]
             ]

    assert :ok =
             Immich.run(ScratchRepo, %{args | "event_id" => Ecto.UUID.generate()},
               storage: storage
             )

    assert rows("SELECT name FROM imports") == [[name]]

    assert rows(
             "SELECT title,content,CASE kind WHEN 0 THEN 'info' END FROM notifications ORDER BY id"
           ) == duplicate["notifications"]

    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
    Task.await(task)
    rows("UPDATE imports SET source=10 WHERE id=$1", [id])
    conflict = Task.async(fn -> responses(server, c.expected["requests"]) end)

    assert {:discard, :name_conflict} =
             Immich.run(ScratchRepo, %{args | "event_id" => Ecto.UUID.generate()},
               storage: storage
             )

    assert rows("SELECT count(*) FROM imports") == [[1]]
    Task.await(conflict)

    filtered_requests =
      List.update_at(c.expected["requests"], 0, fn request ->
        payload = Jason.decode!(request["body"])
        asset = hd(payload["assets"]["items"])

        missing_frame =
          asset
          |> Map.delete("fileCreatedAt")
          |> put_in(["exifInfo", "dateTimeOriginal"], "2026-01-15T23:30:00Z")

        before_start = Map.put(asset, "fileCreatedAt", "1900-01-01T00:00:00Z")

        zero_coordinate = put_in(asset, ["exifInfo", "latitude"], 0.0)

        Map.put(
          request,
          "body",
          Jason.encode!(
            put_in(payload, ["assets", "items"], [missing_frame, before_start, zero_coordinate])
          )
        )
      end)

    filtered = Task.async(fn -> responses(server, filtered_requests) end)

    assert :ok =
             Immich.run(ScratchRepo, %{args | "event_id" => Ecto.UUID.generate()},
               storage: storage
             )

    assert rows("SELECT count(*) FROM imports") == [[1]]
    assert rows("SELECT count(*) FROM notifications") == [[1]]
    Task.await(filtered)
  end

  test "immich connection error classification and owner loss prevent later effects", %{
    storage: storage
  } do
    assert Dawarich.Imports.Integrations.ImmichWorker.perform(%Oban.Job{
             args: %{"event_id" => "invalid"}
           }) ==
             {:discard, :invalid_payload}

    assert Immich.classify({:error, :timeout}) == {:error, :connection}
    assert Immich.classify({:ok, 200, "invalid JSON"}) == {:discard, :invalid_payload}
    assert Immich.classify({:ok, 401, "{}"}) == {:ok, []}
    c = NormalFormats.seed!("producers/immich/success", ScratchRepo)
    server = listen()
    settings!(c.user_id, server.port)

    task =
      Task.async(fn ->
        socket = accept(server)
        read_request(socket)
        Ownership.put!(ScratchRepo, "command:imports.immich_geodata", :sidekiq)
        answer(socket, hd(c.expected["requests"]))
        :gen_tcp.close(socket)
      end)

    args = %{
      "user_id" => c.user_id,
      "time_zone" => c.context.zone,
      "event_id" => Ecto.UUID.generate()
    }

    assert {:cancel, :ownership_lost} = Immich.run(ScratchRepo, args, storage: storage)
    assert rows("SELECT count(*) FROM imports") == [[0]]
    assert rows("SELECT count(*) FROM active_storage_blobs") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert Path.wildcard(Path.join(storage.root, "**/*")) == []
    Task.await(task)
  end

  defp fixture(name) do
    Path.expand("../../fixtures/imports/formats/producers/immich/#{name}.json", __DIR__)
    |> File.read!()
    |> Jason.decode!()
    |> NormalFormats.decode()
  end

  defp settings!(user, port) do
    rows("UPDATE users SET settings=settings || $2::jsonb WHERE id=$1", [
      user,
      %{
        "immich_url" => "http://127.0.0.1:#{port}",
        "immich_api_key" => "synthetic-provider-fixture"
      }
    ])
  end

  defp responses(server, requests) do
    Enum.each(requests, fn request ->
      socket = accept(server)
      {head, body} = read_request(socket)
      assert request_line(head) == "POST /api/search/metadata HTTP/1.1"
      assert Jason.decode!(body) == request["parameters"]
      answer(socket, request)
      :gen_tcp.close(socket)
    end)
  end

  defp read_request(socket) do
    {head, rest} = read_head(socket)
    size = head |> header("content-length") |> hd() |> String.to_integer()
    {head, read_at_least(socket, rest, size)}
  end

  defp answer(socket, request),
    do:
      reply(
        socket,
        "HTTP/1.1 #{request["status"]} Fixture\r\nconnection: close\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(request["body"])}\r\n\r\n#{request["body"]}"
      )
end
