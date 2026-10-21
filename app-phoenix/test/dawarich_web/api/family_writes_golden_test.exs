defmodule DawarichWeb.Api.FamilyWritesGoldenTest do
  use Dawarich.ApiEndpointCase
  @moduletag api_golden: true

  alias Dawarich.Accounts
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Test.ApiGolden
  alias DawarichWeb.Api.FamilyController

  @golden "test/rails_fixtures/api_family/writes.json" |> File.read!() |> Jason.decode!()
  @tables ~w(users families family_memberships family_location_requests notifications points)
  @written @tables
  @outbox ~w(phoenix.rails_commands phoenix.notification_events)
  @now @golden["now"] |> DateTime.from_iso8601() |> elem(1)
  @moduletag api_now: @now
  @events Path.expand("../../../priv/repo/sql/20260928120000_wave2.sql", __DIR__)

  setup do
    if zone = @golden["time_zone"], do: System.put_env("TIME_ZONE", zone)
    Repo.query!(File.read!(@events), [], query_type: :text)
    previous = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", Dawarich.Test.FamilyGoldenResponse.secret())

    on_exit(fn ->
      if previous,
        do: System.put_env("JWT_SECRET_KEY", previous),
        else: System.delete_env("JWT_SECRET_KEY")
    end)

    :ok
  end

  for kase <- @golden["cases"] do
    @kase kase
    test "golden write #{kase["name"]}", %{port: port, upstream: puma} do
      Enum.each(@kase["env"], fn {name, value} -> System.put_env(name, value) end)
      seed(@kase)

      http!(@kase, port, puma)
      if @kase["expect"] == "own", do: domain!(@kase)
    end
  end

  test "a failure after the first write rolls every table back and returns the source error" do
    kase = Enum.find(@golden["cases"], &(&1["name"] == "create_request"))
    seed(kase)
    Repo.query!("DROP TABLE phoenix.notification_events")
    {action, user, params} = prepare(kase)
    tables = @tables ++ ["phoenix.rails_commands"]
    before = rows(tables)

    assert {:ok, 500, {:object, [{"message", "An error occurred"}]}} =
             FamilyController.run(action, user, params, @now)

    assert rows(tables) == before
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
    notifications = count("notifications")
    Dawarich.Test.FamilyGoldenResponse.check(kase, port, puma)

    {action, _params} =
      action(kase["request"]["method"], URI.parse(kase["request"]["target"]).path)

    assert decision_rows(action, kase["response"]["status"]) == kase["after"]
    assert_mail(kase)
    assert count("phoenix.notification_events") == count("notifications") - notifications

    for table <- @outbox ++ Enum.reverse(@tables), do: Repo.query!("DELETE FROM #{table}")

    seed(kase)
  end

  defp prepare(kase) do
    %{"method" => method, "target" => target, "headers" => headers, "body" => body} =
      kase["request"]

    [[_, key]] = for [name, value] <- headers, name == "Authorization", do: [name, value]
    user = Accounts.by_api_key(String.replace_prefix(key, "Bearer ", ""))
    {action, path_params} = action(method, URI.parse(target).path)
    params = query(target) |> Map.merge(body(headers, body)) |> Map.merge(path_params)
    {action, user, params}
  end

  defp domain!(kase) do
    {action, user, params} = prepare(kase)
    notifications = count("notifications")

    assert {:ok, status, term} = FamilyController.run(action, user, params, @now)

    unordered = kase["unordered"]
    got = term |> Ruby.json() |> IO.iodata_to_binary() |> ApiGolden.normalized(unordered)

    assert {status, got} ==
             {kase["response"]["status"],
              ApiGolden.normalized(kase["response"]["body"], unordered)}

    assert decision_rows(action, status) == Map.take(kase["after"], @written)

    assert_mail(kase)

    assert count("phoenix.notification_events") == count("notifications") - notifications
  end

  defp assert_mail(kase) do
    mailed =
      for ["ActionMailer::MailDeliveryJob", "FamilyMailer", "location_request", gid] <-
            kase["jobs"],
          do: gid |> String.split("/") |> List.last() |> String.to_integer()

    assert length(mailed) == length(kase["jobs"])

    expected =
      Enum.map(mailed, fn id ->
        source = Enum.find(kase["after"]["family_location_requests"], &(&1["id"] == id))
        %{"user_id" => source["requester_id"], "request_id" => id}
      end)

    assert mail_commands() == expected
  end

  defp decision_rows(action, status) when action in [:accept, :decline] and status == 200 do
    written = rows(@written)

    [request] =
      Enum.filter(written["family_location_requests"], &Map.has_key?(&1, "responded_at"))

    actual = request["responded_at"]
    at = NaiveDateTime.from_iso8601!(actual)
    expected = DateTime.to_naive(@now)
    assert NaiveDateTime.compare(at, expected) != :lt
    assert NaiveDateTime.diff(at, expected, :microsecond) < 1_000_000

    Map.new(written, fn {table, records} ->
      {table,
       Enum.map(records, fn record ->
         Map.new(record, fn {key, value} ->
           value =
             if key in ~w(responded_at updated_at) and value == actual,
               do: NaiveDateTime.to_iso8601(expected),
               else: value

           {key, value}
         end)
       end)}
    end)
  end

  defp decision_rows(_, _), do: rows(@written)

  defp action("GET", "/api/v1/families/mine"), do: {:mine, %{}}
  defp action("GET", "/api/v1/families/locations/history"), do: {:history, %{}}

  defp action(method, "/api/v1/families/sharing") when method in ~w(PATCH PUT),
    do: {:sharing, %{}}

  defp action("POST", "/api/v1/families/location_requests"), do: {:create, %{}}

  defp action("POST", "/api/v1/families/location_requests/" <> rest) do
    [id, decision] = String.split(rest, "/")
    {String.to_existing_atom(decision), %{"id" => id}}
  end

  defp action(_, _), do: {:other, %{}}

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
