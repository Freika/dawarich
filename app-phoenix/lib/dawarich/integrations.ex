defmodule Dawarich.Integrations do
  @moduledoc false

  alias Dawarich.{UserSettings, UserTimeZone}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.LocalizedDate

  @services ~w(immich photoprism airtrail teslamate trek)
  @statuses %{0 => "active", 1 => "disabled"}

  def services, do: @services

  def service(service) when service in @services, do: service
  def service(_service), do: "immich"

  def trek_sources(user) do
    %{rows: rows} =
      UserTimeZone.query!(
        """
        SELECT t.id, t.base_url, t.importing, t.last_error, t.status,
               (t.last_synced_at AT TIME ZONE 'UTC' AT TIME ZONE z.name)
        FROM trip_sources t, z
        WHERE t.user_id = $1 AND t.provider = 'trek'
        ORDER BY t.created_at
        """,
        [user.id],
        Dawarich.UserSettings.get(user)
      )

    for [id, base_url, importing, last_error, status, synced] <- rows do
      %{
        id: id,
        base_url: base_url,
        importing: importing,
        last_error: last_error,
        status: @statuses[status],
        active: status == 0,
        synced: synced && NaiveDateTime.truncate(synced, :second)
      }
    end
  end

  def statuses(user, sources) do
    settings = UserSettings.get(user)
    Map.new(@services, &{&1, status(&1, settings, sources)})
  end

  defp status("trek", _settings, sources),
    do: if(Enum.any?(sources, & &1.active), do: "connected")

  defp status("teslamate", settings, _sources),
    do:
      if(Ruby.present?(settings["teslamate_url"]),
        do: connection(settings["teslamate_connection_status"])
      )

  defp status(service, settings, _sources) do
    if Ruby.present?(settings[service <> "_url"]) and
         Ruby.present?(settings[service <> "_api_key"]),
       do: connection(settings[service <> "_connection_status"])
  end

  defp connection("ok"), do: "connected"
  defp connection("failed"), do: "failed"
  defp connection(_status), do: nil

  def synced_text(locale, user, key) do
    value = UserSettings.value(user, key)

    cond do
      not Ruby.present?(value) -> nil
      not is_binary(value) -> to_string(value)
      true -> format(locale, user, value)
    end
  end

  defp format(locale, user, value) do
    case local(user, value) do
      %NaiveDateTime{} = local -> LocalizedDate.time(locale, local, "long")
      nil -> value
    end
  end

  defp local(user, value) do
    with {:error, _} <- DateTime.from_iso8601(value),
         {:error, _} <- NaiveDateTime.from_iso8601(value),
         {:error, _} <- Date.from_iso8601(value) do
      nil
    else
      {:ok, %DateTime{} = at, _offset} ->
        UserTimeZone.local(UserSettings.get(user), DateTime.to_naive(at)).local

      {:ok, %NaiveDateTime{} = local} ->
        local

      {:ok, %Date{} = date} ->
        NaiveDateTime.new!(date, ~T[00:00:00])
    end
  end
end
