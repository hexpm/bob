defmodule Bob.S3 do
  defmacrop s3_config(opts) do
    quote do
      { :config,
        'http://s3.amazonaws.com',
        unquote(opts[:access_key_id]),
        unquote(opts[:secret_access_key]),
        :virtual_hosted }
    end
  end

  def upload(name, data) do
    # TODO: cache
    name       = String.to_char_list(name)
    bucket     = Application.get_env(:bob, :s3_bucket) |> String.to_char_list
    opts       = [acl: :public_read]
    headers    = []
    :mini_s3.put_object(bucket, name, data, opts, headers, config())
  end

  def delete(name) do
    name   = String.to_char_list(name)
    bucket = Application.get_env(:bob, :s3_bucket) |> String.to_char_list
    :mini_s3.delete_object(bucket, name, config())
  end

  defp config do
    access_key = Application.get_env(:bob, :s3_access_key) |> String.to_char_list
    secret_key = Application.get_env(:bob, :s3_secret_key) |> String.to_char_list
    s3_config(access_key_id: access_key, secret_access_key: secret_key)
  end
end
