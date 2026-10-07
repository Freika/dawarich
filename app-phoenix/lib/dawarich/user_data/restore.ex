defmodule Dawarich.UserData.Restore do
  @moduledoc false
  require Logger
  alias Dawarich.UserData.{Archive, Versions}
  alias Dawarich.UserData.Restore.{V1, V2, Messages, Files, Resume}
  alias Dawarich.Imports.Fence

  @entities ~w(areas places tags taggings imports exports trips stats digests notifications visits tracks points raw_data_archives)

  def initial_stats do
    Map.new(
      [{"settings_updated", false}, {"files_restored", 0}] ++
        Enum.map(@entities, &{&1 <> "_created", 0})
    )
  end

  def call(repo, user, path, context, opts \\ []) do
    stats =
      Archive.with_directory(path, context, fn directory ->
        Files.with_uploads(context, fn context ->
          Fence.run(context, fn ->
            {:ok, stats} =
              repo.transaction(fn ->
                Resume.call(repo, directory, context, fn ->
                  stats =
                    case Versions.detect(directory) do
                      1 ->
                        V1.call(repo, user, directory, context)

                      2 ->
                        V2.call(repo, user, directory, context)

                      version ->
                        raise elem(
                                Dawarich.I18n.t(
                                  locale(repo, user, context),
                                  "services.users.import_data.unsupported_format_version",
                                  %{"version" => version}
                                ),
                                1
                              )
                    end

                  Messages.success(repo, user, stats, context)
                  stats
                end)
              end)

            stats
          end)
        end)
      end)

    filter = Keyword.get(opts, :filter, &Dawarich.Points.AnomalyFilter.call/5)
    filter(repo, user, context, filter)
    stats
  rescue
    error in Dawarich.Imports.LeaseLost ->
      reraise error, __STACKTRACE__

    error in Versions.UnsupportedFormatError ->
      Messages.failure(repo, user, error, context)
      nil

    error ->
      report(context, error, "Data import failed")
      Messages.failure(repo, user, error, context)
      reraise error, __STACKTRACE__
  end

  def filter(repo, user, context, fun \\ &Dawarich.Points.AnomalyFilter.call/5) do
    case repo.query!("SELECT min(timestamp),max(timestamp) FROM points WHERE user_id=$1", [user],
           log: false
         ).rows do
      [[nil, nil]] ->
        0

      [[first, last]] ->
        fun.(repo, user, first, last,
          zone: context.zone,
          fence: fn effect -> Fence.run(context, effect) end
        )
    end
  rescue
    error in Dawarich.Imports.LeaseLost ->
      reraise error, __STACKTRACE__

    error ->
      report(context, error, "Anomaly filtering failed after data import")
      0
  end

  def locale(repo, user, context) do
    case repo.query!("SELECT settings FROM users WHERE id=$1", [user], log: false).rows do
      [[settings]] ->
        locale = Dawarich.UserSettings.safe(settings)["locale"]
        if is_binary(locale) and locale != "", do: locale, else: context.locale

      _ ->
        context.locale
    end
  end

  def report(context, error, message) do
    case Map.get(context, :report) do
      nil -> Logger.error("#{message}: #{inspect(error.__struct__)}")
      fun -> fun.(error, message)
    end
  end
end
