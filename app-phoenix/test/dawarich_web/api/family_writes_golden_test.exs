defmodule DawarichWeb.Api.FamilyWritesGoldenTest do
  use Dawarich.ApiEndpointCase

  alias Dawarich.Accounts
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Test.ApiGolden
  alias DawarichWeb.Api.FamilyController

  @golden "test/fixtures/api_family/writes.json" |> File.read!() |> Jason.decode!()
  @tables ~w(users families family_memberships family_location_requests notifications points)
  @written ~w(users family_location_requests notifications)
  @now @golden["now"] |> DateTime.from_iso8601() |> elem(1)
  @http_owned ~w(history_missing_params history_blank_params history_not_in_family
                 sharing_missing_enabled sharing_blank_enabled sharing_not_in_family create_stranger
                 create_deleted_member create_without_target create_not_in_family accept_missing
                 accept_not_target mine_not_in_family decline accept_suggested)

  @events Path.expand("../../../priv/repo/sql/20260928120000_wave2.sql", __DIR__)

  setup do
    if zone = @golden["time_zone"], do: System.put_env("TIME_ZONE", zone)
    Repo.query!(File.read!(@events), [], query_type: :text)
    :ok
  end

  for kase <- @golden["cases"] do
    @kase kase
    test "golden write #{kase["name"]}", %{port: port, upstream: puma} do
      Enum.each(@kase["env"], fn {name, value} -> System.put_env(name, value) end)
      seed(@kase)

      if @kase["expect"] == "rails" or @kase["name"] in @http_owned, do: http!(@kase, port, puma)
      if @kase["expect"] == "own", do: domain!(@kase)
    end
  end

  defp seed(kase) do
    for [table, rows] <- @golden["setups"][kase["setup"]], row <- rows do
      true = table in @tables
      ApiGolden.insert!(table, row)
    end

    for {name, value} <- @golden["sequences"],
        do: Repo.query!("SELECT setval($1::text::regclass, $2, false)", [name, value])
  end

  defp http!(kase, port, puma) do
    before = rows(@tables)
    ApiGolden.check(kase, port, puma)
    if kase["expect"] == "rails", do: assert(rows(@tables) == before)

    for table <- ~w(phoenix.notification_events phoenix.rails_commands) ++ Enum.reverse(@tables),
        do: Repo.query!("DELETE FROM #{table}")

    seed(kase)
  end

  defp domain!(kase) do
    %{"method" => method, "target" => target, "headers" => headers, "body" => body} =
      kase["request"]

    [[_, key]] = for [name, value] <- headers, name == "Authorization", do: [name, value]
    user = Accounts.by_api_key(String.replace_prefix(key, "Bearer ", ""))
    {action, path_params} = action(method, URI.parse(target).path)
    params = query(target) |> Map.merge(body(headers, body)) |> Map.merge(path_params)
    notifications = count("notifications")

    assert {:ok, status, term} = FamilyController.run(action, user, params, @now)

    unordered = kase["unordered"]
    got = term |> Ruby.json() |> IO.iodata_to_binary() |> ApiGolden.normalized(unordered)

    assert {status, got} ==
             {kase["response"]["status"],
              ApiGolden.normalized(kase["response"]["body"], unordered)}

    assert rows(@written) == Map.take(kase["after"], @written)

    mailed =
      for ["ActionMailer::MailDeliveryJob", "FamilyMailer", "location_request", gid] <-
            kase["jobs"],
          do: gid |> String.split("/") |> List.last() |> String.to_integer()

    assert length(mailed) == length(kase["jobs"])

    assert mail_commands() ==
             Enum.map(mailed, &%{"user_id" => user.id, "request_id" => &1})

    assert count("phoenix.notification_events") == count("notifications") - notifications
  end

  defp action("GET", "/api/v1/families/mine"), do: {:mine, %{}}
  defp action("GET", "/api/v1/families/locations/history"), do: {:history, %{}}

  defp action(method, "/api/v1/families/sharing") when method in ~w(PATCH PUT),
    do: {:sharing, %{}}

  defp action("POST", "/api/v1/families/location_requests"), do: {:create, %{}}

  defp action("POST", "/api/v1/families/location_requests/" <> rest) do
    [id, decision] = String.split(rest, "/")
    {String.to_existing_atom(decision), %{"id" => id}}
  end

  defp query(target), do: URI.decode_query(URI.parse(target).query || "")

  defp body(_headers, ""), do: %{}

  defp body(headers, body) do
    if ["Content-Type", "application/json"] in headers,
      do: Jason.decode!(body),
      else: URI.decode_query(body)
  end

  defp rows(tables) do
    Repo.query!("SELECT set_config('TimeZone', 'UTC', true)")

    Map.new(tables, fn table ->
      values =
        Repo.query!("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id").rows
        |> Enum.map(fn [json] -> json |> Jason.decode!() |> Map.reject(&is_nil(elem(&1, 1))) end)

      {table, values}
    end)
  end

  defp mail_commands do
    Repo.query!(
      "SELECT payload FROM phoenix.rails_commands WHERE kind = 'family_location_request_mail' ORDER BY id"
    ).rows
    |> Enum.map(&hd/1)
  end

  defp count(table), do: Repo.query!("SELECT count(*) FROM #{table}").rows |> hd() |> hd()
end
