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

  def test_find_version_uses_server_side_version_filter
    client = ASCTooling::Client.allocate
    app = OpenStruct.new(id: "app-123")
    captured = nil
    client.define_singleton_method(:request_json) do |method, path, params: nil, body: nil|
      captured = { method: method, path: path, params: params, body: body }
      {
        "data" => [
          {
            "id" => "version-123",
            "attributes" => {
              "versionString" => "1.10.0",
              "appStoreState" => "READY_FOR_SALE"
            }
          }
        ]
      }
    end

    version = client.find_version!(app, platform: "MAC_OS", app_version: "1.10.0")

    assert_equal "1.10.0", version.version_string
    assert_equal "GET", captured[:method]
    assert_equal "/v1/apps/app-123/appStoreVersions", captured[:path]
    assert_equal "MAC_OS", captured[:params]["filter[platform]"]
    assert_equal "1.10.0", captured[:params]["filter[versionString]"]
    assert_equal "1", captured[:params]["limit"]
  end

  def test_find_app_info_localization_selects_matching_live_state
    client = ASCTooling::Client.allocate
    app = OpenStruct.new(id: "app-123")
    requested_paths = []
    client.define_singleton_method(:request_json) do |_method, path, params: nil, body: nil|
      requested_paths << path
      if path == "/v1/apps/app-123/appInfos"
        {
          "data" => [
            {
              "id" => "draft-info",
              "attributes" => { "appStoreState" => "PREPARE_FOR_SUBMISSION" }
            },
            {
              "id" => "live-info",
              "attributes" => { "appStoreState" => "READY_FOR_SALE" }
            }
          ]
        }
      else
        {
          "data" => [
            {
              "id" => "live-localization",
              "attributes" => { "locale" => "en-US", "name" => "Live Name" }
            }
          ]
        }
      end
    end

    app_info, localization = client.find_app_info_localization(
      app,
      "en-US",
      states: ["READY_FOR_SALE"]
    )

    assert_equal "live-info", app_info.id
    assert_equal "Live Name", localization.name
    assert_equal(
      ["/v1/apps/app-123/appInfos", "/v1/appInfos/live-info/appInfoLocalizations"],
      requested_paths
    )
  end

  def test_find_app_info_localization_does_not_fall_back_to_draft_for_live_state
    client = ASCTooling::Client.allocate
    app = OpenStruct.new(id: "app-123")
    request_count = 0
    client.define_singleton_method(:request_json) do |_method, _path, params: nil, body: nil|
      request_count += 1
      {
        "data" => [
          {
            "id" => "draft-info",
            "attributes" => { "appStoreState" => "PREPARE_FOR_SUBMISSION" }
          }
        ]
      }
    end

    app_info, localization = client.find_app_info_localization(
      app,
      "en-US",
      states: ["READY_FOR_SALE"]
    )

    assert_nil app_info
    assert_nil localization
    assert_equal 1, request_count
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

  def test_find_build_by_number_uses_server_side_build_filter
    client = ASCTooling::Client.allocate
    captured = nil
    client.define_singleton_method(:request_json) do |method, path, params: nil, body: nil|
      captured = { method: method, path: path, params: params, body: body }
      {
        "data" => [
          {
            "id" => "build-123",
            "attributes" => { "version" => "2026082501" }
          }
        ]
      }
    end

    build = client.find_build_by_number("app-123", "1.3.0", "2026082501", platform: "IOS")

    assert_equal "build-123", build["id"]
    assert_equal "GET", captured[:method]
    assert_equal "/v1/builds", captured[:path]
    assert_equal "app-123", captured[:params]["filter[app]"]
    assert_equal "1.3.0", captured[:params]["filter[preReleaseVersion.version]"]
    assert_equal "IOS", captured[:params]["filter[preReleaseVersion.platform]"]
    assert_equal "2026082501", captured[:params]["filter[version]"]
    assert_equal "1", captured[:params]["limit"]
  end

  def test_find_latest_eligible_build_uses_server_side_platform_and_state_filters
    client = ASCTooling::Client.allocate
    captured = nil
    client.define_singleton_method(:request_json) do |method, path, params: nil, body: nil|
      captured = { method: method, path: path, params: params, body: body }
      {
        "data" => [
          {
            "id" => "build-eligible",
            "attributes" => { "version" => "2026082501" }
          }
        ]
      }
    end

    build = client.find_latest_eligible_build("app-123", "1.3.0", platform: "IOS")

    assert_equal "build-eligible", build["id"]
    assert_equal "GET", captured[:method]
    assert_equal "/v1/builds", captured[:path]
    assert_equal "app-123", captured[:params]["filter[app]"]
    assert_equal "1.3.0", captured[:params]["filter[preReleaseVersion.version]"]
    assert_equal "IOS", captured[:params]["filter[preReleaseVersion.platform]"]
    assert_equal "VALID", captured[:params]["filter[processingState]"]
    assert_equal "APP_STORE_ELIGIBLE", captured[:params]["filter[buildAudienceType]"]
    assert_equal "-uploadedDate", captured[:params]["sort"]
    assert_equal "1", captured[:params]["limit"]
  end

  def test_paginated_resources_follows_next_link_until_exhausted
    client = ASCTooling::Client.allocate
    requests = []
    client.define_singleton_method(:request_json) do |method, path, params: nil, body: nil|
      requests << { method: method, path: path, params: params, body: body }
      if params["cursor"] == "next-page"
        { "data" => [{ "id" => "iap-201" }], "links" => {} }
      else
        {
          "data" => [{ "id" => "iap-1" }],
          "links" => {
            "next" => "https://api.appstoreconnect.apple.com/v1/apps/app-123/inAppPurchasesV2?cursor=next-page&limit=200"
          }
        }
      end
    end

    resources = client.paginated_resources(
      "/v1/apps/app-123/inAppPurchasesV2",
      params: { "filter[state]" => "READY_TO_SUBMIT" },
      limit: 200
    )

    resource_ids = resources.map { |resource| resource["id"] }
    assert_equal %w[iap-1 iap-201], resource_ids
    assert_equal 2, requests.length
    assert_equal "READY_TO_SUBMIT", requests.first[:params]["filter[state]"]
    assert_equal "200", requests.first[:params]["limit"]
    assert_equal "next-page", requests.last[:params]["cursor"]
    assert_equal "200", requests.last[:params]["limit"]
  end

  def test_paginated_document_merges_data_and_deduplicates_included_resources
    client = ASCTooling::Client.allocate
    client.define_singleton_method(:request_json) do |_method, _path, params: nil, body: nil|
      if params["cursor"] == "next-page"
        {
          "data" => [{ "id" => "item-51" }],
          "included" => [
            { "type" => "inAppPurchaseVersions", "id" => "iap-version-1" },
            { "type" => "appStoreVersions", "id" => "app-version-1" }
          ]
        }
      else
        {
          "data" => [{ "id" => "item-1" }],
          "included" => [{ "type" => "inAppPurchaseVersions", "id" => "iap-version-1" }],
          "links" => {
            "next" => "https://api.appstoreconnect.apple.com/v1/reviewSubmissions/submission-1/items?cursor=next-page&limit=50"
          }
        }
      end
    end

    document = client.paginated_document(
      "/v1/reviewSubmissions/submission-1/items",
      params: { "include" => "appStoreVersion,inAppPurchaseVersion" },
      limit: 50
    )

    item_ids = document["data"].map { |item| item["id"] }
    assert_equal %w[item-1 item-51], item_ids
    assert_equal 2, document["included"].length
    included_ids = document["included"].map { |resource| resource["id"] }
    assert_equal %w[iap-version-1 app-version-1], included_ids
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
