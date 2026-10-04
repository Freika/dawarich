defmodule Dawarich.SharedLinks do
  @moduledoc false

  alias Dawarich.Repo

  @canonical ~r/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/
  @api_uuid ~r/\A(?:[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}|[0-9a-f]{32})\z/i
  @types %{0 => "trip", 1 => "track", 2 => "timeline", 3 => "live"}
  @iso_date ~r/\A\d{4}-\d{2}-\d{2}\z/

  @active """
  SELECT s.id::text, s.user_id, s.resource_type, s.name, s.magic_phrase, s.settings, s.expires_at,
    s.resource_id, s.created_at,
    CASE s.resource_type
      WHEN 0 THEN EXISTS (SELECT 1 FROM trips t WHERE t.id = s.resource_id AND t.user_id = s.user_id)
      WHEN 1 THEN EXISTS (SELECT 1 FROM tracks t WHERE t.id = s.resource_id AND t.user_id = s.user_id)
      ELSE false
    END
  FROM shared_links s
  WHERE s.id = $1::text::uuid AND s.revoked_at IS NULL AND (s.expires_at IS NULL OR s.expires_at > $2)
  """

  def canonical?(id), do: is_binary(id) and Regex.match?(@canonical, id)

  def api_uuid?(id), do: is_binary(id) and Regex.match?(@api_uuid, id)

  def active(id, %DateTime{} = now) do
    case Repo.query!(@active, [id, DateTime.to_naive(now)]).rows do
      [[id, user_id, type, name, phrase, settings, expires_at, resource_id, created_at, present]] ->
        %{
          id: id,
          user_id: user_id,
          type: Map.get(@types, type),
          name: name,
          magic_phrase: phrase,
          settings: settings,
          expires_at: expires_at,
          resource_id: resource_id,
          created_at: created_at,
          resource_present: present
        }

      [] ->
        nil
    end
  end

  def touch!(id, %DateTime{} = now),
    do:
      Repo.query!(
        "UPDATE shared_links SET view_count = view_count + 1, last_accessed_at = $2 WHERE id = $1::text::uuid",
        [id, DateTime.to_naive(now)]
      )

  def page(%{type: type, resource_present: false}) when type in ["trip", "track"],
    do: :missing_resource

  def page(%{type: "live"}), do: :live

  def page(%{type: "timeline", settings: settings}) do
    with %{"start_date" => from, "end_date" => to} <- settings,
         {:ok, from} <- iso_date(from),
         {:ok, to} <- iso_date(to),
         true <- Date.compare(from, to) != :gt do
      {:timeline, from, to}
    else
      _ -> :rails
    end
  end

  def page(_link), do: :rails

  defp iso_date(value) when is_binary(value) do
    if Regex.match?(@iso_date, value), do: Date.from_iso8601(value), else: :error
  end

  defp iso_date(_value), do: :error
end
