defmodule Dawarich.Test.UserDataSeeds do
  @moduledoc false
  @dir Path.expand("../fixtures/user_data", __DIR__)
  @stamp ~N[2026-10-02 12:00:00]
  @tables ~w(users countries areas places imports exports trips notifications tags visits points stats tracks digests points_raw_data_archives taggings track_segments)

  def seed!(name, repo) do
    capture = @dir |> Path.join("capture.json") |> File.read!() |> Jason.decode!()
    export = capture["exports"] |> Map.get(name)
    expected = export || expected(capture, name)
    entry_name = if export, do: "export_" <> String.replace(name, "/", "_"), else: name
    user = if export, do: 988_001, else: 988_003

    if export do
      insert_rows(repo, export["seed_rows"])

      Dawarich.Test.SeedIds.insert_all!(repo, "exports", [
        %{
          id: 988_202,
          user_id: user,
          name: "user_data_export_20261002_120000.zip",
          file_format: 2,
          file_type: 1,
          status: 1,
          processing_started_at: @stamp,
          created_at: @stamp,
          updated_at: @stamp
        }
      ])
    else
      Dawarich.Test.SeedIds.insert_all!(repo, "users", [
        %{
          id: user,
          email: "user-data-target@example.invalid",
          settings: %{
            "timezone" => "UTC",
            "locale" => "en",
            "gps_filtering_enabled" => false,
            "retained" => "yes"
          },
          created_at: @stamp,
          updated_at: @stamp
        }
      ])
    end

    root = Path.join(System.tmp_dir!(), "user-data-storage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    if export, do: insert_files(repo, root, export["seed_rows"]["storage"])
    path = archive(entry_name)

    ExUnit.Callbacks.on_exit(fn ->
      File.rm_rf!(root)
      File.rm(path)
    end)

    %{
      user_id: user,
      export_id: if(export, do: 988_202),
      archive_path: path,
      expected: expected,
      context: %{
        repo: repo,
        zone: (export && export["zone"]) || "UTC",
        locale: "en",
        now: @stamp,
        fence: fn fun -> fun.() end,
        storage: %{service: "local", root: root},
        storage_services: %{"local" => %{service: "local", root: root, stored_service: "local"}}
      }
    }
  end

  def current_export_entries(zone) do
    tracks =
      @dir
      |> Path.join("map_matching_columns.json")
      |> File.read!()
      |> Jason.decode!()
      |> get_in(["exports", zone])

    Map.merge(entries("export_" <> String.replace(zone, "/", "_")), tracks)
  end

  def entries(name) do
    directory = Path.join([@dir, name, "entries"])

    ordinary =
      directory
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.reject(&File.dir?/1)
      |> Map.new(fn path -> {Path.relative_to(path, directory), File.read!(path)} end)

    extra_path = Path.join([@dir, name, "unsafe_entries.json"])

    extra =
      if File.exists?(extra_path) do
        extra_path
        |> File.read!()
        |> Jason.decode!()
        |> Map.new(fn {key, value} -> {key, Base.decode64!(value)} end)
      else
        %{}
      end

    Map.merge(ordinary, extra)
  end

  defp archive(name) do
    path = Path.join(System.tmp_dir!(), "user-data-#{System.unique_integer([:positive])}.zip")
    rows = Enum.map(entries(name), fn {entry, bytes} -> {String.to_charlist(entry), bytes} end)
    {:ok, _} = :zip.create(String.to_charlist(path), rows)
    path
  end

  defp expected(capture, "boundary_" <> count) do
    Enum.find(capture["boundaries"], &(&1["count"] == String.to_integer(count)))
  end

  defp expected(capture, name) do
    capture["restores"][name] || capture["cases"][name] || capture[name] ||
      @dir |> Path.join(name <> ".json") |> File.read!() |> Jason.decode!()
  end

  defp insert_rows(repo, rows) do
    Enum.each(@tables, fn table ->
      key = if table == "points_raw_data_archives", do: "raw_data_archives", else: table

      Enum.each(rows[key] || [], fn row ->
        columns = row |> Map.keys() |> Enum.sort()
        names = Enum.map_join(columns, ",", &~s("#{&1}"))
        selects = Enum.map_join(columns, ",", &~s(r."#{&1}"))

        Ecto.Adapters.SQL.query!(
          repo,
          "INSERT INTO public.#{table}(#{names}) SELECT #{selects} FROM jsonb_populate_record(NULL::public.#{table},$1::jsonb) r",
          [row]
        )

        Dawarich.Test.SeedIds.advance!(repo, table, [row["id"]])
      end)
    end)
  end

  defp insert_files(repo, root, files) do
    Enum.each(files || [], fn file ->
      blob =
        Dawarich.RailsBlobFixture.create!(
          repo,
          root,
          file["filename"],
          Base.decode64!(file["bytes"]),
          content_type: file["content_type"]
        )

      Dawarich.Test.SeedIds.insert_all!(repo, "active_storage_attachments", [
        %{
          name: "file",
          record_type: file["record_type"],
          record_id: file["record_id"],
          blob_id: blob.id,
          created_at: @stamp
        }
      ])
    end)
  end
end
