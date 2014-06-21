defmodule Bob.Plug do
  defmodule BadRequestError do
    defexception [:message]

    defimpl Plug.Exception do
      def status(_exception) do
        400
      end
    end
  end
end
