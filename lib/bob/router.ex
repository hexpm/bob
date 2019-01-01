defmodule Bob.Router do
  use Plug.Router
  use Bob.Plug.Rollbax
  import Plug.Conn
  require Logger

  def call(conn, opts) do
    Bob.Plug.Exception.call(conn, fun: &super(&1, opts))
  end

  plug(Bob.Plug.Forwarded)
  plug(Bob.Plug.Status)
  # TODO: SSL ?
  plug(:match)
  plug(:dispatch)

  post "github" do
    {request, body, conn} = json_body(conn, [])
    secret = Application.get_env(:bob, :github_secret)
    signature = get_req_header(conn, "x-hub-signature") |> List.first()
    event = get_req_header(conn, "x-github-event") |> List.first()

    verify_signature(body, secret, signature)
    github_request(event, request)

    send_resp(conn, 200, "OK")
  end

  match _ do
    send_resp(conn, 404, "ERROR: 404")
  end

  defp github_request("ping", _request) do
    IO.puts("GOT PING")
  end

  defp github_request(event, request) do
    ref_name = parse_ref(request["ref"])
    ref = request["head_commit"]["id"]
    full_name = request["repository"]["full_name"]
    module = repo_to_job(full_name)

    Bob.Queue.run(module, [event, ref_name, ref])
  end

  defp parse_ref("refs/heads/" <> ref), do: ref
  defp parse_ref("refs/tags/" <> ref), do: ref
  defp parse_ref(ref), do: ref

  defp json_body(conn, opts) do
    case read_body(conn, opts) do
      {:ok, body, conn} ->
        {parse(body), body, conn}

      {:more, _data, _conn} ->
        raise Plug.Parsers.RequestTooLargeError
    end
  end

  defp parse(body) do
    case Jason.decode(body) do
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
      Logger.error("bad github signature")
      raise Bob.Plug.BadRequestError, message: "bad signature"
    end
  end

  defp repo_to_job("elixir-lang/elixir"), do: Bob.Job.BuildElixir
  defp repo_to_job("elixir-lang/elixir-lang.github.com"), do: Bob.Job.BuildElixirGuides
  defp repo_to_job("hexpm/hex"), do: Bob.Job.BuildHexDocs
end
