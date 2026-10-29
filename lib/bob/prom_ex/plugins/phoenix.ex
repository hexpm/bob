defmodule Bob.PromEx.Plugins.Phoenix do
  @moduledoc """
  `PromEx.Plugins.Phoenix` with HTTP labels the client can't choose.

  The upstream plugin labels its HTTP request metrics with the `Host` header
  and the method exactly as the client sent them, and offers no option to
  change that. Scanners send arbitrary hosts and made-up methods, and each new
  value is a new series for every path, status and pod.

  The HTTP metrics are returned under their upstream names, with their upstream
  buckets, without the host label, and with any method other than GET, HEAD,
  POST, PUT, PATCH, DELETE and OPTIONS labelled `"OTHER"`. Routes are still
  looked up with the method the client sent. Every other metric is upstream's
  unchanged, so the upstream Phoenix dashboard keeps working.
  """

  use PromEx.Plugin

  alias PromEx.MetricTypes.Event

  @methods ~w(GET HEAD POST PUT PATCH DELETE OPTIONS)

  @impl true
  def event_metrics(opts) do
    opts
    |> PromEx.Plugins.Phoenix.event_metrics()
    |> Enum.map(&relabel/1)
  end

  defp relabel(%Event{group_name: :phoenix_http_event_metrics, metrics: metrics} = event) do
    %{event | metrics: Enum.map(metrics, &relabel_metric/1)}
  end

  defp relabel(event), do: event

  defp relabel_metric(%{tags: tags, tag_values: tag_values} = metric) do
    %{
      metric
      | tags: List.delete(tags, :host),
        tag_values: fn metadata -> metadata |> tag_values.() |> http_tags() end
    }
  end

  defp http_tags(tags) do
    tags
    |> Map.delete(:host)
    |> Map.replace_lazy(:method, &method/1)
  end

  defp method(method) when method in @methods, do: method
  defp method(_method), do: "OTHER"
end
