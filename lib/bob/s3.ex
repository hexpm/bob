defmodule Bob.S3 do
  alias ExAws.S3

  def upload(name, data) do
    # TODO: cache
    bucket = Application.get_env(:bob, :s3_bucket)
    S3.put_object!(bucket, name, data, acl: :public_read)
  end

  def delete(name) do
    bucket = Application.get_env(:bob, :s3_bucket)
    S3.delete_object!(bucket, name)
  end
end
