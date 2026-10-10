defmodule DawarichWeb.NativeTwoFactorDocumentTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import ExUnit.CaptureLog
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint
  @path "/settings/two_factor"

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    env = %{
      "DAWARICH_RAILS" => "off",
      "SELF_HOSTED" => "true",
      "FORCE_SSL" => "false",
      "OTP_ENCRYPTION_PRIMARY_KEY" => "synthetic-primary",
      "OTP_ENCRYPTION_DETERMINISTIC_KEY" => "synthetic-deterministic",
      "OTP_ENCRYPTION_KEY_DERIVATION_SALT" => "synthetic-salt"
    }

    old = Map.new(env, fn {k, _} -> {k, System.get_env(k)} end)
    System.put_env(env)

    on_exit(fn ->
      for {k, v} <- old, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    Dawarich.State.put_registration_enabled(Repo, true)

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "native-2fa@example.test",
        api_key: "synthetic",
        admin: true,
        settings: %{"onboarding_completed" => true}
      })

    %{actor: actor, session: RailsUser.session(actor.id, %{"locale" => "de"})}
  end

  defp submit(session, path, fields \\ %{}) do
    fields =
      Map.put(fields, "authenticity_token", RailsCsrf.masked_form_token(session, path, "POST"))

    RailsFormRequests.post_form(session, URI.encode_query(fields), [], path)
  end

  defp private?(response),
    do: Enum.any?([:secret, :uri, :codes, :render, :qr_svg], &Map.has_key?(response.assigns, &1))

  test "setup secret and backup codes exist only in authorized response rendering", c do
    log =
      capture_log(fn ->
        setup = submit(c.session, @path)
        assert setup.status == 200
        assert setup.resp_body =~ "/native/auth_http.js"
        refute private?(setup)

        {:ok, secret} =
          Dawarich.Auth.TwoFactor.Secret.decrypt(
            Repo.get!(Dawarich.Auth.Account, c.actor.id).otp_secret
          )

        assert String.contains?(setup.resp_body, secret)

        verified =
          submit(c.session, @path <> "/verify", %{
            "otp_attempt" =>
              Dawarich.Auth.TwoFactor.Totp.at(secret, DateTime.to_unix(DateTime.utc_now()))
          })

        assert verified.status == 200
        refute private?(verified)
        nodes = LazyHTML.query(LazyHTML.from_document(verified.resp_body), "code")
        assert Enum.count(nodes) == 10

        for node <- nodes do
          assert byte_size(String.trim(LazyHTML.text(node))) > 0
          refute Enum.any?(LazyHTML.attribute(node, "class"), &String.contains?(&1, "truncate"))
        end

        assert Repo.get!(Dawarich.Auth.Account, c.actor.id).otp_required_for_login
      end)

    refute log =~ "otpauth://"
    refute log =~ "otp_backup_codes"
  end

  test "verify failure replaces inherited alert and clears attempted code", c do
    assert submit(c.session, @path).status == 200

    inherited =
      Map.put(c.session, "flash", %{
        "discard" => [],
        "flashes" => %{"alert" => "synthetic-old-alert"}
      })

    failed = submit(inherited, @path <> "/verify", %{"otp_attempt" => "synthetic-attempt"})
    assert failed.status == 422
    assert failed.resp_body =~ "/native/auth_http.js"
    refute failed.resp_body =~ "synthetic-attempt"
    refute failed.resp_body =~ "synthetic-old-alert"
    refute private?(failed)

    assert Enum.count(
             LazyHTML.query(LazyHTML.from_document(failed.resp_body), "[data-auth-error-summary]")
           ) == 1
  end

  test "HTTP self 2FA renders fresh ordinary navigation after admin demotion", c do
    Repo.query!("UPDATE users SET admin=false WHERE id=$1", [c.actor.id], log: false)

    page =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
      |> get(@path)

    assert page.status == 200
    assert page.resp_body =~ "/native/auth_http.js"
    dom = LazyHTML.from_document(page.resp_body)

    assert Enum.count(LazyHTML.query(dom, "a[aria-current=page][href='/settings/two_factor']")) ==
             1

    assert Enum.empty?(LazyHTML.query(dom, "a[href='/admin/settings']"))
    assert Enum.count(LazyHTML.query(dom, "form[action='/users/sign_out'][data-auth-form]")) >= 1
  end
end
