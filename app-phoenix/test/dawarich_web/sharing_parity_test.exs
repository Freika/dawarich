defmodule DawarichWeb.SharingParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2, put_req_header: 3]

  alias Dawarich.Test.SharingSeeds

  @endpoint DawarichWeb.Endpoint
  @external_resource "test/fixtures/sharing/pages.json"
  @pages SharingSeeds.fixture("pages.json")["pages"]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    SharingSeeds.load!()
    :ok
  end

  defp request(%{"verb" => "get", "path" => path}, cookie), do: get(conn(cookie), path)

  defp request(%{"verb" => "post", "path" => path, "params" => params}, cookie) do
    body = URI.encode_query(params || %{})

    conn(cookie)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> post(path, body)
  end

  defp conn(nil), do: build_conn()
  defp conn({name, value}), do: build_conn() |> put_req_header("cookie", "#{name}=#{value}")

  defp unlocked(%{"cookie" => nil}), do: nil

  defp unlocked(%{"cookie" => name, "path" => path}) do
    unlock =
      Enum.find(@pages, &(&1["path"] == path <> "/unlock" and &1["status"] == 302))

    response = request(unlock, nil)
    {name, response |> cookie_lines() |> Map.fetch!(name) |> elem(0)}
  end

  defp cookie_lines(conn) do
    for {"set-cookie", line} <- conn.resp_headers, into: %{} do
      [pair | attributes] = line |> String.split(";") |> Enum.map(&String.trim/1)
      [name, value] = String.split(pair, "=", parts: 2)

      attributes =
        attributes
        |> Enum.map(&(&1 |> String.downcase() |> String.replace(~r/\Aexpires=.*/, "expires")))
        |> Enum.sort()

      {name, {value, attributes}}
    end
  end

  defp header(conn, name), do: conn |> get_resp_header(name) |> Enum.join(", ")

  defp text(doc, selector),
    do:
      doc
      |> LazyHTML.query(selector)
      |> LazyHTML.text()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

  defp unmask(value) do
    <<pad::binary-size(32), masked::binary-size(32)>> = Base.url_decode64!(value, padding: false)
    pad |> :crypto.exor(masked) |> Base.encode16(case: :lower)
  end

  test "the unlock form and the csrf meta carry the tokens Rails derives from the session" do
    csrf = SharingSeeds.fixture("csrf.json")
    id = csrf["action"] |> String.split("/") |> Enum.at(2)
    cookie = Dawarich.Test.RailsUser.cookie(%{"_csrf_token" => csrf["session"]})
    html = conn({"_dawarich_session", cookie}) |> get("/s/#{id}") |> html_response(401)
    doc = LazyHTML.from_document(html)

    assert doc
           |> LazyHTML.query(~s(input[name="authenticity_token"]))
           |> LazyHTML.attribute("value")
           |> Enum.map(&unmask/1) ==
             [csrf["form"]]

    assert doc
           |> LazyHTML.query(~s(meta[name="csrf-token"]))
           |> LazyHTML.attribute("content")
           |> Enum.map(&unmask/1) ==
             [csrf["meta"]]
  end

  for page <- @pages do
    @page page

    test "#{page["name"]} answers as Rails does" do
      id = @page["path"] |> String.split("/") |> Enum.at(2) |> String.split("?") |> hd()
      cookie = unlocked(@page)
      before = @page["touched"] && SharingSeeds.view_count(id)
      conn = request(@page, cookie)

      assert conn.status == @page["status"]

      for {name, value} <- @page["headers"], do: assert(header(conn, name) == value, name)

      assert header(conn, "etag") != "" == @page["etag"]

      assert Map.new(Map.delete(cookie_lines(conn), "_dawarich_phoenix"), fn {name,
                                                                              {_value, attrs}} ->
               {name, attrs}
             end) ==
               @page["set_cookies"]

      if @page["touched"], do: assert(SharingSeeds.view_count(id) - before == @page["touched"])

      if @page["title"] do
        html = conn.resp_body
        rails = SharingSeeds.page("#{@page["name"]}.html")
        doc = LazyHTML.from_document(html)
        assert doc |> LazyHTML.query("title") |> LazyHTML.text() == @page["title"]

        assert LazyHTML.query(doc, "script[type=importmap], [data-controller], turbo-frame")
               |> Enum.empty?()

        assert html =~ "/native/app"
        assert text(doc, "h1") == text(LazyHTML.from_fragment(rails), "h1")

        if @page["status"] == 200 do
          assert html =~ "native-public-share"
          assert Map.has_key?(cookie_lines(conn), "_dawarich_phoenix")
          {_value, attrs} = cookie_lines(conn)["_dawarich_phoenix"]
          assert "httponly" in attrs and "samesite=lax" in attrs and "path=/" in attrs
        else
          assert text(doc, "main") == text(LazyHTML.from_fragment(rails), "main")
        end

        assert html =~ ~s(<html lang="#{@page["html_lang"]}">)
      end
    end
  end
end
