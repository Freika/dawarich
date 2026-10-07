defmodule Dawarich.EnhancedImport.State do
  @moduledoc false

  alias Dawarich.RailsEffects

  @now ~S|to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')|
  @merge "additional_data_extraction || jsonb_build_object("

  def load(repo, id) do
    case repo.query!(
           "SELECT id, user_id, source, raw_data FROM imports WHERE id = $1",
           [id],
           log: false
         ).rows do
      [[id, user_id, source, raw_data]] ->
        %{id: id, user_id: user_id, source: source, raw_data: raw_data}

      [] ->
        nil
    end
  end

  def running!(repo, import) do
    payload =
      @merge <> "'started_at', #{started(import)}, 'completed_at', NULL, 'error_message', NULL)"

    write!(repo, import, 2, payload, [], [:card])
  end

  def pending!(repo, import),
    do: write!(repo, import, 1, @merge <> "'started_at', #{started(import)})", [], [])

  def completed!(repo, import, counts) do
    payload = @merge <> "'completed_at', #{@now}, 'counts', $2::jsonb, 'error_message', NULL)"
    write!(repo, import, 3, payload, [counts], [:untracked, :card])
  end

  def retrying!(repo, import, message) do
    payload = @merge <> "'started_at', #{started(import)}, 'error_message', $2::text)"
    write!(repo, import, 1, payload, [message], [:card])
  end

  def failed!(repo, import, message) do
    payload = @merge <> "'completed_at', #{@now}, 'error_message', $2::text)"
    write!(repo, import, 4, payload, [message], [:card, :untracked])
  end

  def reset!(repo, import), do: write!(repo, import, 0, "'{}'::jsonb", [], [:card])

  def destroy_failed!(repo, import, message) do
    payload =
      "COALESCE(additional_data_extraction, '{}'::jsonb) || " <>
        "jsonb_build_object('error_message', 'Removing extracted data failed: ' || $2::text)"

    write!(repo, import, 4, payload, [message], [:card])
  end

  defp write!(repo, import, status, payload, params, kinds) do
    sql =
      "UPDATE imports SET additional_data_extraction_status = #{status}, " <>
        "additional_data_extraction = #{payload} WHERE id = $1"

    effect!(
      repo,
      import,
      fn ->
        repo.query!(sql, [import.id | params], log: false)
        Enum.each(kinds, &kind!(repo, import, &1))
      end,
      status in [0, 3, 4]
    )

    :ok
  end

  def effect!(repo, import, fun, terminal \\ false) do
    case Map.get(import, :fence) do
      fence when is_function(fence, 2) -> fence.(fun, terminal)
      fence when is_function(fence, 1) -> fence.(fun)
      nil ->
        {:ok, result} = repo.transaction(fun)
        result
    end
  end

  defp started(import),
    do:
      if(import[:request_started_at], do: "additional_data_extraction->'started_at'", else: @now)

  defp kind!(repo, import, :card), do: RailsEffects.import_card(repo, import.user_id, import.id)

  defp kind!(repo, import, :untracked),
    do: RailsEffects.untracked_tracks(repo, import.user_id, import.id)
end
