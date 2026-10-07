defmodule Dawarich.Admin.UsersPage do
  @moduledoc false

  alias Dawarich.{Repo, TripSettings, UserTimeZone}
  alias Dawarich.Auth.RegistrationSetting
  alias DawarichWeb.TripsGate

  @page_size 25
  @max_page div(9_223_372_036_854_775_807, @page_size)
  @relation "deleted_at IS NULL AND email ILIKE $1 ESCAPE chr(92)"
  @list_fields "id, email, admin, status, points_count, last_sign_in_at, created_at"
  @show_fields @list_fields <>
                 ", settings, api_key, sign_in_count, last_sign_in_ip, current_sign_in_ip"

  def list(actor, query) do
    with true <- supported?(actor),
         true <- scalar?(query["search"]) and scalar?(query["page"]),
         page = TripsGate.page_number(query["page"]),
         true <- page <= @max_page,
         pattern = pattern(query["search"]),
         true <- Dawarich.Standalone.enabled?() or not ties?(pattern),
         {:ok, registration} <- registration() do
      [[count]] =
        Repo.query!("SELECT count(*) FROM users WHERE " <> @relation, [pattern], log: false).rows

      rows =
        rows(
          "SELECT #{@list_fields} FROM users WHERE #{@relation} ORDER BY created_at DESC LIMIT #{@page_size} OFFSET $2",
          [pattern, (page - 1) * @page_size]
        )

      if Enum.all?(rows, &displayable?/1) do
        {:ok,
         %{
           rows: Enum.map(rows, &dates(&1, Dawarich.UserSettings.get(actor))),
           page: page,
           pages: ceil(count / @page_size),
           total: count,
           registration: registration,
           search: query["search"]
         }}
      else
        :rails
      end
    else
      _ -> :rails
    end
  rescue
    _ -> :rails
  end

  def find(actor, id, kind) when is_integer(id) and id > 0 and kind in [:show, :edit] do
    if supported?(actor) do
      columns = if kind == :show, do: @show_fields, else: "id, email, admin, status"

      case rows("SELECT #{columns} FROM users WHERE id = $1 AND deleted_at IS NULL", [id]) do
        [target] -> detail(actor, target, kind)
        _ -> :rails
      end
    else
      :rails
    end
  rescue
    _ -> :rails
  end

  def find(_actor, _id, _kind), do: :rails

  defp detail(_actor, %{status: status} = target, :edit) when status in 0..3, do: {:ok, target}

  defp detail(actor, target, :show) do
    if displayable?(target) and is_binary(target.api_key) and String.length(target.api_key) >= 8 do
      zone_settings = Dawarich.UserSettings.get(actor)

      [[tracks, imports, exports, areas]] =
        Repo.query!(
          "SELECT (SELECT count(*) FROM tracks WHERE user_id = $1), (SELECT count(*) FROM imports WHERE user_id = $1), (SELECT count(*) FROM exports WHERE user_id = $1), (SELECT count(*) FROM areas WHERE user_id = $1)",
          [target.id],
          log: false
        ).rows

      target = target |> Map.delete(:settings) |> dates(zone_settings)

      {:ok,
       Map.put(target, :counts, %{
         "tracks" => tracks,
         "imports" => imports,
         "exports" => exports,
         "areas" => areas
       })}
    else
      :rails
    end
  end

  defp detail(_actor, _target, _kind), do: :rails

  defp registration do
    case RegistrationSetting.fetch() do
      {:ok, value} when is_boolean(value) -> {:ok, value}
      _ -> :rails
    end
  end

  defp ties?(pattern) do
    [[ties]] =
      Repo.query!(
        "SELECT EXISTS(SELECT 1 FROM users WHERE #{@relation} GROUP BY created_at HAVING count(*) > 1)",
        [pattern],
        log: false
      ).rows

    ties
  end

  defp supported?(user) do
    settings = Dawarich.UserSettings.get(user)

    with {:ok, _} <- TripSettings.read(settings) do
      zone = settings["timezone"] || System.get_env("TIME_ZONE", "Europe/Berlin")
      TripSettings.zone?(%{"timezone" => zone}, UserTimeZone.name(settings))
    else
      _ -> false
    end
  end

  defp scalar?(value), do: is_nil(value) or is_binary(value)

  defp pattern(search) when search in [nil, ""], do: "%"

  defp pattern(search) do
    if String.trim(search) == "" do
      "%"
    else
      "%" <> String.replace(search, ["\\", "%", "_"], fn char -> "\\" <> char end) <> "%"
    end
  end

  defp rows(sql, params) do
    %{columns: columns, rows: rows} = Repo.query!(sql, params, log: false)
    names = Enum.map(columns, &String.to_atom/1)
    Enum.map(rows, &Map.new(Enum.zip(names, &1)))
  end

  defp displayable?(row) do
    row.status in 0..3 and match?(%NaiveDateTime{}, row.created_at) and
      (is_nil(row.last_sign_in_at) or match?(%NaiveDateTime{}, row.last_sign_in_at))
  end

  defp dates(row, settings) do
    %{
      row
      | created_at: UserTimeZone.local(settings, row.created_at),
        last_sign_in_at: row.last_sign_in_at && UserTimeZone.local(settings, row.last_sign_in_at)
    }
  end
end
