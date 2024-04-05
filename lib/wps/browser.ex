defmodule WPS.Browser do
  # chromedriver --enable-chrome-logs --log-level=ALL
  alias WPS.Browser

  defstruct session: nil

  defmodule Timing do
    defstruct url: nil,
              status: nil,
              transfered_bytes: 0,
              region: nil,
              loaded: 0,
              meta: %{},
              http_status: nil,
              browser_url: nil

    def build(url, region) do
      %__MODULE__{url: url, browser_url: url, status: :awaiting_session, region: region}
    end

    def loading(%__MODULE__{} = timing) do
      %__MODULE__{timing | status: :loading}
    end

    def error(%__MODULE__{} = timing) do
      %__MODULE__{timing | status: :error}
    end

    def complete(%__MODULE__{} = timing) do
      %__MODULE__{timing | status: :complete}
    end

    def dom_interactive_time(%__MODULE__{} = timing) do
      with :complete <- timing.status,
           %{"domInteractive" => domint, "navigationStart" => start}
           when is_integer(domint) and is_integer(start) <- timing.meta do
        domint - start
      else
        _ -> nil
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
          "user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.6312.86 Safari/537.36",
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

  @max_retries 10
  def start_session(base_url \\ "http://127.0.0.1:9515") do
    config =
      base_url
      |> WebDriverClient.Config.build(
        protocol: :w3c,
        http_client_options: [recv_timeout: 60_000, timeout: 60_000]
      )

    case start_session_with_retries(config, 0) do
      {:ok, %Browser{} = browser} -> {:ok, browser}
      {:error, reason} -> {:error, reason}
    end
  end

  def with_session(base_url \\ "http://127.0.0.1:9515", timeout, func)
      when is_function(func, 1) do
    parent = self()

    task =
      Task.Supervisor.async(WPS.TaskSup, fn ->
        Process.flag(:trap_exit, true)
        Process.monitor(parent)

        case start_session(base_url) do
          {:ok, browser} ->
            try do
              %Task{ref: task_ref} = Task.Supervisor.async(WPS.TaskSup, fn -> func.(browser) end)
              Process.send_after(self(), :timeout, timeout)

              receive do
                :timeout -> {:error, :timeout}
                {:EXIT, _pid, reason} -> {:error, {:exit, reason}}
                {:DOWN, _, :process, ^parent, reason} -> {:error, {:exit, reason}}
                {^task_ref, result} -> result
              end
            after
              end_session(browser)
            end

          {:error, reason} ->
            {:error, {:badsession, reason}}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      _other -> {:error, :timeout}
    end
  end

  defp start_session_with_retries(config, retries) do
    case WebDriverClient.start_session(config, %{capabilities: @capabilities}) do
      {:ok, %WebDriverClient.Session{} = web_session} ->
        {:ok, %Browser{session: web_session}}

      {:error, %WebDriverClient.ConnectionError{reason: :econnrefused} = reason} ->
        if retries < @max_retries do
          Process.sleep(1000)
          start_session_with_retries(config, retries + 1)
        else
          {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def navigate_to(%Browser{session: session}, url) do
    WebDriverClient.navigate_to(session, url)
  end

  def time_navigation(%Timing{} = timing, timeout) do
    case with_session(timeout, fn browser -> do_time_navigation(browser, timing) end) do
      {:ok, %Timing{} = timing} -> {:ok, timing}
      {:error, {reason, %Timing{} = timing}} -> {:error, {reason, timing}}
      {:error, reason} -> {:error, {reason, Timing.error(timing)}}
    end
  end

  defp do_time_navigation(%Browser{session: session} = browser, timing) do
    WebDriverClient.navigate_to(session, timing.url)
    timing = %Timing{timing | status: :loading}
    await_response_end(browser, timing, 0)
  end

  @perf_timing_poll_interval 100
  @perf_timing_timeout 30_000
  defp await_response_end(browser, timing, tries)
       when tries * @perf_timing_poll_interval > @perf_timing_timeout do
    end_session(browser)
    timing = %Timing{timing | status: :error}
    {:error, {:timeout, timing}}
  end

  defp await_response_end(browser, timing, tries) do
    case exec_script(browser, "return performance.timing") do
      {:ok, %{"loadEventEnd" => 0, "navigationStart" => _}} ->
        Process.sleep(@perf_timing_poll_interval)
        await_response_end(browser, timing, tries + 1)

      {:ok, %{"loadEventEnd" => ending, "navigationStart" => start} = all} ->
        {status, http_status, transfered_bytes, browser_url} = fetch_status_from_logs(browser)

        timing = %Timing{
          timing
          | status: status,
            transfered_bytes: transfered_bytes,
            loaded: ending - start,
            meta: all,
            http_status: http_status,
            browser_url: browser_url,
            region: WPS.region()
        }

        {:ok, timing}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def end_session(%Browser{session: session}) do
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

  def fetch_status_from_logs(%Browser{session: session}) do
    {:ok, url} = WebDriverClient.fetch_current_url(session)
    await_req_sent(session, url)
  end

  defp await_req_sent(session, url) do
    {:ok, encoded_logs} = WebDriverClient.fetch_logs(session, "performance")

    logs =
      for entry <- encoded_logs, %WebDriverClient.LogEntry{message: json} = entry do
        Jason.decode!(json)["message"]
      end

    req_id =
      Enum.find_value(logs, fn
        %{"method" => "Network.requestWillBeSent", "params" => %{"documentURL" => ^url} = params} ->
          Map.fetch!(params, "requestId")

        %{} ->
          nil
      end)

    first_resp =
      Enum.find_value(logs, fn
        %{"method" => "Network.responseReceived", "params" => %{"response" => resp} = params} ->
          if params["requestId"] == req_id && resp["url"] == url do
            params
          end

        %{} ->
          nil
      end)

    transfered_bytes =
      logs
      |> Enum.flat_map(fn
        %{"method" => method, "params" => params} when method in ~w(Network.dataReceived) ->
          case params do
            %{"encodedDataLength" => len} when len > 0 -> [len]
            %{"dataLength" => len} -> [len]
            %{} -> []
          end

        %{} ->
          []
      end)
      |> Enum.sum()

    if first_resp do
      %{"status" => status, "url" => url} = first_resp["response"]
      {:complete, status, transfered_bytes, url}
    else
      {:error, nil, transfered_bytes, url}
    end
  end
end
