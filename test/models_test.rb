require_relative "test_helper"

class ASCToolingModelsTest < Minitest::Test
  def test_app_data_attributes
    app = ASCTooling::AppData.new({
                                    "id" => "app-123",
                                    "attributes" => { "name" => "MyApp", "bundleId" => "com.example.app" }
                                  })

    assert_equal "app-123", app.id
    assert_equal "MyApp", app.name
    assert_equal "com.example.app", app.bundle_id
  end

  def test_version_data_attributes
    version = ASCTooling::VersionData.new({
                                            "id" => "v-1",
                                            "attributes" => {
                                              "versionString" => "1.2.0",
                                              "appStoreState" => "PREPARE_FOR_SUBMISSION",
                                              "releaseType" => "AFTER_APPROVAL",
                                              "copyright" => "2026 Jamin"
                                            },
                                            "relationships" => { "build" => { "data" => nil } }
                                          })

    assert_equal "v-1", version.id
    assert_equal "1.2.0", version.version_string
    assert_equal "PREPARE_FOR_SUBMISSION", version.app_store_state
    assert_equal "AFTER_APPROVAL", version.release_type
    assert_equal "2026 Jamin", version.copyright
    assert_nil version.build
  end

  def test_version_data_resolves_build_from_included
    included = [
      { "type" => "builds", "id" => "build-1", "attributes" => { "version" => "42", "processingState" => "VALID" } }
    ]
    version = ASCTooling::VersionData.new(
      {
        "id" => "v-1",
        "attributes" => { "versionString" => "1.0" },
        "relationships" => { "build" => { "data" => { "type" => "builds", "id" => "build-1" } } }
      },
      included: included
    )

    build = version.build
    refute_nil build
    assert_equal "build-1", build.id
    assert_equal "42", build.version
    assert_equal "VALID", build.processing_state
  end

  def test_localization_data_attributes
    loc = ASCTooling::LocalizationData.new({
                                             "id" => "loc-1",
                                             "attributes" => {
                                               "locale" => "en-US",
                                               "name" => "MyApp",
                                               "subtitle" => "The best app",
                                               "description" => "A description",
                                               "keywords" => "app,tool",
                                               "marketingUrl" => "https://example.com",
                                               "promotionalText" => "Try now",
                                               "supportUrl" => "https://example.com/support",
                                               "whatsNew" => "Bug fixes",
                                               "privacyPolicyUrl" => "https://example.com/privacy",
                                               "privacyChoicesUrl" => "https://example.com/choices"
                                             }
                                           })

    assert_equal "en-US", loc.locale
    assert_equal "MyApp", loc.name
    assert_equal "The best app", loc.subtitle
    assert_equal "A description", loc.description
    assert_equal "app,tool", loc.keywords
    assert_equal "https://example.com", loc.marketing_url
    assert_equal "Try now", loc.promotional_text
    assert_equal "https://example.com/support", loc.support_url
    assert_equal "Bug fixes", loc.whats_new
    assert_equal "https://example.com/privacy", loc.privacy_policy_url
    assert_equal "https://example.com/choices", loc.privacy_choices_url
  end

  def test_screenshot_set_data_resolves_screenshots
    included = [
      { "type" => "appScreenshots", "id" => "ss-1",
        "attributes" => { "fileName" => "shot1.png", "assetDeliveryState" => { "state" => "UPLOAD_COMPLETE" } } },
      { "type" => "appScreenshots", "id" => "ss-2", "attributes" => { "fileName" => "shot2.png", "assetDeliveryState" => { "state" => "COMPLETE" } } }
    ]
    set = ASCTooling::ScreenshotSetData.new(
      {
        "id" => "set-1",
        "attributes" => { "screenshotDisplayType" => "APP_DESKTOP" },
        "relationships" => {
          "appScreenshots" => {
            "data" => [
              { "type" => "appScreenshots", "id" => "ss-1" },
              { "type" => "appScreenshots", "id" => "ss-2" }
            ]
          }
        }
      },
      included: included
    )

    assert_equal "set-1", set.id
    assert_equal "APP_DESKTOP", set.screenshot_display_type
    assert_equal 2, set.screenshots.length
    assert_equal "shot1.png", set.screenshots.first.file_name
    assert_equal({ "state" => "UPLOAD_COMPLETE" }, set.screenshots.first.asset_delivery_state)
  end

  def test_screenshot_set_data_returns_empty_when_no_included
    set = ASCTooling::ScreenshotSetData.new({
                                              "id" => "set-1",
                                              "attributes" => { "screenshotDisplayType" => "APP_DESKTOP" },
                                              "relationships" => { "appScreenshots" => { "data" => [{ "type" => "appScreenshots",
                                                                                                      "id" => "ss-missing" }] } }
                                            })

    assert_equal [], set.screenshots
  end
end
