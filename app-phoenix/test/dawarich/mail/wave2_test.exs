defmodule Dawarich.Mail.Wave2Test do
  use ExUnit.Case, async: false

  alias Dawarich.Mail.{ExploreFeatures, Wave2}

  @fixture Path.expand("../../fixtures/wave2/mail.json", __DIR__)
  @email "unit@example.test"
  @secret "wave2-jwt-secret"
  @surfaces ~w(welcome archival_approaching oauth_account_link account_destroy_confirmation
               family_invitation family_lapse family_lapse_cloud)

  setup do
    previous = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)
  end

  defp normalize(text), do: String.replace(text, "\r\n", "\n")

  defp query_token(url),
    do: url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("token")

  defp rails_env(inputs) do
    base = URI.parse(inputs["accept_url_base"])

    %{
      "SMTP_FROM" => "Dawarich <hi@example.test>",
      "MANAGER_URL" => inputs["manager_url"],
      "JWT_SECRET_KEY" => @secret,
      "DOMAIN" => base.host,
      "RAILS_ENV" => if(base.scheme == "http", do: "staging", else: "production")
    }
  end

  defp user(inputs, settings), do: %{email: inputs["user_email"], settings: settings}

  defp build("welcome", inputs, settings, locale, env),
    do: Wave2.welcome(user(inputs, settings), locale, env)

  defp build("archival_approaching", inputs, settings, locale, env),
    do: Wave2.archival_approaching(42, user(inputs, settings), locale, env)

  defp build("oauth_account_link", inputs, settings, locale, env),
    do:
      Wave2.oauth_account_link(
        user(inputs, settings),
        locale,
        inputs["provider_label"],
        inputs["link_url"],
        env
      )

  defp build("account_destroy_confirmation", inputs, settings, locale, env),
    do:
      Wave2.account_destroy_confirmation(user(inputs, settings), locale, inputs["link_url"], env)

  defp build("family_invitation", inputs, _settings, locale, env),
    do:
      Wave2.family_invitation(
        inputs["recipient_email"],
        locale,
        inputs["invitation_token"],
        inputs["family_name"],
        inputs["inviter_email"],
        env
      )

  defp build(lapse, inputs, _settings, locale, env)
       when lapse in ~w(family_lapse family_lapse_cloud),
       do:
         Wave2.family_lapse(
           inputs["user_email"],
           locale,
           inputs["family_name"],
           inputs["owner_email"],
           env
         )

  defp recipient("family_invitation", inputs), do: inputs["recipient_email"]
  defp recipient(_surface, inputs), do: inputs["user_email"]

  defp token("archival_approaching", _inputs, mail) do
    [_, token] = Regex.run(~r/token=([^&\s]+)/, mail.text)
    assert [_, _, _] = String.split(token, ".")
    token
  end

  defp token(_surface, inputs, _mail), do: query_token(inputs["link_url"])

  test "each surface equals the Rails fixture in all seven locales" do
    %{"inputs" => inputs, "messages" => messages} = @fixture |> File.read!() |> Jason.decode!()
    env = rails_env(inputs)

    assert Enum.sort(Map.keys(messages)) == Enum.sort(@surfaces)

    for {surface, by_locale} <- messages do
      assert Enum.sort(Map.keys(by_locale)) == Enum.sort(Dawarich.I18n.available_locales()),
             surface

      assert by_locale |> Map.values() |> Enum.uniq_by(& &1["subject"]) |> length() == 7,
             surface

      System.put_env("SELF_HOSTED", to_string(Map.fetch!(inputs["self_hosted"], surface)))

      for {fixture_locale, expected} <- by_locale do
        settings = Map.fetch!(inputs["recipient_settings"], fixture_locale)
        locale = ExploreFeatures.locale(settings, inputs["job_locale"])
        assert locale == fixture_locale
        label = "#{surface}/#{fixture_locale}"

        assert {:ok, mail} = build(surface, inputs, settings, locale, env)
        token = token(surface, inputs, mail)

        assert mail.subject == expected["subject"], label
        assert mail.from == env["SMTP_FROM"], label
        assert mail.to == recipient(surface, inputs), label

        assert normalize(mail.text) ==
                 normalize(String.replace(expected["text"], "{{token}}", token)),
               label

        assert normalize(mail.html) ==
                 normalize(String.replace(expected["html"], "{{token}}", token)),
               label
      end
    end
  end

  test "archival: the upgrade link carries an HS256 JWT verifiable with JWT_SECRET_KEY and the Rails payload keys in order" do
    System.put_env("SELF_HOSTED", "false")
    env = %{"MANAGER_URL" => "https://manager.example.test", "JWT_SECRET_KEY" => @secret}
    user = %{email: "lite@example.test", settings: %{}}

    assert {:ok, mail} = Wave2.archival_approaching(7, user, "en", env, 1_800_000_000)
    assert [_, url] = Regex.run(~r/Upgrade now: (\S+)/, mail.text)
    assert String.starts_with?(url, "https://manager.example.test/auth/dawarich?token=")

    assert String.ends_with?(
             url,
             "&utm_source=email&utm_medium=email&utm_campaign=archival_approaching&utm_content=upgrade"
           )

    [header, payload, signature] = url |> query_token() |> String.split(".")

    assert Base.url_decode64!(signature, padding: false) ==
             :crypto.mac(:hmac, :sha256, @secret, header <> "." <> payload)

    assert Base.url_decode64!(header, padding: false) == ~s({"alg":"HS256"})

    decoded =
      payload |> Base.url_decode64!(padding: false) |> Jason.decode!(objects: :ordered_objects)

    assert Enum.map(decoded.values, &elem(&1, 0)) == ~w(user_id email purpose jti exp)
    assert decoded["user_id"] == 7
    assert decoded["email"] == "lite@example.test"
    assert decoded["purpose"] == "checkout"
    assert {:ok, _} = Ecto.UUID.cast(decoded["jti"])
    assert decoded["exp"] == 1_800_001_800
  end

  test "a missing JWT_SECRET_KEY or DOMAIN is a build error" do
    user = %{email: @email, settings: %{}}

    assert Wave2.archival_approaching(1, user, "en", %{}) ==
             {:error, "JWT_SECRET_KEY is not set"}

    assert Wave2.family_invitation(@email, "en", "t", "F", "o@example.test", %{}) ==
             {:error, "DOMAIN is not set"}
  end

  test "the invitation accept URL is https on DOMAIN outside staging" do
    assert {:ok, mail} =
             Wave2.family_invitation(@email, "en", "tok", "F", "o@example.test", %{
               "DOMAIN" => "dawarich.example.test",
               "RAILS_ENV" => "production"
             })

    assert mail.text =~ "https://dawarich.example.test/family/invitations/tok"
    assert mail.html =~ ~s(href="https://dawarich.example.test/family/invitations/tok")
  end

  test "bindings of _html keys are escaped, the translation itself is not" do
    assert {:ok, mail} =
             Wave2.oauth_account_link(
               %{email: @email, settings: %{}},
               "en",
               "<b>G&G</b>",
               "u",
               %{}
             )

    assert mail.html =~ "<strong>&lt;b&gt;G&amp;G&lt;/b&gt;</strong> sign-in"
    assert mail.text =~ "link <b>G&G</b> sign-in"
    assert mail.subject == "Confirm linking <b>G&G</b> to your Dawarich account"
  end
end
