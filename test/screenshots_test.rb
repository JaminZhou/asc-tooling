require_relative "test_helper"

class ASCToolingScreenshotsTest < Minitest::Test
  class FakeClient
    attr_reader :read_version_calls

    def initialize(app:, version:, localization:, screenshot_set:)
      @app = app
      @version = version
      @localization = localization
      @screenshot_set = screenshot_set
      @read_version_calls = []
    end

    def platform(_value) = "MAC_OS"
    def find_app!(_bundle_id) = @app

    def find_version!(_app, platform:, app_version: nil)
      @read_version_calls << { platform: platform, app_version: app_version }
      @version
    end

    def find_version_localization(_version, _locale) = @localization
    def find_screenshot_set(_localization, _display_type) = @screenshot_set
    def format_api_errors(_payload) = ""
  end

  def test_valid_display_types_includes_standard_types
    types = ASCTooling::Screenshots::VALID_DISPLAY_TYPES
    assert_includes types, "APP_DESKTOP"
    assert_includes types, "APP_IPHONE_67"
    assert_includes types, "APP_IPAD_PRO_3GEN_129"
    assert_includes types, "APP_APPLE_TV"
  end

  def test_display_type_warns_for_unrecognized_type
    screenshots = ASCTooling::Screenshots.allocate
    screenshots.instance_variable_set(:@options, { display_type: "APP_APPLE_VISION_PRO" })

    output = capture_io { screenshots.send(:display_type) }
    assert_match(/unrecognized screenshot display type/, output[1])
    assert_equal "APP_APPLE_VISION_PRO", screenshots.send(:display_type)
  end

  def test_display_type_returns_valid_type
    screenshots = ASCTooling::Screenshots.allocate
    screenshots.instance_variable_set(:@options, { display_type: "APP_DESKTOP" })

    assert_equal "APP_DESKTOP", screenshots.send(:display_type)
  end

  def test_summary_for_set_handles_nil
    screenshots = ASCTooling::Screenshots.allocate
    screenshots.instance_variable_set(:@options, { display_type: "APP_DESKTOP" })

    summary = screenshots.send(:summary_for_set, nil)

    assert_nil summary[:set_id]
    assert_equal "APP_DESKTOP", summary[:display_type]
    assert_equal 0, summary[:count]
    assert_equal [], summary[:screenshots]
  end

  def test_summary_for_set_extracts_screenshot_info
    included = [
      { "type" => "appScreenshots", "id" => "ss-1", "attributes" => { "fileName" => "shot.png", "assetDeliveryState" => { "state" => "COMPLETE" } } }
    ]
    set = ASCTooling::ScreenshotSetData.new(
      {
        "id" => "set-1",
        "attributes" => { "screenshotDisplayType" => "APP_DESKTOP" },
        "relationships" => {
          "appScreenshots" => { "data" => [{ "type" => "appScreenshots", "id" => "ss-1" }] }
        }
      },
      included: included
    )

    screenshots = ASCTooling::Screenshots.allocate
    screenshots.instance_variable_set(:@options, { display_type: "APP_DESKTOP" })

    summary = screenshots.send(:summary_for_set, set)

    assert_equal "set-1", summary[:set_id]
    assert_equal 1, summary[:count]
    assert_equal "shot.png", summary[:screenshots].first[:file_name]
    assert_equal "COMPLETE", summary[:screenshots].first[:state]
  end

  def test_status_reads_released_version_without_editable_filter
    app = OpenStruct.new(name: "Test", bundle_id: "com.test")
    version = OpenStruct.new(version_string: "1.10.0", app_store_state: "READY_FOR_SALE")
    localization = OpenStruct.new(id: "loc-1")
    screenshot_set = OpenStruct.new(
      id: "set-1",
      screenshot_display_type: "APP_DESKTOP",
      screenshots: [
        OpenStruct.new(file_name: "shot.png", asset_delivery_state: { "state" => "COMPLETE" })
      ]
    )
    client = FakeClient.new(
      app: app,
      version: version,
      localization: localization,
      screenshot_set: screenshot_set
    )
    screenshots = ASCTooling::Screenshots.allocate
    screenshots.instance_variable_set(
      :@options,
      {
        bundle_id: "com.test",
        platform: "macos",
        app_version: "1.10.0",
        locale: "en-US",
        display_type: "APP_DESKTOP"
      }
    )
    screenshots.instance_variable_set(:@asc, client)

    output = capture_io { screenshots.send(:print_status) }.first

    assert_includes output, "Version: 1.10.0"
    assert_includes output, "State: READY_FOR_SALE"
    assert_includes output, "Count: 1"
    assert_equal [{ platform: "MAC_OS", app_version: "1.10.0" }], client.read_version_calls

    screenshots.instance_variable_get(:@options)[:json] = true
    summary = JSON.parse(capture_io { screenshots.send(:print_status) }.first)
    assert_equal "READY_FOR_SALE", summary["version_state"]
  end
end
