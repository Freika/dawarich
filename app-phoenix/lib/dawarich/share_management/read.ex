defmodule Dawarich.ShareManagement.Read do
  @moduledoc false

  alias Dawarich.{Repo, UserTimeZone}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @fields "id::text, user_id, resource_type, resource_id, name, magic_phrase, settings, expires_at, revoked_at, created_at, updated_at, view_count, last_accessed_at"
  @keys ~w(id user_id resource_type resource_id name magic_phrase settings expires_at revoked_at created_at updated_at view_count last_accessed_at)a
  @types %{0 => "trip", 1 => "track", 2 => "timeline", 3 => "live"}
  @active "revoked_at IS NULL AND (expires_at IS NULL OR expires_at > $2)"
  @source Path.expand("../../../../config/shared_link_wordlist.txt", __DIR__)
  @external_resource if File.regular?(@source),
                       do: @source,
                       else: Path.expand("../../../priv/shared_link_wordlist.txt", __DIR__)
  @words @external_resource |> File.read!() |> String.split("\n", trim: true)

  def phrase do
    Enum.map_join(1..3, "-", fn _ ->
      index = :crypto.strong_rand_bytes(8) |> :binary.decode_unsigned() |> rem(length(@words))
      Enum.at(@words, index)
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

  def track(user, id, now, locale \\ nil) do
    case Repo.query!(
           "SELECT id,start_at,distance,dominant_mode FROM tracks WHERE user_id=$1 AND id=$2",
           [user.id, id]
         ).rows do
      [[id, start, distance, mode]] ->
        modes =
          ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)

        locale = locale || DawarichWeb.Locale.resolve(nil, user, %{})
        unit = get_in(user.settings, ["maps", "distance_unit"]) || "km"
        factors = %{"km" => 1000, "mi" => 1609.34, "m" => 1, "ft" => 0.3048, "yd" => 0.9144}

        if Map.has_key?(factors, unit) do
          mode_key =
            if is_nil(mode),
              do: "helpers.shared_links.track",
              else: "transportation_modes." <> Enum.at(modes, mode)

          {:ok, mode_name} = Dawarich.I18n.t(locale, mode_key)

          date = UserTimeZone.local(user.settings, start).local |> NaiveDateTime.to_date()
          date = DawarichWeb.LocalizedDate.l(locale, date, "day_month_year_abbreviated")

          {:ok, name} =
            Dawarich.I18n.t(locale, "helpers.shared_links.track_label", %{
              "mode" => mode_name,
              "date" => date,
              "distance" => round((distance || 0) / factors[unit]),
              "unit" => unit
            })

          share =
            links(user, now, "AND resource_type=1 AND resource_id=#{id} ORDER BY id LIMIT 1")
            |> List.first()

          {:ok, %{trip: %{id: id, name: name, type: "track"}, share: share}}
        else
          :rails
        end

      [] ->
        {:error, 404}
    end
  end

  def timeline(user, params, now) do
    {:ok, hub} = hub(user, params, now)
    share = links(user, now, "AND resource_type=2 ORDER BY id LIMIT 1") |> List.first()

    if Enum.all?(
         ~w(start_date end_date),
         &Dawarich.ShareManagement.Params.timeline_date_shape?(params[&1])
       ) and
         (is_nil(share) or
            (is_map(share.settings) and
               Enum.all?(~w(start_date end_date), &(not is_nil(date(share.settings[&1])))))) do
      {:ok, %{trip: nil, share: share, start_date: hub.start_date, end_date: hub.end_date}}
    else
      :rails
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
