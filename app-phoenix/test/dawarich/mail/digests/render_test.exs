defmodule Dawarich.Mail.Digests.RenderTest do
  use Dawarich.JobsCase

  alias Dawarich.{DigestFixtures, ScratchRepo}
  alias Dawarich.Mail.Digests.Render
  alias Dawarich.Test.MailWire

  @path Path.expand("../../../fixtures/mail/residual/digest_content.json", __DIR__)
  @ids ~w(monthly_km monthly_mi monthly_default monthly_de monthly_ambient_fr monthly_empty
          monthly_equal monthly_leap_invalid_days monthly_threshold monthly_nil_json monthly_negative
          monthly_malformed_distances monthly_malformed_locations monthly_malformed_visits
          monthly_invalid_month yearly_km yearly_mi yearly_default yearly_de yearly_ambient_fr
          yearly_empty yearly_shared yearly_sharing_disabled yearly_sparse_stats yearly_nil_json
          yearly_negative yearly_malformed_stats) ++
         for(
           period <- ~w(monthly yearly),
           locale <- ~w(es fr pl ca zh),
           do: period <> "_" <> locale
         )
  @now "2026-10-04T12:00:00Z"

  test "monthly and yearly digest messages equal every Rails content row" do
    cases = @path |> File.read!() |> Jason.decode!() |> Map.fetch!("cases")
    assert Enum.map(cases, & &1["id"]) == @ids

    for row <- cases do
      rows("TRUNCATE public.digests, public.stats, public.users CASCADE")
      load(row)
      user = %{id: row["user_id"], email: row["email"], settings: row["settings"]}
      env = %{"SMTP_FROM" => row["from_header"]}

      render = fn ->
        Render.message(
          ScratchRepo,
          user,
          row["digest"],
          row["ambient_locale"],
          env,
          row["base_url"]
        )
      end

      if row["error"] do
        error =
          if row["error"]["class"] == "TypeError",
            do: Dawarich.ReleaseMigrations.Effects.Support.Ruby.Error,
            else: ArgumentError

        assert_raise error, render
      else
        message = render.()
        same(message.subject, row["subject"], "subject", row)
        same(message.to, hd(row["to"]), "recipient", row)
        same(message.from, row["from_header"], "sender", row)
        same(message.locale, row["locale"], "locale", row)
        same(message.text, hd(row["tree"]["parts"])["body"], "text", row)
        same(message.html, List.last(row["tree"]["parts"])["body"], "HTML", row)
        wire = MailWire.phoenix(message)
        same(wire.subject, row["subject"], "wire subject", row)
        same(wire.from, {"Dawarich", hd(row["from"])}, "wire sender", row)
        same(wire.to, {row["email"], row["email"]}, "wire recipient", row)
        same(wire.reply_to, nil, "reply-to", row)
        same(wire.type, {"multipart", "alternative"}, "MIME tree", row)
        same(length(wire.body), 2, "part count", row)

        for {{type, subtype, _headers, params, body}, expected} <-
              Enum.zip(wire.body, row["tree"]["parts"]) do
          same(type <> "/" <> subtype, expected["type"], "MIME part", row)
          {_, charset} = List.keyfind(params[:content_type_params], "charset", 0)
          same(String.downcase(charset), "utf-8", "charset", row)
          same(String.replace(body, "\r\n", "\n"), expected["body"], "wire body", row)
        end
      end
    end
  end

  defp load(row) do
    users = Enum.uniq([row["user_id"] | Enum.map(row["stats"], & &1["user_id"])])

    for id <- users do
      DigestFixtures.row!(ScratchRepo, "users", %{
        "id" => id,
        "email" => if(id == row["user_id"], do: row["email"], else: "foreign-digest@test"),
        "settings" => row["settings"],
        "created_at" => @now,
        "updated_at" => @now
      })
    end

    digest =
      row["digest"]
      |> Map.put("period_type", if(row["period"] == "monthly", do: 0, else: 1))
      |> Map.merge(%{"created_at" => @now, "updated_at" => @now})

    DigestFixtures.row!(ScratchRepo, "digests", digest)

    for stat <- row["stats"] do
      stat = Map.merge(stat, %{"distance" => 0, "created_at" => @now, "updated_at" => @now})
      DigestFixtures.row!(ScratchRepo, "stats", stat)
    end
  end

  defp same(actual, expected, field, row) do
    if actual != expected do
      detail =
        if is_binary(actual) and is_binary(expected), do: difference(actual, expected), else: ""

      flunk("#{field} differs: #{row["id"]}" <> detail)
    end
  end

  defp difference(actual, expected) do
    pairs = Enum.zip(String.codepoints(actual), String.codepoints(expected))
    index = Enum.find_index(pairs, fn {a, b} -> a != b end) || length(pairs)
    {a, b} = Enum.at(pairs, index, {nil, nil})
    line = actual |> String.codepoints() |> Enum.take(index) |> Enum.count(&(&1 == "\n"))

    " at line #{line + 1}, character #{index}, #{kind(a)}/#{kind(b)}; lengths #{byte_size(actual)}/#{byte_size(expected)}"
  end

  defp kind("\n"), do: "newline"
  defp kind(" "), do: "space"
  defp kind(nil), do: "end"
  defp kind(_), do: "content"
end
