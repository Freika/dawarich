defmodule Dawarich.ShareManagement.Read do
  @moduledoc false

  alias Dawarich.{Repo, UserTimeZone}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @fields "id::text, user_id, resource_type, resource_id, name, magic_phrase, settings, expires_at, revoked_at, created_at, updated_at, view_count, last_accessed_at"
  @keys ~w(id user_id resource_type resource_id name magic_phrase settings expires_at revoked_at created_at updated_at view_count last_accessed_at)a
  @types %{0 => "trip", 1 => "track", 2 => "timeline", 3 => "live"}
  @active "revoked_at IS NULL AND (expires_at IS NULL OR expires_at > $2)"

  def phrase do
    root = Application.get_env(:dawarich, :rails_root, Path.expand("../..", File.cwd!()))

    words =
      root
      |> Path.join("config/shared_link_wordlist.txt")
      |> File.read!()
      |> String.split("\n", trim: true)

    Enum.map_join(1..3, "-", fn _ ->
      index = :crypto.strong_rand_bytes(8) |> :binary.decode_unsigned() |> rem(length(words))
      Enum.at(words, index)
    end)
  end

  def hub(user, params, now) do
    shares = links(user, now, "ORDER BY created_at DESC")

    today =
      UserTimeZone.local(user.settings, DateTime.to_naive(now)).local |> NaiveDateTime.to_date()

    tab = if Ruby.blank?(params["tab"]), do: "live", else: params["tab"]

    {:ok,
     %{
       shares: shares,
       live: Enum.find(shares, &(&1.type == "live")),
       timeline: Enum.find(shares, &(&1.type == "timeline")),
       tab: if(tab == "shared" and shares == [], do: "live", else: tab),
       start_date: date(params["start_date"]) || Date.add(today, -7),
       end_date: date(params["end_date"]) || today
     }}
  end

  def live(user, now),
    do:
      {:ok,
       %{
         trip: nil,
         share: links(user, now, "AND resource_type = 3 ORDER BY id LIMIT 1") |> List.first()
       }}

  def trip(user, id, now) do
    case Repo.query!("SELECT id, name FROM trips WHERE user_id = $1 AND id = $2", [user.id, id]).rows do
      [[id, name]] ->
        share =
          links(user, now, "AND resource_type = 0 AND resource_id = #{id} ORDER BY id LIMIT 1")
          |> List.first()

        {:ok, %{trip: %{id: id, name: name}, share: share}}

      [] ->
        {:error, 404}
    end
  end

  def owned(user, id) do
    if Dawarich.SharedLinks.canonical?(id) do
      case Repo.query!(
             "SELECT #{@fields} FROM shared_links WHERE user_id = $1 AND id = $2::text::uuid",
             [user.id, id]
           ).rows do
        [values] -> {:ok, %{share: row(values), trip: nil}}
        [] -> {:error, 404}
      end
    else
      :rails
    end
  end

  defp links(user, now, suffix) do
    Repo.query!(
      "SELECT #{@fields} FROM shared_links WHERE user_id = $1 AND #{@active} #{suffix}",
      [user.id, DateTime.to_naive(now)]
    ).rows
    |> Enum.map(&row/1)
  end

  defp row(values) do
    link = Map.new(Enum.zip(@keys, values))
    Map.put(link, :type, Map.fetch!(@types, link.resource_type))
  end

  defp date(raw) when is_binary(raw) do
    case Date.from_iso8601(raw) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp date(_raw), do: nil
end
