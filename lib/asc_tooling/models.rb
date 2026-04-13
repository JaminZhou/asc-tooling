module ASCTooling
  class APIResource
    attr_reader :id, :raw

    def initialize(data, included: nil)
      @raw = data
      @id = data["id"]
      @included = included
    end

    private

    def attributes
      @raw.fetch("attributes", {})
    end

    def find_included(type, id)
      return nil unless @included

      @included.find { |item| item["type"] == type && item["id"] == id }
    end
  end

  class AppData < APIResource
    def name
      attributes["name"]
    end

    def bundle_id
      attributes["bundleId"]
    end
  end

  class VersionData < APIResource
    def version_string
      attributes["versionString"]
    end

    def app_store_state
      attributes["appStoreState"]
    end

    def release_type
      attributes["releaseType"]
    end

    def copyright
      attributes["copyright"]
    end

    def build
      build_ref = @raw.dig("relationships", "build", "data")
      return nil unless build_ref

      build_data = find_included("builds", build_ref["id"])
      build_data ? BuildData.new(build_data) : nil
    end
  end

  class BuildData < APIResource
    def version
      attributes["version"]
    end

    def processing_state
      attributes["processingState"]
    end
  end

  class LocalizationData < APIResource
    def locale
      attributes["locale"]
    end

    def name
      attributes["name"]
    end

    def subtitle
      attributes["subtitle"]
    end

    def description
      attributes["description"]
    end

    def keywords
      attributes["keywords"]
    end

    def marketing_url
      attributes["marketingUrl"]
    end

    def promotional_text
      attributes["promotionalText"]
    end

    def support_url
      attributes["supportUrl"]
    end

    def whats_new
      attributes["whatsNew"]
    end

    def privacy_policy_url
      attributes["privacyPolicyUrl"]
    end

    def privacy_choices_url
      attributes["privacyChoicesUrl"]
    end
  end

  class ScreenshotSetData < APIResource
    def screenshot_display_type
      attributes["screenshotDisplayType"]
    end

    def screenshots
      refs = @raw.dig("relationships", "appScreenshots", "data") || []
      refs.filter_map do |ref|
        data = find_included("appScreenshots", ref["id"])
        ScreenshotData.new(data) if data
      end
    end
  end

  class ScreenshotData < APIResource
    def file_name
      attributes["fileName"]
    end

    def asset_delivery_state
      attributes["assetDeliveryState"]
    end
  end
end
