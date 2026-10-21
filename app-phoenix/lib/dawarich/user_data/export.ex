defmodule Dawarich.UserData.Export do
  @moduledoc false
  alias Dawarich.UserData.Export.{
    Settings,
    Areas,
    Places,
    Imports,
    Exports,
    Trips,
    Notifications,
    Tags,
    Taggings,
    Points,
    Visits,
    Stats,
    Tracks,
    Digests,
    RawArchives,
    Files,
    Manifest,
    Zip
  }

  @modules [
    Settings,
    Areas,
    Places,
    Imports,
    Exports,
    Trips,
    Notifications,
    Tags,
    Taggings,
    Points,
    Visits,
    Stats,
    Tracks,
    Digests,
    RawArchives
  ]

  def write(repo, user, dir, context) do
    context = Files.context(context, dir)
    entries = Enum.flat_map(@modules, & &1.write(repo, user, dir, context))
    manifest = Manifest.write(repo, user, dir, entries, context)
    %{path: Zip.write!(dir), counts: manifest.count}
  end

  def notify!(repo, user, counts, locale, now) do
    summary =
      Enum.map_join(
        ~w(points visits places trips areas imports exports stats tags tracks digests notifications),
        ", ",
        &"#{counts[&1]} #{&1}"
      )

    {:ok, title} = Dawarich.I18n.t(locale, "services.users.export_data.export_completed")

    {:ok, content} =
      Dawarich.I18n.t(
        locale,
        "services.users.export_data.your_data_export_has_been_processed_successfully_summary_you_can",
        %{"summary" => summary}
      )

    Dawarich.Notifications.create!(repo, user, :info, title, content, now)
  end
end
