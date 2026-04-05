require "json"
require "net/http"
require "spaceship"
require "uri"

module ASCTooling
  class APIError < StandardError
    attr_reader :operation, :status, :payload

    def initialize(operation, status, payload)
      super("#{operation} failed with HTTP #{status}")
      @operation = operation
      @status = status
      @payload = payload
    end
  end

  class Client
    EDITABLE_STATES = %w[
      PREPARE_FOR_SUBMISSION
      DEVELOPER_REJECTED
      REJECTED
      METADATA_REJECTED
      READY_FOR_REVIEW
      WAITING_FOR_REVIEW
      INVALID_BINARY
    ].freeze

    PLATFORM_MAP = {
      "ios" => "IOS",
      "mac" => "MAC_OS",
      "macos" => "MAC_OS",
      "osx" => "MAC_OS",
      "tvos" => "TV_OS"
    }.freeze

    def self.blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def self.option_or_env(options, key, *env_names)
      value = options[key]
      return value unless blank?(value)

      env_names.each do |env_name|
        env_value = ENV[env_name]
        return env_value unless blank?(env_value)
      end

      nil
    end

    attr_reader :client

    def initialize(key_id: nil, issuer_id: nil, key_path: nil)
      @key_id = key_id
      @issuer_id = issuer_id
      @key_path = key_path
      @client = Spaceship::ConnectAPI
      normalize_proxy_env!
      authenticate!
    end

    def platform(value)
      normalized = value.to_s.downcase
      PLATFORM_MAP.fetch(normalized) do
        raise ArgumentError, "unsupported platform: #{value}"
      end
    end

    def find_app!(bundle_id)
      app = client.get_apps(filter: { bundleId: bundle_id }, limit: 1).first
      raise ArgumentError, "app not found for bundle id #{bundle_id}" unless app

      app
    end

    def find_editable_version!(app, platform:, app_version: nil)
      filter = {
        "filter[platform]" => platform,
        "filter[appStoreState]" => EDITABLE_STATES.join(",")
      }
      data = request_json(
        "GET",
        "/v1/apps/#{app.id}/appStoreVersions",
        params: filter.merge("include" => "build", "limit" => "50")
      )
      versions = data.fetch("data", [])
      versions.select! { |item| item.dig("attributes", "versionString") == app_version } if app_version

      selected = versions.max_by { |item| Gem::Version.new(item.dig("attributes", "versionString")) }
      raise ArgumentError, "editable version not found" unless selected

      Spaceship::ConnectAPI::AppStoreVersion.get(
        app_store_version_id: selected["id"],
        includes: "build"
      )
    end

    def find_version_localization(version, locale)
      version
        .get_app_store_version_localizations(client: client, filter: { locale: locale }, limit: 50)
        .find { |item| item.locale == locale }
    end

    def find_or_create_version_localization!(version, locale)
      find_version_localization(version, locale) ||
        version.create_app_store_version_localization(client: client, attributes: { locale: locale })
    end

    def fetch_edit_app_info!(app)
      app_info = app.fetch_edit_app_info(client: client)
      raise ArgumentError, "editable app info not found" unless app_info

      app_info
    end

    def find_app_info_localization(app, locale)
      app_info = fetch_edit_app_info!(app)
      localization = app_info
        .get_app_info_localizations(client: client, filter: { locale: locale }, limit: 50)
        .find { |item| item.locale == locale }

      [app_info, localization]
    end

    def find_or_create_app_info_localization!(app, locale)
      app_info, localization = find_app_info_localization(app, locale)
      localization ||= app_info.create_app_info_localization(client: client, attributes: { locale: locale })
      [app_info, localization]
    end

    def find_screenshot_set(version_localization, display_type)
      version_localization
        .get_app_screenshot_sets(
          client: client,
          filter: { screenshotDisplayType: display_type },
          includes: "appScreenshots",
          limit: 50
        )
        .find { |item| item.screenshot_display_type == display_type }
    end

    def find_or_create_screenshot_set!(version_localization, display_type)
      set = find_screenshot_set(version_localization, display_type)
      set ||= version_localization.create_app_screenshot_set(
        client: client,
        attributes: { screenshotDisplayType: display_type }
      )
      Spaceship::ConnectAPI::AppScreenshotSet.get(client: client, app_screenshot_set_id: set.id)
    end

    def request_json(method, path, params: nil, body: nil)
      uri = URI("https://api.appstoreconnect.apple.com#{path}")
      uri.query = URI.encode_www_form(params) if params && !params.empty?

      request_class = case method
                      when "GET" then Net::HTTP::Get
                      when "POST" then Net::HTTP::Post
                      when "PATCH" then Net::HTTP::Patch
                      when "DELETE" then Net::HTTP::Delete
                      else
                        raise ArgumentError, "unsupported method: #{method}"
                      end

      request = request_class.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json" if body
      request.body = JSON.dump(body) if body

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      payload = response.body.to_s.empty? ? {} : JSON.parse(response.body)
      return payload if response.code.to_i.between?(200, 299)

      raise APIError.new("#{method} #{path}", response.code.to_i, payload)
    end

    def format_api_errors(payload)
      errors = payload.fetch("errors", [])
      return JSON.pretty_generate(payload) if errors.empty?

      lines = errors.flat_map do |error|
        messages = ["- #{error['title']}"]
        messages << "  #{error['detail']}" unless self.class.blank?(error["detail"])

        associated = error.dig("meta", "associatedErrors") || {}
        associated.each_value do |items|
          Array(items).each do |item|
            messages << "  blocker: #{item['title']}"
            messages << "  #{item['detail']}" unless self.class.blank?(item["detail"])
          end
        end

        messages
      end

      lines.join("\n")
    end

    private

    def token
      Spaceship::ConnectAPI.token.text
    end

    def authenticate!
      key_id = @key_id
      issuer_id = @issuer_id
      key_path = @key_path

      missing = []
      missing << "key id" if self.class.blank?(key_id)
      missing << "issuer id" if self.class.blank?(issuer_id)
      missing << "key path" if self.class.blank?(key_path)
      raise ArgumentError, "missing #{missing.join(', ')}" unless missing.empty?

      expanded_key_path = File.expand_path(key_path)
      raise ArgumentError, "key file not found: #{key_path}" unless File.exist?(expanded_key_path)

      Spaceship::ConnectAPI.auth(
        key_id: key_id,
        issuer_id: issuer_id,
        filepath: expanded_key_path,
        duration: 1200,
        in_house: false
      )
    end

    def normalize_proxy_env!
      if self.class.blank?(ENV["http_proxy"]) && !self.class.blank?(ENV["HTTP_PROXY"])
        ENV["http_proxy"] = ENV["HTTP_PROXY"]
      end
      if self.class.blank?(ENV["https_proxy"]) && !self.class.blank?(ENV["HTTPS_PROXY"])
        ENV["https_proxy"] = ENV["HTTPS_PROXY"]
      end

      ENV.delete("HTTP_PROXY")
      ENV.delete("HTTPS_PROXY")
    end
  end
end
