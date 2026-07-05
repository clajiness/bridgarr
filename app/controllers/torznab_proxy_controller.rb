class TorznabProxyController < ApplicationController
  def show
    result = Jackett::TorznabProxy.call(
      base_url: Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY),
      bridgarr_base_url: Setting.fetch_value(Setting::BRIDGARR_BASE_URL_KEY),
      api_key: Setting.fetch_value(Setting::JACKETT_API_KEY_KEY),
      jackett_id: params.expect(:jackett_id),
      query_params: request.query_parameters
    )

    render body: result.body, status: result.http_status, content_type: result.content_type
  end

  def download
    result = Jackett::DownloadProxy.call(
      base_url: Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY),
      api_key: Setting.fetch_value(Setting::JACKETT_API_KEY_KEY),
      jackett_id: params.expect(:jackett_id),
      query_params: request.query_parameters
    )

    render body: result.body, status: result.http_status, content_type: result.content_type
  end
end
