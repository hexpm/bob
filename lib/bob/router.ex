defmodule Bob.Router do
  use Plug.Router
  import Plug.Conn

  plug Bob.Plugs.Exception

  plug :match
  plug :dispatch

  post "github" do
    {request, body, conn} = json_body(conn, [])
    secret    = Application.get_env(:bob, :github_secret)
    signature = get_req_header(conn, "x-hub-signature") |> List.first
    event     = get_req_header(conn, "x-github-event") |> List.first

    verify_signature(body, secret, signature)
    github_request(event, request)

    send_resp(conn, 200, "OK")
  end

  match _ do
    send_resp(conn, 404, "ERROR: 404")
  end

  defp github_request("ping", _request) do
    IO.puts "GOT PING"
  end

  defp github_request(event, request) do
    "refs/heads/" <> ref = request["ref"]

    name  = request["repository"]["name"]
    owner = request["repository"]["owner"]["name"]
    repo  = "#{owner}/#{name}"

    case event do
      "push"   -> Bob.Queue.build(repo, ref)
      "create" -> Bob.Queue.build(repo, ref)
      "delete" -> Bob.S3.delete(Bob.upload_path(repo, ref))
    end
  end

  defp json_body(conn, opts) do
    case read_body(conn, opts) do
      {:ok, body, conn} ->
        {parse(body), body, conn}
      {:more, _data, _conn} ->
        raise Plug.Parsers.RequestTooLargeError
    end
  end

  defp parse(body) do
    case Jazz.decode(body) do
      {:ok, params} ->
        params
      _ ->
        raise Bob.Plug.BadRequestError, message: "malformed JSON"
    end
  end

  defp verify_signature(_body, nil, _signature) do
    :ok
  end

  defp verify_signature(body, secret, signature) do
    digest = :crypto.hmac(:sha, secret, body) |> Base.encode16(case: :lower)
    digest = "sha1=" <> digest

    unless digest == signature do
      IO.puts(:stderr, "BAD SIGNATURE")
      raise Bob.Plug.BadRequestError, message: "bad signature"
    end
  end
end
