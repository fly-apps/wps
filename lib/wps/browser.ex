defmodule WPS.Browser do
  # chromedriver --enable-chrome-logs --log-level=ALL
  alias WPS.Browser

  defstruct session: nil

  defmodule Timing do
    defstruct url: nil, status: nil, region: nil, loaded: 0, meta: %{}

    def build(url, region) do
      %__MODULE__{url: url, status: :awaiting_session, region: region}
    end

    def dom_interactive_time(%__MODULE__{} = timing) do
      case timing.meta do
        %{"domInteractive" => domint, "navigationStart" => start} when is_integer(domint) and is_integer(start) ->
          domint - start

        _ ->
          nil
      end
    end
  end

  @capabilities %{
    alwaysMatch: %{
      "goog:loggingPrefs": %{
        browser: "ALL",
        performance: "ALL"
      },
      "goog:chromeOptions": %{
        perfLoggingPrefs: %{
          enableNetwork: true,
          enablePage: true
        },
        args: [
          "--enable-logging",
          "--v=1",
          "--headless",
          "--disable-dev-shm-usage",
          "--disable-extensions",
          "--disable-default-apps",
          "--disable-application-cache",
          "--disable-infobars",
          "--homedir=/tmp",
          "--disable-gpu",
          "--disable-sync",
          "--disable-background-networking",
          "--incognito"
        ]
      }
    }
  }

  def start_session(base_url \\ "http://127.0.0.1:9515") do
    config =
      base_url
      |> WebDriverClient.Config.build(
        protocol: :w3c,
        http_client_options: [recv_timeout: 60_000, timeout: 60_000]
      )

    case WebDriverClient.start_session(config, %{capabilities: @capabilities}) do
      {:ok, %WebDriverClient.Session{} = web_session} ->
        {:ok, %Browser{session: web_session}}

      {:error, _} = error ->
        error
    end
  end

  def navigate_to(%Browser{session: session}, url) do
    WebDriverClient.navigate_to(session, url)
  end

  def time_navigation(%Browser{session: session} = browser, %Timing{} = timing) do
    WebDriverClient.navigate_to(session, timing.url)
    timing = %Timing{timing | status: :loading}
    await_response_end(browser, timing, 0)
  end

  @perf_timing_poll_interval 100
  @perf_timing_timeout 15_000
  defp await_response_end(browser, timing, tries) do
    if tries * @perf_timing_poll_interval > @perf_timing_timeout do
      stop_session(browser)
      timing = %Timing{timing | status: :error}
      {:error, {:timeout, timing}}
    else
      {:ok, js_timing} = exec_script(browser, "return performance.timing")

      case js_timing do
        %{"loadEventEnd" => 0, "navigationStart" => _} ->
          Process.sleep(@perf_timing_poll_interval)
          await_response_end(browser, timing, tries + 1)

        %{"loadEventEnd" => ending, "navigationStart" => start} = all ->
          timing = %Timing{
            timing
            | status: :complete,
              loaded: ending - start,
              meta: all,
              region: WPS.region()
          }

          {:ok, timing}
      end
    end
  end

  def stop_session(%Browser{session: session}) do
    WebDriverClient.end_session(session)
  end

  def exec_script(%Browser{session: session}, script, args \\ []) do
    %WebDriverClient.Session{id: id, config: config} = session

    post =
      Req.post!("#{config.base_url}/session/#{id}/execute/sync",
        json: %{script: script, args: args}
      )

    case post do
      %Req.Response{status: 200, body: body} ->
        %{"value" => val} = body
        {:ok, val}

      %Req.Response{status: status, body: body} ->
        {:error, {status, body["value"]["message"]}}
    end
  end
end
