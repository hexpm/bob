defmodule Bob.OAuthTest do
  use ExUnit.Case, async: true

  alias Bob.OAuth

  describe "generate_code_verifier/0" do
    test "returns a 43-character url-safe string" do
      verifier = OAuth.generate_code_verifier()

      assert String.length(verifier) == 43
      assert verifier =~ ~r/^[A-Za-z0-9_-]+$/
    end

    test "returns a unique value per call" do
      assert OAuth.generate_code_verifier() != OAuth.generate_code_verifier()
    end
  end

  describe "generate_code_challenge/1" do
    test "returns the url-encoded sha256 of the verifier" do
      assert OAuth.generate_code_challenge("verifier") ==
               Base.url_encode64(:crypto.hash(:sha256, "verifier"), padding: false)
    end
  end

  describe "authorization_url/1" do
    test "builds the hexpm authorize url with pkce parameters" do
      url =
        OAuth.authorization_url(
          state: "state123",
          code_challenge: "challenge123",
          redirect_uri: "http://localhost:4003/oauth/callback"
        )

      assert %URI{} = uri = URI.parse(url)
      assert url =~ "http://localhost:4000/oauth/authorize?"

      assert URI.decode_query(uri.query) == %{
               "response_type" => "code",
               "client_id" => "b0b00000-0000-4000-8000-000000000b0b",
               "redirect_uri" => "http://localhost:4003/oauth/callback",
               "scope" => "api:read",
               "state" => "state123",
               "code_challenge" => "challenge123",
               "code_challenge_method" => "S256"
             }
    end
  end
end
