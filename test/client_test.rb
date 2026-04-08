require "minitest/autorun"
require "ostruct"

require "asc_tooling/client"

class ASCToolingClientTest < Minitest::Test
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
end
