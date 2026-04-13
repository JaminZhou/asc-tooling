require_relative "test_helper"

class ASCToolingClientTest < Minitest::Test
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

    client.define_singleton_method(:find_app_info_localization) { |_app, _locale| [app_info, existing_localization] }
    client.define_singleton_method(:request_json) do |_method, _path, params: nil, body: nil|
      create_calls += 1
      {}
    end

    returned_app_info, returned_localization = client.find_or_create_app_info_localization!(
      app,
      "ja"
    )

    assert_same app_info, returned_app_info
    assert_same existing_localization, returned_localization
    assert_equal 0, create_calls
  end

  def test_find_or_create_app_info_localization_uses_direct_api_creation
    client = ASCTooling::Client.allocate

    app = OpenStruct.new(name: "Rouse")
    app_info = OpenStruct.new(id: "app-info-123")
    created_localization = OpenStruct.new(locale: "ja")

    payloads = []
    calls = 0

    client.define_singleton_method(:find_app_info_localization) do |_app, _locale|
      calls += 1
      calls == 1 ? [app_info, nil] : [app_info, created_localization]
    end
    client.define_singleton_method(:request_json) do |method, path, params: nil, body: nil|
      payloads << { method: method, path: path, params: params, body: body }
      {}
    end

    returned_app_info, returned_localization = client.find_or_create_app_info_localization!(
      app,
      "ja"
    )

    assert_same app_info, returned_app_info
    assert_same created_localization, returned_localization

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

    client.define_singleton_method(:find_app_info_localization) do |_app, _locale|
      calls += 1
      calls == 1 ? [app_info, nil] : [app_info, created_localization]
    end
    client.define_singleton_method(:request_json) do |method, path, params: nil, body: nil|
      payload = { method: method, path: path, params: params, body: body }
      {}
    end

    client.find_or_create_app_info_localization!(app, "ja", name: "Rouse: Stay Awake")

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

  def test_platform_normalizes_known_values
    client = ASCTooling::Client.allocate
    assert_equal "IOS", client.platform("ios")
    assert_equal "MAC_OS", client.platform("macos")
    assert_equal "MAC_OS", client.platform("mac")
    assert_equal "MAC_OS", client.platform("osx")
    assert_equal "TV_OS", client.platform("tvos")
  end

  def test_platform_raises_for_unknown_value
    client = ASCTooling::Client.allocate
    assert_raises(ArgumentError) { client.platform("android") }
  end

  def test_format_api_errors_with_nested_structure
    client = ASCTooling::Client.allocate
    payload = {
      "errors" => [
        {
          "title" => "Validation failed",
          "detail" => "Missing required field",
          "meta" => {
            "associatedErrors" => {
              "/v1/builds" => [
                { "title" => "Build missing", "detail" => "No valid build" }
              ]
            }
          }
        }
      ]
    }

    result = client.format_api_errors(payload)
    assert_includes result, "Validation failed"
    assert_includes result, "Missing required field"
    assert_includes result, "blocker: Build missing"
    assert_includes result, "No valid build"
  end

  def test_format_api_errors_falls_back_to_json_when_no_errors
    client = ASCTooling::Client.allocate
    payload = { "status" => "unknown" }

    result = client.format_api_errors(payload)
    assert_includes result, '"status"'
  end

  def test_api_error_codes_extracts_direct_and_associated_codes
    client = ASCTooling::Client.allocate
    payload = {
      "errors" => [
        {
          "code" => "ENTITY_ERROR",
          "meta" => {
            "associatedErrors" => {
              "/v1/iap" => [{ "code" => "STATE_ERROR.FIRST_IAP" }]
            }
          }
        },
        { "code" => "VALIDATION_ERROR" }
      ]
    }

    codes = client.api_error_codes(payload)
    assert_includes codes, "ENTITY_ERROR"
    assert_includes codes, "STATE_ERROR.FIRST_IAP"
    assert_includes codes, "VALIDATION_ERROR"
    assert_equal 3, codes.size
  end

  def test_build_candidates_sends_correct_request
    client = ASCTooling::Client.allocate
    payloads = []

    client.define_singleton_method(:request_json) do |method, path, params: nil, body: nil|
      payloads << { method: method, path: path, params: params }
      { "data" => [{ "id" => "build-1" }] }
    end

    result = client.build_candidates("app-123", "1.0", limit: 10)

    assert_equal 1, payloads.length
    assert_equal "GET", payloads.first[:method]
    assert_equal "/v1/builds", payloads.first[:path]
    assert_equal "app-123", payloads.first[:params]["filter[app]"]
    assert_equal "1.0", payloads.first[:params]["filter[preReleaseVersion.version]"]
    assert_equal "10", payloads.first[:params]["limit"]
    assert_equal 1, result.length
  end

  def test_build_candidates_omits_version_filter_when_nil
    client = ASCTooling::Client.allocate
    payloads = []

    client.define_singleton_method(:request_json) do |_method, _path, params: nil, body: nil|
      payloads << { params: params }
      { "data" => [] }
    end

    client.build_candidates("app-123")
    refute payloads.first[:params].key?("filter[preReleaseVersion.version]")
  end

  def test_camelize_keys_converts_snake_case
    client = ASCTooling::Client.allocate
    result = client.send(:camelize_keys, {
                           whats_new: "notes",
                           marketing_url: "https://example.com",
                           privacy_policy_url: "https://example.com/privacy",
                           copyright: "2026 Test",
                           description: "A description"
                         })

    assert_equal({
                   "whatsNew" => "notes",
                   "marketingUrl" => "https://example.com",
                   "privacyPolicyUrl" => "https://example.com/privacy",
                   "copyright" => "2026 Test",
                   "description" => "A description"
                 }, result)
  end

  def test_update_resource_sends_camelized_attributes
    client = ASCTooling::Client.allocate
    payloads = []

    client.define_singleton_method(:request_json) do |_method, _path, params: nil, body: nil|
      payloads << body
      { "data" => {} }
    end

    client.update_resource("appStoreVersionLocalizations", "loc-1",
                           attributes: { whats_new: "notes", support_url: "https://example.com" })

    attrs = payloads.first.dig(:data, :attributes)
    assert_equal "notes", attrs["whatsNew"]
    assert_equal "https://example.com", attrs["supportUrl"]
    refute attrs.key?(:whats_new)
    refute attrs.key?(:support_url)
  end
end
