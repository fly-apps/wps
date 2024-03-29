defmodule WPS do
  @moduledoc """
  WPS keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def region do
    System.get_env("FLY_REGION") || "iad"
  end
end
