class TorznabProxyController < ApplicationController
  skip_before_action :redirect_to_admin_setup
  skip_before_action :authenticate_user!

  before_action :authenticate_proxy_api_key!

  def show
    jackett_id = params.expect(:jackett_id)
    started_at = monotonic_time
    result = Jackett::TorznabProxy.call(
      base_url: Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY),
      bridgarr_base_url: Setting.fetch_value(Setting::BRIDGARR_BASE_URL_KEY),
      api_key: Setting.fetch_value(Setting::JACKETT_API_KEY_KEY),
      proxy_api_key: Setting.proxy_api_key,
      jackett_id:,
      query_params: request.query_parameters
    )
    record_proxy_request(jackett_id:, result:, started_at:, request_type: request.query_parameters["t"])

    render body: result.body, status: result.http_status, content_type: result.content_type
  end

  def download
    jackett_id = params.expect(:jackett_id)
    started_at = monotonic_time
    result = Jackett::DownloadProxy.call(
      base_url: Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY),
      api_key: Setting.fetch_value(Setting::JACKETT_API_KEY_KEY),
      jackett_id:,
      query_params: request.query_parameters
    )
    record_proxy_request(jackett_id:, result:, started_at:, request_type: "download")

    render body: result.body, status: result.http_status, content_type: result.content_type
  end

  private

    def authenticate_proxy_api_key!
      provided_token = params[:apikey].to_s
      expected_token = Setting.proxy_api_key

      return if provided_token.bytesize == expected_token.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(provided_token, expected_token)

      head :unauthorized
    end

    def record_proxy_request(jackett_id:, result:, started_at:, request_type:)
      ProxyActivity::Recorder.call(
        indexer: Indexer.find_by(jackett_id:),
        jackett_id:,
        request_type:,
        query_params: request.query_parameters,
        result:,
        duration_ms: ((monotonic_time - started_at) * 1_000).round
      )
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
end
