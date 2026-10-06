defmodule Dawarich.EnhancedImport.PlaceWriter do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.RubyDecimal

  @columns "SELECT id, geodata, name_locked_at IS NOT NULL FROM"
  @by_external @columns <>
                 " places WHERE user_id = $1 AND geodata ->> 'external_place_id' = ANY($2)"
  @renamed "WITH near AS MATERIALIZED (SELECT id, user_id, source, geodata, name_locked_at FROM places " <>
             "WHERE ST_DWithin(lonlat::geography, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, 1)) " <>
             @columns <> " near WHERE user_id = $1 AND source = 2 LIMIT 10"
  @nearby "WITH near AS MATERIALIZED (SELECT id, user_id, name, lonlat, geodata, name_locked_at FROM places " <>
            "WHERE ST_DWithin(lonlat::geography, ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography, 75)) " <>
            @columns <>
            " near WHERE user_id = $1 AND LOWER(name) = $2 ORDER BY lonlat::geography <-> " <>
            "ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography LIMIT 1"
  @adopt "UPDATE places SET geodata = geodata || jsonb_build_object('external_place_id', $2::text), " <>
           "updated_at = now()"
  @insert """
  INSERT INTO places (user_id, import_id, name, latitude, longitude, lonlat, source, geodata, created_at, updated_at)
  VALUES ($1, $2, $3, $4::text::numeric, $5::text::numeric,
          ST_SetSRID(ST_MakePoint($5::text::numeric::float8, $4::text::numeric::float8), 4326)::geography,
          $7, $6, now(), now())
  ON CONFLICT DO NOTHING RETURNING id
  """
  @tag "SELECT id, privacy_radius_meters FROM tags WHERE user_id = $1 AND LOWER(tags.name) = $2 ORDER BY id LIMIT 1"
  @create_tag "INSERT INTO tags (user_id, name, color, demo, created_at, updated_at) " <>
                "VALUES ($1, $2, $3, false, now(), now()) ON CONFLICT (user_id, name) DO NOTHING " <>
                "RETURNING id, privacy_radius_meters"
  @attach "INSERT INTO taggings (tag_id, taggable_type, taggable_id, created_at, updated_at) " <>
            "VALUES ($1, 'Place', $2, now(), now()) ON CONFLICT (taggable_type, taggable_id, tag_id) DO NOTHING"

  def new(%{id: import_id, user_id: user_id} = import),
    do: %{
      user_id: user_id,
      import_id: import_id,
      claimed: MapSet.new(),
      tags: %{},
      known: %{},
      count: 0,
      last_id: nil,
      source: if(Map.get(import, :source, 4) == 4, do: 2, else: 1)
    }

  def prefetch(repo, state, places) do
    ids = places |> Enum.map(& &1.external_place_id) |> Enum.uniq()
    rows = query(repo, @by_external, [state.user_id, ids])

    found =
      Map.new(rows, fn [_id, geodata, _locked] = row -> {geodata["external_place_id"], row} end)

    %{state | known: Map.merge(Map.new(ids, &{&1, nil}), found)}
  end

  def upsert(repo, state, place) do
    {:ok, state} = repo.transaction(fn -> write(repo, state, place) end)
    state
  end

  defp write(repo, state, place) do
    case find(repo, state, place) do
      {kind, [id | _] = row} ->
        state = adopt(repo, state, kind, row, place)
        found(repo, state, id, place)

      nil ->
        insert(repo, state, place)
    end
  end

  defp find(repo, state, place) do
    cond do
      row = by_external(repo, state, place) -> {:existing, row}
      row = state.source == 2 && renamed(repo, state, place) -> {:renamed, row}
      row = nearby(repo, state, place) -> {:existing, row}
      true -> nil
    end
  end

  defp by_external(repo, state, place) do
    case Map.fetch(state.known, place.external_place_id) do
      {:ok, row} -> row
      :error -> fetch_external(repo, state, place)
    end
  end

  defp fetch_external(repo, state, place),
    do: one(repo, @by_external, [state.user_id, [place.external_place_id]])

  defp renamed(repo, state, place) do
    rows = query(repo, @renamed, [state.user_id, place.longitude, place.latitude])

    case length(rows) < 10 && Enum.reject(rows, &MapSet.member?(state.claimed, hd(&1))) do
      [row] -> row
      _ -> nil
    end
  end

  defp nearby(_repo, _state, %{name: nil}), do: nil

  defp nearby(repo, state, place),
    do:
      one(repo, @nearby, [
        state.user_id,
        String.downcase(place.name),
        place.longitude,
        place.latitude
      ])

  defp adopt(repo, state, :renamed, [id, _geodata, locked] = row, place) do
    {set, params} =
      if locked,
        do: {"", [id, place.external_place_id]},
        else: {", name = $3", [id, place.external_place_id, place_name(place.name)]}

    repo |> savepoint(@adopt <> set <> " WHERE id = $1", params) |> adopted(state, row, place)
  end

  defp adopt(repo, state, :existing, [id, geodata, _locked] = row, place) do
    if Ruby.blank?(geodata["external_place_id"]),
      do:
        repo
        |> savepoint(@adopt <> " WHERE id = $1", [id, place.external_place_id])
        |> adopted(state, row, place),
      else: state
  end

  defp adopted(:conflict, state, _row, _place), do: state

  defp adopted(:ok, state, [id, geodata, locked], place) do
    old = geodata["external_place_id"]
    known = with %{^old => [^id | _]} <- state.known, do: %{state.known | old => nil}
    geodata = Map.put(geodata, "external_place_id", place.external_place_id)
    remember(%{state | known: known}, place, [id, geodata, locked])
  end

  defp remember(state, place, row),
    do: %{state | known: Map.replace(state.known, place.external_place_id, row)}

  defp insert(repo, state, place) do
    geodata =
      if place.semantic_type,
        do: %{
          "external_place_id" => place.external_place_id,
          "semantic_type" => place.semantic_type
        },
        else: %{"external_place_id" => place.external_place_id}

    params = [
      state.user_id,
      state.import_id,
      place_name(place.name),
      RubyDecimal.column(place.latitude, 10, 6),
      RubyDecimal.column(place.longitude, 10, 6),
      geodata,
      state.source
    ]

    case query(repo, @insert, params) do
      [[id]] ->
        found(repo, remember(state, place, [id, geodata, false]), id, place)

      [] ->
        case fetch_external(repo, state, place) do
          [id | _] = row -> found(repo, remember(state, place, row), id, place)
          nil -> state
        end
    end
  end

  defp found(repo, state, id, place) do
    state = %{state | claimed: MapSet.put(state.claimed, id), count: state.count + 1, last_id: id}
    attach_tag(repo, state, id, place)
  end

  defp attach_tag(_repo, state, _place_id, %{tag_name: nil}), do: state

  defp attach_tag(repo, state, place_id, place) do
    state =
      case existing_tag(repo, state, place.tag_name) do
        {nil, state} -> create_tag(repo, state, place)
        {_tag, state} -> state
      end

    case state.tags[String.downcase(place.tag_name)] do
      [tag_id, nil] -> query(repo, @attach, [tag_id, place_id])
      _nil_or_privacy_zone -> :ok
    end

    state
  end

  defp existing_tag(repo, state, name) do
    key = String.downcase(name)

    case Map.fetch(state.tags, key) do
      {:ok, tag} ->
        {tag, state}

      :error ->
        tag = one(repo, @tag, [state.user_id, key])
        {tag, %{state | tags: Map.put(state.tags, key, tag)}}
    end
  end

  defp create_tag(repo, state, place) do
    key = String.downcase(place.tag_name)

    case query(repo, @create_tag, [state.user_id, place.tag_name, place.tag_color]) do
      [tag] ->
        %{state | tags: Map.put(state.tags, key, tag)}

      [] ->
        {_tag, state} = existing_tag(repo, %{state | tags: Map.delete(state.tags, key)}, key)
        state
    end
  end

  defp place_name(name) do
    cond do
      not Ruby.present?(name) ->
        "Unknown"

      length(String.codepoints(name)) > 255 ->
        Enum.join(Enum.take(String.codepoints(name), 252)) <> "..."

      true ->
        name
    end
  end

  defp savepoint(repo, sql, params) do
    repo.query!("SAVEPOINT place_adopt", [], log: false)

    try do
      repo.query!(sql, params, log: false)
      repo.query!("RELEASE SAVEPOINT place_adopt", [], log: false)
      :ok
    rescue
      error in Postgrex.Error ->
        if error.postgres[:code] != :unique_violation, do: reraise(error, __STACKTRACE__)
        repo.query!("ROLLBACK TO SAVEPOINT place_adopt", [], log: false)
        repo.query!("RELEASE SAVEPOINT place_adopt", [], log: false)
        :conflict
    end
  end

  defp one(repo, sql, params) do
    case query(repo, sql, params) do
      [row | _] -> row
      [] -> nil
    end
  end

  defp query(repo, sql, params), do: repo.query!(sql, params, log: false).rows
end
