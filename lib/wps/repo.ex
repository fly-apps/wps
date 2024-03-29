defmodule WPS.Repo do
  use Ecto.Repo,
    otp_app: :wps,
    adapter: Ecto.Adapters.Postgres
end
