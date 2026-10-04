defmodule Dawarich.Auth.AdmissionTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.Admission

  test "special session, mobile, OIDC and cloud requests hand back before authentication" do
    assert Admission.context(%{}, [], false, true) == :ok

    assert {:handoff, :duplicate_headers} =
             Admission.context(%{}, [{"cookie", "one"}, {"cookie", "two"}], false, true)

    for key <- ~w(invitation_token pending_import_ticket dawarich_client) do
      assert {:handoff, :special_session} = Admission.context(%{key => "ticket"}, [], false, true)
    end

    assert {:handoff, :mobile} =
             Admission.context(%{}, [{"x-dawarich-client", "ios"}], false, true)

    for header <- ["x-forwarded-for", "client-ip", "forwarded"] do
      assert {:handoff, :client_ip} = Admission.context(%{}, [{header, "1.2.3.4"}], false, true)
    end

    assert {:handoff, :method_override} =
             Admission.context(%{}, [{"x-http-method-override", "DELETE"}], false, true)

    assert {:handoff, :oidc} = Admission.context(%{}, [], true, true)
    assert {:handoff, :cloud} = Admission.context(%{}, [], false, false)
  end

  test "Rails hidden unchecked checkbox plus checked value is accepted; ambiguous credentials are not" do
    assert {:ok, %{"user[remember_me]" => "1", "user[email]" => "a+b@test"}} =
             Admission.form(
               "user%5Bremember_me%5D=0&user%5Bremember_me%5D=1&user%5Bemail%5D=a%2Bb%40test",
               ""
             )

    assert {:handoff, :duplicate_parameters} =
             Admission.form("user%5Bemail%5D=a&user%5Bemail%5D=b", "")

    assert {:handoff, :parameters} = Admission.form("invitation_token=t", "")
    assert {:handoff, :parameters} = Admission.form("user%5Bemail%5D=a", "locale=de")
    assert {:handoff, :parameters} = Admission.form("user%5Bemail%5D=%FF", "")
    assert {:handoff, :parameters} = Admission.form("user%5Bemail%5D=%ZZ", "")

    for value <- ~w(on t true yes) do
      assert {:handoff, :parameters} = Admission.form("user%5Bremember_me%5D=#{value}", "")
    end

    assert {:ok, %{"user[remember_me]" => "0"}} = Admission.form("user%5Bremember_me%5D=0", "")
  end

  test "oidc?/1 is Rails' OIDC/Google switch" do
    refute Admission.oidc?(%{})

    assert Admission.oidc?(%{
             "GOOGLE_OAUTH_CLIENT_ID" => "g",
             "GOOGLE_OAUTH_CLIENT_SECRET" => "s"
           })

    refute Admission.oidc?(%{
             "GOOGLE_OAUTH_CLIENT_ID" => "g",
             "GOOGLE_OAUTH_CLIENT_SECRET" => " "
           })

    assert Admission.oidc?(%{"OIDC_CLIENT_ID" => "o", "OIDC_CLIENT_SECRET" => "s"})
    assert Admission.oidc?(%{"OIDC_CLIENT_ID" => "o", "OIDC_PKCE_ENABLED" => " TRUE "})
    refute Admission.oidc?(%{"OIDC_CLIENT_ID" => "o", "OIDC_PKCE_ENABLED" => "yes"})
  end
end
