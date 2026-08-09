require "rails_helper"

RSpec.describe Secrets::Redactor do
  it "redacts API keys in URLs without removing diagnostic context" do
    message = "GET http://10.251.41.13:9117/api?t=tvsearch&cat=5030,5040&apikey=super-secret-key"

    redacted = described_class.call(message)

    expect(redacted).to include("http://10.251.41.13:9117/api")
    expect(redacted).to include("t=tvsearch")
    expect(redacted).to include("cat=5030,5040")
    expect(redacted).to include("apikey=[REDACTED]")
    expect(redacted).not_to include("super-secret-key")
  end

  it "redacts mixed-case query credentials" do
    message = "http://example.test/api?apiKey=first&APIKEY=second&token=third"

    redacted = described_class.call(message)

    expect(redacted).to include("apiKey=[REDACTED]")
    expect(redacted).to include("APIKEY=[REDACTED]")
    expect(redacted).to include("token=[REDACTED]")
    expect(redacted).not_to include("first")
    expect(redacted).not_to include("second")
    expect(redacted).not_to include("third")
  end

  it "redacts common header and JSON credential forms" do
    message = 'X-Api-Key: sonarr-secret Authorization: Bearer bearer-secret {"apiKey":"json-secret"}'

    redacted = described_class.call(message)

    expect(redacted).to include("X-Api-Key: [REDACTED]")
    expect(redacted).to include("Authorization: Bearer [REDACTED]")
    expect(redacted).to include('"apiKey":"[REDACTED]"')
    expect(redacted).not_to include("sonarr-secret")
    expect(redacted).not_to include("bearer-secret")
    expect(redacted).not_to include("json-secret")
  end

  it "redacts Ruby hash-style credential strings" do
    message = '{ "apiKey"=>"hash-secret", "token"=>"other-secret" }'

    redacted = described_class.call(message)

    expect(redacted).to include('"apiKey"=>"[REDACTED]"')
    expect(redacted).to include('"token"=>"[REDACTED]"')
    expect(redacted).not_to include("hash-secret")
    expect(redacted).not_to include("other-secret")
  end

  it "redacts plain key-value credentials in diagnostic text" do
    redacted = described_class.call("HTTP 401 apikey=plain-secret token = another-secret")

    expect(redacted).to include("apikey=[REDACTED]", "token = [REDACTED]")
    expect(redacted).not_to include("plain-secret", "another-secret")
  end

  it "redacts password and secret values in common diagnostic forms" do
    message = 'password=hunter2 client_secret: deployment-secret {"db_password":"legacy-password"}'

    redacted = described_class.call(message)

    expect(redacted).to include("password=[REDACTED]", "client_secret: [REDACTED]", '"db_password":"[REDACTED]"')
    expect(redacted).not_to include("hunter2", "deployment-secret", "legacy-password")
  end

  it "does not alter an already redacted message" do
    message = "GET http://example.test/api?apikey=[REDACTED] api-key=[REDACTED] Authorization: Bearer [REDACTED]"

    expect(described_class.call(described_class.call(message))).to eq(message)
  end
end
