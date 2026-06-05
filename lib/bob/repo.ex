defmodule Bob.Repo do
  use Ecto.Repo,
    otp_app: :bob,
    adapter: Ecto.Adapters.Postgres

  def init(_context, opts) do
    if url = System.get_env("BOB_DATABASE_URL") do
      pool_size_env = System.get_env("BOB_DATABASE_POOL_SIZE")
      pool_size = if pool_size_env, do: String.to_integer(pool_size_env), else: opts[:pool_size]
      ca_cert = System.get_env("BOB_DATABASE_CA_CERT")
      client_key = System.get_env("BOB_DATABASE_CLIENT_KEY")
      client_cert = System.get_env("BOB_DATABASE_CLIENT_CERT")
      common_name = System.get_env("BOB_DATABASE_COMMON_NAME")

      ssl_opts =
        if ca_cert do
          [
            verify: :verify_peer,
            cacerts: [decode_cert(ca_cert)],
            key: decode_key(client_key),
            cert: decode_cert(client_cert),
            server_name_indication: String.to_charlist(common_name)
          ]
        end

      opts =
        opts
        |> Keyword.put(:url, url)
        |> Keyword.put(:pool_size, pool_size)
        |> then(fn opts ->
          if ssl_opts, do: Keyword.put(opts, :ssl, ssl_opts), else: opts
        end)

      {:ok, opts}
    else
      {:ok, opts}
    end
  end

  defp decode_cert(cert) do
    [{:Certificate, der, _}] = :public_key.pem_decode(cert)
    der
  end

  defp decode_key(key) do
    [{:RSAPrivateKey, der, :not_encrypted}] = :public_key.pem_decode(key)
    {:RSAPrivateKey, der}
  end
end
