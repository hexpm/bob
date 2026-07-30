defmodule Bob.Job do
  @type args :: [term()]

  # A job still running after this is wedged, so the runner reaps it and the
  # maintenance sweep requeues it. Jobs that legitimately run longer override
  # timeout/0.
  @default_timeout 3 * 60 * 60 * 1000

  @callback run(args()) :: term()
  @callback timeout() :: pos_integer()

  @optional_callbacks timeout: 0

  def default_timeout(), do: @default_timeout

  @doc "How long `key` may run before it is treated as wedged, in milliseconds."
  def timeout({module, _key}), do: timeout(module)

  # ensure_loaded? first: function_exported?/3 answers false for a module that
  # has not been loaded yet, which silently hands every job the default.
  def timeout(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :timeout, 0) do
      module.timeout()
    else
      @default_timeout
    end
  end
end
