defmodule Bob.Job do
  @type args :: [term()]

  @callback run(args()) :: term()
  @callback equal?(args(), args()) :: boolean()
end
