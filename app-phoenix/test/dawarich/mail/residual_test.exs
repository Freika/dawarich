defmodule Dawarich.Mail.ResidualTest do
  use ExUnit.Case, async: true

  alias Dawarich.Mail.Residual
  alias Dawarich.Test.MailWire

  @fixture Path.expand("../../fixtures/mail/residual/content.json", __DIR__)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
  end

  test "basic residual bodies subjects and part trees equal the Rails corpus" do
    rows =
      @fixture
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> Enum.filter(&(&1["kind"] in ~w(otp_account_locked test_email location_request)))

    expected =
      Enum.flat_map(~w(otp_account_locked test_email location_request), fn kind ->
        ids = for locale <- ~w(en de fallback_fr es fr pl ca zh), do: kind <> "_" <> locale

        if kind == "test_email",
          do: ids ++ ~w(test_email_berlin test_email_invalid_zone),
          else: ids
      end)

    assert Enum.map(rows, & &1["id"]) == expected

    for row <- rows do
      {:ok, now, 0} = DateTime.from_iso8601(row["now"])
      recipient = %{email: row["email"], settings: row["settings"]}
      env = %{"SMTP_FROM" => row["from_header"], "TIME_ZONE" => "Europe/Berlin"}

      surface =
        %{
          "otp_account_locked" => :otp_account_locked,
          "test_email" => :test_email,
          "location_request" => :location_request
        }[row["kind"]]

      message =
        Residual.message(surface, recipient, row["ambient_locale"], env,
          clock: clock(row["settings"], now, env),
          base_url: row["base_url"],
          requester: row["requester"],
          request_id: row["request_id"]
        )

      same(message.subject, row["subject"], "subject", row)
      same(message.to, hd(row["to"]), "recipient", row)
      same(message.from, row["from_header"], "sender", row)
      same(message.locale, row["locale"], "locale", row)
      tree = row["tree"]

      if row["kind"] == "test_email" do
        same(message.format, :html_only, "format", row)
        same(message.html, tree["body"], "HTML", row)
        refute Map.has_key?(message, :text)
      else
        same(message.text, hd(tree["parts"])["body"], "text", row)
        same(message.html, List.last(tree["parts"])["body"], "HTML", row)
      end

      wire = MailWire.phoenix(message)
      same(wire.subject, row["subject"], "wire subject", row)
      same(wire.from, {"Dawarich", hd(row["from"])}, "wire sender", row)
      same(wire.to, {row["email"], row["email"]}, "wire recipient", row)
      same(wire.reply_to, nil, "reply-to", row)

      if row["kind"] == "test_email" do
        same(wire.type, {"text", "html"}, "MIME tree", row)
        same(wire.charset, "utf-8", "charset", row)
        same(normalize(wire.body), tree["body"], "wire HTML", row)
      else
        same(wire.type, {"multipart", "alternative"}, "MIME tree", row)
        same(length(wire.body), 2, "part count", row)

        for {{type, subtype, _headers, params, body}, expected} <-
              Enum.zip(wire.body, tree["parts"]) do
          same(type <> "/" <> subtype, expected["type"], "MIME part", row)
          {_, charset} = List.keyfind(params[:content_type_params], "charset", 0)
          same(String.downcase(charset), "utf-8", "part charset", row)
          same(normalize(body), expected["body"], "wire body", row)
        end
      end
    end
  end

  defp normalize(value), do: String.replace(value, "\r\n", "\n")

  defp clock(settings, now, env) do
    zone = Dawarich.UserTimeZone.zone(settings, env) |> Dawarich.TimeZoneName.to_iana()

    %{rows: [[local, offset, name, valid]]} =
      Dawarich.UserTimeZone.query!(
        """
        SELECT ($1::timestamptz AT TIME ZONE z.name)::timestamp,
               extract(epoch FROM (($1::timestamptz AT TIME ZONE z.name) - ($1::timestamptz AT TIME ZONE 'UTC')))::int,
               z.name, EXISTS(SELECT 1 FROM pg_timezone_names WHERE name = $2) FROM z
        """,
        [now, zone],
        settings,
        env
      )

    %{local: local, offset: offset, zone: name, valid: valid}
  end

  defp same(actual, expected, field, row) do
    if actual != expected, do: flunk("#{field} differs: #{row["id"]}")
  end
end
