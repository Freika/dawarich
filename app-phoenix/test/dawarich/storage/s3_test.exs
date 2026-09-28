defmodule Dawarich.Storage.S3Test do
  use ExUnit.Case, async: true

  alias Dawarich.Storage
  alias Dawarich.Storage.S3

  @mib 1024 * 1024
  @fixture "test/fixtures/wave2/storage.json" |> File.read!() |> Jason.decode!()

  defmodule FakeClient do
    @moduledoc false
    @behaviour ExAws.Request.HttpClient

    @impl true
    def request(method, url, body, headers, opts) do
      send(self(), {:s3, method, url, Map.new(headers), body})
      Keyword.fetch!(opts, :respond).(method, url, body)
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "w2-s3-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp config(root, respond, env \\ %{}) do
    env =
      Map.merge(
        %{
          "STORAGE_BACKEND" => "s3",
          "AWS_ACCESS_KEY_ID" => "AKIA",
          "AWS_SECRET_ACCESS_KEY" => "secret",
          "AWS_REGION" => "eu-central-1",
          "AWS_BUCKET" => "dawarich"
        },
        env
      )

    config = Storage.config!(env, root)

    %{
      config
      | ex_aws:
          Keyword.merge(config.ex_aws, http_client: FakeClient, http_opts: [respond: respond])
    }
  end

  defp ok(body \\ "", headers \\ []), do: {:ok, %{status_code: 200, headers: headers, body: body}}

  defp multipart_responder(fail) do
    fn
      :post, url, _body ->
        if URI.parse(url).query =~ "uploads",
          do:
            ok(
              "<InitiateMultipartUploadResult><UploadId>up-1</UploadId></InitiateMultipartUploadResult>"
            ),
          else:
            fail.(:complete) ||
              ok("<CompleteMultipartUploadResult></CompleteMultipartUploadResult>")

      :put, url, _body ->
        number = URI.decode_query(URI.parse(url).query)["partNumber"]
        fail.({:part, number}) || ok("", [{"ETag", ~s("etag-#{number}")}])

      :delete, _url, _body ->
        {:ok, %{status_code: 204, headers: [], body: ""}}
    end
  end

  defp received do
    receive do
      {:s3, method, url, headers, body} ->
        uri = URI.parse(url)
        [{method, uri.path, URI.decode_query(uri.query || ""), headers, body} | received()]
    after
      0 -> []
    end
  end

  defp big_file(root) do
    path = Path.join(root, "big.zip")
    bin = :crypto.strong_rand_bytes(8 * @mib + 5)
    File.write!(path, bin)
    {path, bin}
  end

  test "S3 addressing matches aws-sdk-s3 for every fixture combination", %{root: root} do
    for address <- @fixture["addresses"] do
      config =
        config(root, fn _, _, _ -> ok() end, %{
          "AWS_REGION" => address["region"],
          "AWS_BUCKET" => address["bucket"],
          "AWS_ENDPOINT_URL" => address["endpoint"]
        })

      assert S3.delete(config, "abc") == :ok
      assert_received {:s3, :delete, url, _headers, _body}
      uri = URI.parse(url)
      assert {uri.host, uri.path} == {address["host"], address["path"]}, inspect(address)
    end
  end

  test "plan/1: single part below 8 MiB, else parts of max(8 MiB, ceil(size/10 000))" do
    assert S3.plan(8 * @mib - 1) == :single
    assert S3.plan(8 * @mib) == {:multipart, 8 * @mib}
    assert S3.plan(200 * 1024 * @mib) == {:multipart, 21_474_837}
  end

  test "single-part PUT sends Content-MD5, Content-Type and Content-Disposition", %{root: root} do
    path = Path.join(root, "small.zip")
    File.write!(path, "zip bytes")
    config = config(root, fn _, _, _ -> ok() end)

    blob = Storage.put!(config, path, "report name.zip", "application/zip")

    assert [{:put, "/" <> key, %{}, headers, "zip bytes"}] = received()
    assert key == blob.key
    assert blob.service_name == "s3"
    assert headers["content-md5"] == Base.encode64(:crypto.hash(:md5, "zip bytes"))
    assert headers["content-type"] == "application/zip"

    assert headers["content-disposition"] ==
             @fixture["content_dispositions"]["report name.zip"]
  end

  test "multipart sends per-part Content-MD5 and completes with the ETags in order", %{root: root} do
    {path, bin} = big_file(root)
    config = config(root, multipart_responder(fn _ -> nil end))

    blob = Storage.put!(config, path, "big.zip", "application/zip")
    path = "/" <> blob.key
    <<first::binary-size(8 * @mib), second::binary>> = bin

    assert [
             {:post, ^path, %{"uploads" => _}, initiate, ""},
             {:put, ^path, %{"partNumber" => "1", "uploadId" => "up-1"}, part1, ^first},
             {:put, ^path, %{"partNumber" => "2", "uploadId" => "up-1"}, part2, ^second},
             {:post, ^path, %{"uploadId" => "up-1"}, complete, xml}
           ] = received()

    assert initiate["content-type"] == "application/zip"
    assert initiate["content-disposition"] =~ ~s(filename="big.zip")
    assert part1["content-md5"] == Base.encode64(:crypto.hash(:md5, first))
    assert part2["content-md5"] == Base.encode64(:crypto.hash(:md5, second))
    assert complete["content-type"] == "application/xml"

    assert xml ==
             ~s(<CompleteMultipartUpload><Part><PartNumber>1</PartNumber><ETag>"etag-1"</ETag></Part>) <>
               ~s(<Part><PartNumber>2</PartNumber><ETag>"etag-2"</ETag></Part></CompleteMultipartUpload>)
  end

  test "a failed part aborts the upload and re-raises", %{root: root} do
    {path, _bin} = big_file(root)

    fail = fn
      {:part, "2"} -> {:ok, %{status_code: 400, headers: [], body: "<Error/>"}}
      _ -> nil
    end

    config = config(root, multipart_responder(fail))

    assert_raise RuntimeError, fn -> Storage.put!(config, path, "big.zip", "application/zip") end
    assert {:delete, _path, %{"uploadId" => "up-1"}, _headers, ""} = List.last(received())
  end

  test "a 200 CompleteMultipartUpload whose body is an Error raises and aborts", %{root: root} do
    {path, _bin} = big_file(root)

    fail = fn
      :complete -> ok("<Error><Code>InternalError</Code></Error>")
      _ -> nil
    end

    config = config(root, multipart_responder(fail))

    assert_raise RuntimeError, fn -> Storage.put!(config, path, "big.zip", "application/zip") end
    assert {:delete, _path, %{"uploadId" => "up-1"}, _headers, ""} = List.last(received())
  end
end
