defmodule Dawarich.Test.NormalFormats do
  @moduledoc false
  @dir Path.expand("../fixtures/imports/formats", __DIR__)
  @stamp ~N[2026-01-15 23:30:00]
  @sources ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)

  def seed!(name, repo) do
    expected = @dir |> Path.join(name <> ".json") |> File.read!() |> Jason.decode!()
    identities = expected["identities"] || %{}

    {1, [%{id: user}]} =
      repo.insert_all(
        "users",
        [
          %{
            email: "normal-#{System.unique_integer([:positive])}@dawarich.test",
            settings: %{"timezone" => expected["zone"], "locale" => expected["locale"]},
            created_at: @stamp,
            updated_at: @stamp
          }
          |> identity(:id, identities["user_id"])
        ],
        returning: [:id]
      )

    {1, [%{id: id}]} =
      repo.insert_all(
        "imports",
        [
          %{
            user_id: user,
            name: name,
            source: Enum.find_index(@sources, &(&1 == expected["import"]["source"])),
            created_at: @stamp,
            updated_at: @stamp
          }
          |> identity(:id, identities["import_id"])
        ],
        returning: [:id]
      )

    %{
      import: %{id: id, user_id: user},
      path: Path.join(@dir, expected["input"]),
      expected: decode(expected),
      context: %{
        repo: repo,
        zone: expected["zone"],
        locale: expected["locale"],
        now: @stamp,
        altitude_decimal?: true,
        fence: fn fun -> fun.() end
      }
    }
  end

  def whole!(name, repo, root) do
    expected =
      @dir
      |> Path.join("whole_create/" <> name <> ".json")
      |> File.read!()
      |> Jason.decode!()
      |> decode()

    user = expected["identities"]["user_id"]
    id = expected["identities"]["import_id"]
    parent = expected["parent"] || %{"name" => archive_name(expected)}
    source = Enum.find_index(@sources, &(&1 == expected["initial_source"]))

    repo.insert_all("users", [
      %{
        id: user,
        email: "whole@example.test",
        settings: %{"timezone" => expected["zone"], "locale" => expected["locale"]},
        status: if(expected["trial"], do: 2, else: 1),
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    repo.insert_all("imports", [
      %{
        id: id,
        user_id: user,
        name: parent["name"],
        source: source,
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    for initial <- expected["initial_imports"] do
      repo.insert_all("imports", [
        %{
          id: initial["id"],
          user_id: user,
          name: initial["name"],
          source: Enum.find_index(@sources, &(&1 == initial["source"])),
          additional_data_extraction_status: 5,
          created_at: @stamp,
          updated_at: @stamp
        }
      ])
    end

    repo.query!(
      "SELECT setval(pg_get_serial_sequence('imports','id'),GREATEST(987200,(SELECT max(id) FROM imports)),true)"
    )

    for point <- expected["initial_points"] do
      repo.query!(
        "INSERT INTO points(user_id,lonlat,timestamp,created_at,updated_at) VALUES($1,ST_GeomFromText($2,4326),$3,$4,$4)",
        [user, point["lonlat"], point["timestamp"], @stamp]
      )
    end

    bytes =
      if parent["file"],
        do: parent["file"]["bytes"],
        else: File.read!(Path.join(@dir, "whole_create/" <> expected["input"]))

    filename = if parent["file"], do: parent["file"]["filename"], else: parent["name"]
    content_type = if parent["file"], do: parent["file"]["content_type"], else: "application/zip"
    key = Dawarich.Storage.generate_key()
    path = Dawarich.Storage.disk_path(root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)

    {1, [%{id: blob}]} =
      repo.insert_all(
        "active_storage_blobs",
        [
          %{
            id: 987_301,
            key: key,
            filename: filename,
            content_type: content_type,
            byte_size: byte_size(bytes),
            checksum: Base.encode64(:crypto.hash(:md5, bytes)),
            service_name: "local",
            created_at: @stamp
          }
        ],
        returning: [:id]
      )

    repo.query!("SELECT setval(pg_get_serial_sequence('active_storage_blobs','id'),987301,true)")

    repo.insert_all("active_storage_attachments", [
      %{record_type: "Import", record_id: id, name: "file", blob_id: blob, created_at: @stamp}
    ])

    args = %{
      "event_id" => Ecto.UUID.generate(),
      "import_id" => id,
      "user_id" => user,
      "time_zone" => expected["zone"]
    }

    {1, [%{id: job}]} =
      repo.insert_all(
        "oban_jobs",
        [
          %{
            state: "executing",
            queue: "imports",
            worker: "Dawarich.Imports.ProcessWorker",
            args: args,
            attempt: 1,
            max_attempts: 3,
            attempted_at: @stamp
          }
        ],
        prefix: "oban",
        returning: [:id]
      )

    Dawarich.Jobs.Ownership.put!(repo, "command:imports.process_normal", :oban)

    %{
      import: %{id: id, user_id: user},
      job: %Oban.Job{id: job, attempt: 1, args: args},
      expected: expected,
      context: %{
        repo: repo,
        locale: expected["locale"],
        zone: expected["zone"],
        now: DateTime.from_naive!(@stamp, "Etc/UTC"),
        services: %{"local" => %{service: "local", root: root}},
        temp_dir: root,
        self_hosted?: true,
        on_terminal: fn ->
          Dawarich.Jobs.Processed.mark!(repo, args["event_id"], "imports.process_normal")
        end
      }
    }
  end

  defp archive_name(expected) do
    name =
      Enum.find_value(expected["children"], fn child ->
        case Regex.run(~r/\(from (.*)\)$/, child["name"]) do
          [_, name] -> name
          _ -> nil
        end
      end)

    name || String.replace(expected["input"], ".input", "")
  end

  def decode(%{"__float__" => name}),
    do: %{"Infinity" => :infinity, "-Infinity" => :neg_infinity, "NaN" => :nan}[name]

  def decode(%{"__float64__" => hex}) do
    <<value::float-64>> = Base.decode16!(hex, case: :mixed)
    value
  end

  def decode(%{"__bytes__" => hex}), do: Base.decode16!(hex, case: :mixed)

  def decode(%{"__symbol_pairs__" => pairs}),
    do:
      Dawarich.Imports.NormalCast.symbolic_hash(Enum.map(pairs, fn [k, v] -> {k, decode(v)} end))

  def decode(%{"__symbol_hash__" => map}),
    do: Dawarich.Imports.NormalCast.symbolic_hash(Enum.map(map, fn {k, v} -> {k, decode(v)} end))

  def decode(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, decode(value)} end)
  def decode(list) when is_list(list), do: Enum.map(list, &decode/1)
  def decode(value), do: value

  defp identity(attrs, _, nil), do: attrs
  defp identity(attrs, key, value), do: Map.put(attrs, key, value)
end
