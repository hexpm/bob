defmodule Bob.Job do
  @type args :: [term()]

  @callback run(args()) :: term()
end
