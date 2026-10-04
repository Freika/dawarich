defmodule Dawarich.Auth.AdmissionTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.Admission

  test "account field lists do not widen credential admission" do
    fields =
      ~w(authenticity_token user[email] user[password] user[password_confirmation] user[current_password] commit utf8 _method)

    keys = ~w(authenticity_token commit utf8)

    raw =
      "user%5Bemail%5D=a%2Bb%40test&user%5Bcurrent_password%5D=old&user%5Bpassword_confirmation%5D=new%26value&_method=put"

    assert {:ok,
            %{
              "user[email]" => "a+b@test",
              "user[current_password]" => "old",
              "user[password_confirmation]" => "new&value",
              "_method" => "put"
            }} = Admission.form(raw, "", fields)

    assert {:handoff, :parameters} = Admission.form(raw, "")
    assert {:handoff, :parameters} = Admission.form("user%5Bcurrent_password%5D=old", "")
    assert {:handoff, :parameters} = Admission.form("user%5Bpassword_confirmation%5D=new", "")
    assert {:ok, %{}} = Admission.form("", "", keys)

    assert {:ok, %{"authenticity_token" => "token"}} =
             Admission.form("authenticity_token=token", "", keys)

    assert {:handoff, :parameters} = Admission.form("user%5Bemail%5D=a", "", keys)

    for duplicate <- [
          "user%5Bemail%5D=a&user%5Bemail%5D=b",
          "user%5Bcurrent_password%5D=a&user%5Bcurrent_password%5D=b",
          "commit=one&commit=two"
        ] do
      original = :binary.copy(duplicate)
      assert {:handoff, :duplicate_parameters} = Admission.form(duplicate, "", fields)
      assert duplicate == original
    end

    for unsupported <- [
          "user%5Bemail%5D=%FF",
          "user%5Bemail%5D=%ZZ",
          "user%5Bemail%5D%5Bnested%5D=a"
        ] do
      assert {:handoff, :parameters} = Admission.form(unsupported, "", fields)
    end

    assert {:handoff, :parameters} = Admission.form(raw, "locale=de", fields)
    assert {:handoff, :parameters} = Admission.form(String.duplicate("x", 65_537), "", fields)
    checkbox = "user%5Bremember_me%5D=0&user%5Bremember_me%5D=1"
    assert {:ok, %{"user[remember_me]" => "1"}} = Admission.form(checkbox, "")
    assert {:handoff, :parameters} = Admission.form(checkbox, "", fields)
    assert {:handoff, :duplicate_parameters} = Admission.form(checkbox, "", ["user[remember_me]"])
  end

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
