defmodule Bob.DockerHub.AuthTest do
  use ExUnit.Case, async: true

  alias Bob.DockerHub.Auth

  defp token(claims) do
    encode = &Base.url_encode64(&1, padding: false)
    Enum.join([encode.(~s({"alg":"RS256"})), encode.(JSON.encode!(claims)), "signature"], ".")
  end

  describe "refresh_after/1" do
    test "replaces an access token session after two thirds of its 15 minutes" do
      # iat and exp of a session Docker Hub issued for an access token
      claims = %{"iat" => 1_791_482_900, "exp" => 1_791_483_800, "sub" => "hexbob"}
      assert Auth.refresh_after(token(claims)) == 600_000
    end

    test "reads the lifetime from the token, not the local clock" do
      assert Auth.refresh_after(token(%{"iat" => 1_000, "exp" => 4_600})) == 2_400_000
    end
  end
end
