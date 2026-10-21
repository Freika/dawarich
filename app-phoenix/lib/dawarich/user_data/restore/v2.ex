defmodule Dawarich.UserData.Restore.V2 do
  @moduledoc false
  alias Dawarich.UserData.{Jsonl, Paths, Versions, Restore}

  alias Dawarich.UserData.Restore.{
    Settings,
    Areas,
    Places,
    Tags,
    Taggings,
    Imports,
    Exports,
    Trips,
    Stats,
    Digests,
    Notifications,
    Visits,
    Tracks,
    Points,
    RawArchives,
    Monthly,
    Messages
  }

  @order ~w(settings areas places tags taggings imports exports trips stats digests notifications visits tracks points raw_data_archives)
  @modules %{
    "areas" => Areas,
    "places" => Places,
    "tags" => Tags,
    "taggings" => Taggings,
    "trips" => Trips,
    "stats" => Stats,
    "digests" => Digests,
    "notifications" => Notifications,
    "visits" => Visits,
    "tracks" => Tracks
  }

  def call(repo, user, dir, context) do
    manifest = Versions.manifest(dir)

    stats =
      Enum.reduce(@order, Restore.initial_stats(), fn name, stats ->
        case name do
          name when name in ~w(visits tracks stats digests) ->
            count = Monthly.call(@modules[name], repo, user, dir, manifest, name, context)
            add(stats, name, count)

          "points" ->
            add(stats, name, Points.call(repo, user, point_rows(dir, manifest), context))

          "settings" ->
            path = Path.join(dir, "settings.jsonl")
            data = if File.regular?(path), do: rows(path) |> Enum.take(1), else: []

            case data do
              [] ->
                stats

              [row] ->
                Settings.call(repo, user, row, context)
                Map.put(stats, "settings_updated", true)
            end

          "places" ->
            add(stats, name, Places.call(repo, user, file_rows(dir, name), context))

          _ ->
            section(repo, user, dir, name, Enum.to_list(file_rows(dir, name)), stats, context)
        end
      end)

    Messages.completeness(stats, manifest["counts"])
    stats
  end

  def section(repo, user, dir, name, data, stats, context) do
    case name do
      "settings" ->
        Settings.call(repo, user, data, context)
        Map.put(stats, "settings_updated", true)

      name when name in ~w(imports exports raw_data_archives) ->
        module =
          %{"imports" => Imports, "exports" => Exports, "raw_data_archives" => RawArchives}[name]

        [count, files] = module.call(repo, user, data, Path.join(dir, "files"), context)
        stats |> add(name, count) |> Map.update!("files_restored", &(&1 + files))

      name when is_map_key(@modules, name) ->
        add(stats, name, @modules[name].call(repo, user, data, context))

      _ ->
        stats
    end
  rescue
    error in KeyError ->
      names = %{
        "tags" => "Tag",
        "imports" => "Import",
        "places" => "Place",
        "digests" => "Users::Digest",
        "visits" => "Visit"
      }

      if Map.has_key?(names, name),
        do: raise(ArgumentError, "unknown attribute '#{error.key}' for #{names[name]}."),
        else: reraise(error, __STACKTRACE__)
  end

  def point_rows(dir, manifest) do
    files = get_in(manifest, ["files", "points"]) || []
    files = if files == [], do: ["points.jsonl"], else: Enum.sort(files)

    Stream.flat_map(files, fn name ->
      path = Paths.relative(dir, name)
      if path && File.regular?(path), do: rows(path), else: []
    end)
  end

  def file_rows(dir, name) do
    path = Path.join(dir, name <> ".jsonl")
    if File.regular?(path), do: rows(path), else: []
  end

  def rows(path),
    do:
      path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.map(&Jsonl.decode!/1)

  def add(stats, name, count), do: Map.update!(stats, name <> "_created", &(&1 + count))
end
