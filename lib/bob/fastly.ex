defmodule Bob.Fastly do
  @purge_request_delay 4_000

  def purge_builds(keys) do
    service = System.get_env("BOB_FASTLY_SERVICE_BUILDS")
    key = System.get_env("BOB_FASTLY_KEY")

    if service && key do
      purge(service, keys, key)
    else
      :ok
    end
  end

  defp purge(service, keys, key) do
    request(service, keys, key)
    Process.sleep(@purge_request_delay)
    request(service, keys, key)
    Process.sleep(@purge_request_delay)
    request(service, keys, key)
    :ok
  end

  defp request(service, keys, key) do
    url = "https://api.fastly.com/service/#{service}/purge"

    headers = [
      {"Fastly-Key", key},
      {"Accept", "application/json"},
      {"surrogate-key", keys}
    ]

    Bob.HTTP.retry("Fastly", fn ->
      Bob.HTTP.request(:post, url, headers, "")
    end)
  end
end
