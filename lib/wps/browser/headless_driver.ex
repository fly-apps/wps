defmodule WPS.Browser.HeadlessDriver do
  use GenServer
  # chromedriver --enable-chrome-logs --log-level=ALL

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    driver_path = System.get_env("CHROME_DRIVER_PATH") || "chromedriver"
    {:ok, _, driver} =
      :exec.run_link("#{driver_path} --enable-chrome-logs --log-level=ALL", [stdout: :print, stderr: :print])

    {:ok, %{driver: driver}}
  end
end
