require "minitest/autorun"
require "minitest/mock"
require "ostruct"

require "asc_tooling/client"

class ASCToolingClientTest < Minitest::Test
  ENV_MISSING = Object.new

  EnvAwareClient = Class.new(ASCTooling::Client) do
    attr_reader :captured_auth

    def authenticate!
      @captured_auth = {
        key_id: @key_id,
        issuer_id: @issuer_id,
        key_path: @key_path
      }
    end
  end

  def test_find_or_create_app_info_localization_returns_existing_localization_without_creation
    client = ASCTooling::Client.allocate

    app = OpenStruct.new(name: "Rouse")
    app_info = OpenStruct.new(id: "app-info-123")
    existing_localization = OpenStruct.new(locale: "ja")

    create_calls = 0

    client.stub(:find_app_info_localization, [app_info, existing_localization]) do
      client.stub(:request_json, lambda { |_method, _path, params: nil, body: nil|
        create_calls += 1
        {}
      }) do
        returned_app_info, returned_localization = client.find_or_create_app_info_localization!(
          app,
          "ja"
        )

        assert_same app_info, returned_app_info
        assert_same existing_localization, returned_localization
      end
    end

    assert_equal 0, create_calls
  end

  def test_find_or_create_app_info_localization_uses_direct_api_creation
    client = ASCTooling::Client.allocate

    app = OpenStruct.new(name: "Rouse")
    app_info = OpenStruct.new(id: "app-info-123")
    created_localization = OpenStruct.new(locale: "ja")

    payloads = []
    calls = 0

    client.stub(:find_app_info_localization, lambda { |_app, _locale|
      calls += 1
      calls == 1 ? [app_info, nil] : [app_info, created_localization]
    }) do
      client.stub(:request_json, lambda { |method, path, params: nil, body: nil|
        payloads << { method: method, path: path, params: params, body: body }
        {}
      }) do
        returned_app_info, returned_localization = client.find_or_create_app_info_localization!(
          app,
          "ja"
        )

        assert_same app_info, returned_app_info
        assert_same created_localization, returned_localization
      end
    end

    assert_equal 1, payloads.length
    assert_equal "POST", payloads.first[:method]
    assert_equal "/v1/appInfoLocalizations", payloads.first[:path]
    assert_nil payloads.first[:params]
    assert_equal(
      {
        data: {
          type: "appInfoLocalizations",
          attributes: {
            locale: "ja",
            name: "Rouse"
          },
          relationships: {
            appInfo: {
              data: {
                type: "appInfos",
                id: "app-info-123"
              }
            }
          }
        }
      },
      payloads.first[:body]
    )
  end

  def test_find_or_create_app_info_localization_prefers_explicit_name
    client = ASCTooling::Client.allocate

    app = OpenStruct.new(name: "Rouse")
    app_info = OpenStruct.new(id: "app-info-123")
    created_localization = OpenStruct.new(locale: "ja")

    payload = nil
    calls = 0

    client.stub(:find_app_info_localization, lambda { |_app, _locale|
      calls += 1
      calls == 1 ? [app_info, nil] : [app_info, created_localization]
    }) do
      client.stub(:request_json, lambda { |method, path, params: nil, body: nil|
        payload = { method: method, path: path, params: params, body: body }
        {}
      }) do
        client.find_or_create_app_info_localization!(app, "ja", name: "Rouse: Stay Awake")
      end
    end

    assert_equal "Rouse: Stay Awake", payload.dig(:body, :data, :attributes, :name)
  end

  def test_auth_options_from_uses_supported_env_names
    with_env(
      "ASC_KEY_ID" => nil,
      "APP_STORE_CONNECT_API_KEY_KEY_ID" => "secondary-key-id",
      "ASC_ISSUER_ID" => "primary-issuer-id",
      "APP_STORE_CONNECT_API_ISSUER_ID" => nil,
      "ASC_KEY_PATH" => nil,
      "APP_STORE_CONNECT_API_KEY_KEY_FILEPATH" => "/tmp/secondary-key.p8"
    ) do
      auth_options = ASCTooling::Client.auth_options_from({})

      assert_equal "secondary-key-id", auth_options[:key_id]
      assert_equal "primary-issuer-id", auth_options[:issuer_id]
      assert_equal "/tmp/secondary-key.p8", auth_options[:key_path]
    end
  end

  def test_initialize_falls_back_to_env_auth_values
    with_env(
      "ASC_KEY_ID" => "env-key-id",
      "ASC_ISSUER_ID" => "env-issuer-id",
      "ASC_KEY_PATH" => "/tmp/env-key.p8"
    ) do
      client = EnvAwareClient.new

      assert_equal(
        {
          key_id: "env-key-id",
          issuer_id: "env-issuer-id",
          key_path: "/tmp/env-key.p8"
        },
        client.captured_auth
      )
    end
  end

  private

  def with_env(overrides)
    original_values = overrides.keys.to_h do |key|
      [key, ENV.key?(key) ? ENV[key] : ENV_MISSING]
    end

    overrides.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    yield
  ensure
    original_values.each do |key, value|
      if value.equal?(ENV_MISSING)
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
