require_relative "test_helper"

class ASCToolingScreenshotsTest < Minitest::Test
  def test_valid_display_types_includes_standard_types
    types = ASCTooling::Screenshots::VALID_DISPLAY_TYPES
    assert_includes types, "APP_DESKTOP"
    assert_includes types, "APP_IPHONE_67"
    assert_includes types, "APP_IPAD_PRO_3GEN_129"
    assert_includes types, "APP_APPLE_TV"
  end

  def test_display_type_raises_for_invalid_type
    screenshots = ASCTooling::Screenshots.allocate
    screenshots.instance_variable_set(:@options, { display_type: "INVALID_TYPE" })

    assert_raises(ArgumentError) { screenshots.send(:display_type) }
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
end
