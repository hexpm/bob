defmodule Bob.Job.ElixirChecker do
  @repo "elixir-lang/elixir"

  def run() do
    for {ref_name, ref} <- Bob.GitHub.diff(@repo, "builds/elixir", &expand_ref/1),
        build_ref?(ref_name) do
      otps = Bob.Job.BuildElixir.elixir_to_otp(ref)
      Bob.Queue.add(Bob.Job.BuildElixir, [ref_name, ref, otps])
    end
  end

  def priority(), do: 1
  def weight(), do: 1
  def concurrency(), do: :shared

  defp build_ref?("main"), do: true
  defp build_ref?("v0." <> _), do: false

  defp build_ref?("v" <> version) do
    match?({:ok, _}, Version.parse(version)) or match?({:ok, _}, Version.parse(version <> ".0"))
  end

  defp build_ref?(_), do: false

  defp expand_ref(ref) do
    ref_otps =
      Enum.map(Bob.Job.BuildElixir.elixir_to_otp(ref), fn otp ->
        [major, _minor] = String.split(otp, ".", parts: 2)
        "#{ref}-otp-#{major}"
      end)

    [ref] ++ ref_otps
  end
end
