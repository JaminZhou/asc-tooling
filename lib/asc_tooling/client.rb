require "digest"
require "json"
require "jwt"
require "net/http"
require "openssl"
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
    KEY_ID_ENV_NAMES = %w[
      ASC_KEY_ID
      APP_STORE_CONNECT_API_KEY_KEY_ID
    ].freeze
    ISSUER_ID_ENV_NAMES = %w[
      ASC_ISSUER_ID
      APP_STORE_CONNECT_API_ISSUER_ID
    ].freeze
    KEY_PATH_ENV_NAMES = %w[
      ASC_KEY_PATH
      APP_STORE_CONNECT_API_KEY_KEY_FILEPATH
    ].freeze

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

    RELEASE_TYPE_MAP = {
      "after-approval" => "AFTER_APPROVAL",
      "manual" => "MANUAL"
    }.freeze

    JWT_DURATION_SECONDS = 1200
    MAX_REDIRECTS = 5
    DEFAULT_PAGE_LIMIT = 50
    HTTP_OPEN_TIMEOUT = 30
    HTTP_READ_TIMEOUT = 60

    def self.blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def self.option_or_env(options, key, *env_names)
      value = options[key]
      return value unless blank?(value)

      env_names.each do |env_name|
        env_value = ENV.fetch(env_name, nil)
        return env_value unless blank?(env_value)
      end

      nil
    end

    def self.auth_options_from(options = {})
      {
        key_id: option_or_env(options, :key_id, *KEY_ID_ENV_NAMES),
        issuer_id: option_or_env(options, :issuer_id, *ISSUER_ID_ENV_NAMES),
        key_path: option_or_env(options, :key_path, *KEY_PATH_ENV_NAMES)
      }
    end

    def initialize(key_id: nil, issuer_id: nil, key_path: nil)
      auth_options = self.class.auth_options_from(
        key_id: key_id,
        issuer_id: issuer_id,
        key_path: key_path
      )
      @key_id = auth_options[:key_id]
      @issuer_id = auth_options[:issuer_id]
      @key_path = auth_options[:key_path]
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
      data = request_json("GET", "/v1/apps", params: {
                            "filter[bundleId]" => bundle_id,
                            "limit" => "1"
                          })
      app_data = data.fetch("data", []).first
      raise ArgumentError, "app not found for bundle id #{bundle_id}" unless app_data

      AppData.new(app_data)
    end

    def find_editable_version!(app, platform:, app_version: nil)
      find_version!(app, platform: platform, app_version: app_version, states: EDITABLE_STATES)
    end

    def find_version!(app, platform:, app_version: nil, states: nil)
      filter = {
        "filter[platform]" => platform
      }
      filter["filter[appStoreState]"] = Array(states).join(",") if states && !states.empty?
      data = request_json(
        "GET",
        "/v1/apps/#{app.id}/appStoreVersions",
        params: filter.merge("include" => "build", "limit" => DEFAULT_PAGE_LIMIT.to_s)
      )
      versions = data.fetch("data", [])
      versions.select! { |item| item.dig("attributes", "versionString") == app_version } if app_version

      selected = versions.max_by { |item| Gem::Version.new(item.dig("attributes", "versionString")) }
      raise ArgumentError, app_version ? "version #{app_version} not found" : "app store version not found" unless selected

      included = data.fetch("included", [])
      VersionData.new(selected, included: included)
    end

    def find_version_localization(version, locale)
      data = request_json(
        "GET",
        "/v1/appStoreVersions/#{version.id}/appStoreVersionLocalizations",
        params: { "filter[locale]" => locale, "limit" => DEFAULT_PAGE_LIMIT.to_s }
      )
      found = data.fetch("data", []).find { |item| item.dig("attributes", "locale") == locale }
      found ? LocalizationData.new(found) : nil
    end

    def find_or_create_version_localization!(version, locale)
      find_version_localization(version, locale) || create_version_localization(version, locale)
    end

    def fetch_edit_app_info!(app)
      data = request_json(
        "GET",
        "/v1/apps/#{app.id}/appInfos",
        params: { "limit" => DEFAULT_PAGE_LIMIT.to_s }
      )
      app_info = data.fetch("data", []).first
      raise ArgumentError, "editable app info not found" unless app_info

      APIResource.new(app_info)
    end

    def find_app_info_localization(app, locale)
      app_info = fetch_edit_app_info!(app)
      data = request_json(
        "GET",
        "/v1/appInfos/#{app_info.id}/appInfoLocalizations",
        params: { "filter[locale]" => locale, "limit" => DEFAULT_PAGE_LIMIT.to_s }
      )
      found = data.fetch("data", []).find { |item| item.dig("attributes", "locale") == locale }
      localization = found ? LocalizationData.new(found) : nil

      [app_info, localization]
    end

    def create_app_info_localization!(app_info, locale, name:)
      request_json(
        "POST",
        "/v1/appInfoLocalizations",
        body: {
          data: {
            type: "appInfoLocalizations",
            attributes: {
              locale: locale,
              name: name
            },
            relationships: {
              appInfo: {
                data: {
                  type: "appInfos",
                  id: app_info.id
                }
              }
            }
          }
        }
      )
    end

    def find_or_create_app_info_localization!(app, locale, name: nil)
      app_info, localization = find_app_info_localization(app, locale)
      unless localization
        create_app_info_localization!(app_info, locale, name: name || app.name)
        _, localization = find_app_info_localization(app, locale)
      end

      [app_info, localization]
    end

    def find_screenshot_set(version_localization, display_type)
      data = request_json(
        "GET",
        "/v1/appStoreVersionLocalizations/#{version_localization.id}/appScreenshotSets",
        params: {
          "filter[screenshotDisplayType]" => display_type,
          "include" => "appScreenshots",
          "limit" => DEFAULT_PAGE_LIMIT.to_s
        }
      )
      included = data.fetch("included", [])
      found = data.fetch("data", []).find { |item| item.dig("attributes", "screenshotDisplayType") == display_type }
      found ? ScreenshotSetData.new(found, included: included) : nil
    end

    def find_or_create_screenshot_set!(version_localization, display_type)
      set = find_screenshot_set(version_localization, display_type)
      unless set
        created = request_json(
          "POST",
          "/v1/appScreenshotSets",
          body: {
            data: {
              type: "appScreenshotSets",
              attributes: { screenshotDisplayType: display_type },
              relationships: {
                appStoreVersionLocalization: {
                  data: { type: "appStoreVersionLocalizations", id: version_localization.id }
                }
              }
            }
          }
        ).fetch("data")
        set = ScreenshotSetData.new(created)
      end
      set
    end

    def build_candidates(app_id, app_version = nil, limit: 20)
      params = {
        "filter[app]" => app_id,
        "sort" => "-uploadedDate",
        "limit" => limit.to_s
      }
      params["filter[preReleaseVersion.version]"] = app_version unless self.class.blank?(app_version)

      request_json("GET", "/v1/builds", params: params).fetch("data", [])
    end

    def update_resource(type, id, attributes:)
      request_json(
        "PATCH",
        "/v1/#{type}/#{id}",
        body: { data: { type: type, id: id, attributes: camelize_keys(attributes) } }
      )
    end

    def delete_resource(path)
      request_json("DELETE", path)
    end

    def upload_asset(operations, bytes)
      operations.each do |operation|
        uri = URI(operation["url"])
        headers = (operation["requestHeaders"] || []).to_h { |h| [h["name"], h["value"]] }
        chunk = bytes.byteslice(operation["offset"], operation["length"])

        request = Net::HTTP::Put.new(uri)
        headers.each { |k, v| request[k] = v }
        request.body = chunk

        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.open_timeout = HTTP_OPEN_TIMEOUT
          http.read_timeout = HTTP_READ_TIMEOUT
          response = http.request(request)
          raise APIError.new("PUT #{uri.path}", response.code.to_i, {}) unless response.code.to_i.between?(200, 299)
        end
      end
    end

    def upload_screenshot(set_id, path:, position: nil)
      bytes = File.binread(path)
      file_name = File.basename(path)

      reserve = request_json(
        "POST",
        "/v1/appScreenshots",
        body: {
          data: {
            type: "appScreenshots",
            attributes: {
              fileName: file_name,
              fileSize: bytes.bytesize
            },
            relationships: {
              appScreenshotSet: {
                data: { type: "appScreenshotSets", id: set_id }
              }
            }
          }
        }
      ).fetch("data")

      upload_asset(reserve.dig("attributes", "uploadOperations") || [], bytes)

      committed = request_json(
        "PATCH",
        "/v1/appScreenshots/#{reserve['id']}",
        body: {
          data: {
            type: "appScreenshots",
            id: reserve["id"],
            attributes: {
              uploaded: true,
              sourceFileChecksum: Digest::MD5.hexdigest(bytes)
            }
          }
        }
      ).fetch("data")

      if position
        request_json(
          "PATCH",
          "/v1/appScreenshotSets/#{set_id}/relationships/appScreenshots",
          body: {
            data: reorder_screenshots(set_id, committed["id"], position)
          }
        )
      end

      ScreenshotData.new(committed)
    end

    def request_json(method, path, params: nil, body: nil)
      response = request_response(
        method,
        path,
        params: params,
        body: body,
        accept: "application/json"
      )
      payload = response.body.to_s.empty? ? {} : JSON.parse(response.body)
      return payload if response.code.to_i.between?(200, 299)

      raise APIError.new("#{method} #{path}", response.code.to_i, payload)
    end

    def request_blob(method, path, params: nil, body: nil, accept: "application/a-gzip")
      response = request_response(
        method,
        path,
        params: params,
        body: body,
        accept: accept
      )
      return response.body.to_s.b if response.code.to_i.between?(200, 299)

      payload = begin
        response.body.to_s.empty? ? {} : JSON.parse(response.body)
      rescue JSON::ParserError
        { "raw" => response.body.to_s }
      end
      raise APIError.new("#{method} #{path}", response.code.to_i, payload)
    end

    def api_error_codes(payload)
      errors = payload.fetch("errors", [])
      direct_codes = errors.filter_map { |error| error["code"] }
      associated_codes = errors.flat_map do |error|
        associated = error.dig("meta", "associatedErrors") || {}
        associated.values.flatten.filter_map { |item| item["code"] }
      end

      (direct_codes + associated_codes).uniq
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

    def create_version_localization(version, locale)
      data = request_json(
        "POST",
        "/v1/appStoreVersionLocalizations",
        body: {
          data: {
            type: "appStoreVersionLocalizations",
            attributes: { locale: locale },
            relationships: {
              appStoreVersion: {
                data: { type: "appStoreVersions", id: version.id }
              }
            }
          }
        }
      ).fetch("data")
      LocalizationData.new(data)
    end

    def camelize_keys(hash)
      hash.transform_keys { |key| key.to_s.gsub(/_([a-z])/) { ::Regexp.last_match(1).upcase } }
    end

    def reorder_screenshots(set_id, new_screenshot_id, position)
      data = request_json(
        "GET",
        "/v1/appScreenshotSets/#{set_id}/relationships/appScreenshots"
      )
      ids = data.fetch("data", []).map { |item| { type: "appScreenshots", id: item["id"] } }
      ids.reject! { |item| item[:id] == new_screenshot_id }
      ids.insert(position, { type: "appScreenshots", id: new_screenshot_id })
      ids
    end

    def request_response(method, path, params: nil, body: nil, accept: "application/json")
      uri = URI("https://api.appstoreconnect.apple.com#{path}")
      uri.query = URI.encode_www_form(params) if params && !params.empty?

      request = build_request(method, uri, body: body, accept: accept)
      perform_request(uri, request, method: method, body: body, accept: accept)
    end

    def build_request(method, uri, body:, accept:)
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
      request["Accept"] = accept
      request["Content-Type"] = "application/json" if body
      request.body = JSON.dump(body) if body
      request
    end

    def perform_request(uri, request, method:, body:, accept:, redirects_remaining: MAX_REDIRECTS)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.open_timeout = HTTP_OPEN_TIMEOUT
        http.read_timeout = HTTP_READ_TIMEOUT
        http.request(request)
      end

      return response unless response.is_a?(Net::HTTPRedirection)
      raise ArgumentError, "too many redirects for #{uri}" if redirects_remaining <= 0

      location = response["location"]
      raise ArgumentError, "missing redirect location for #{uri}" if self.class.blank?(location)

      redirected_uri = URI(location)
      redirected_request = build_request(method, redirected_uri, body: body, accept: accept)
      perform_request(
        redirected_uri,
        redirected_request,
        method: method,
        body: body,
        accept: accept,
        redirects_remaining: redirects_remaining - 1
      )
    end

    def token
      now = Time.now.to_i
      return @token_text if @token_text && @token_expiry && now < @token_expiry - 60

      payload = {
        iss: @issuer_id,
        iat: now,
        exp: now + JWT_DURATION_SECONDS,
        aud: "appstoreconnect-v1"
      }
      @token_text = JWT.encode(payload, @private_key, "ES256", { kid: @key_id })
      @token_expiry = payload[:exp]
      @token_text
    end

    def authenticate!
      missing = []
      missing << "key id" if self.class.blank?(@key_id)
      missing << "issuer id" if self.class.blank?(@issuer_id)
      missing << "key path" if self.class.blank?(@key_path)
      raise ArgumentError, "missing #{missing.join(', ')}" unless missing.empty?

      expanded_key_path = File.expand_path(@key_path)
      raise ArgumentError, "key file not found: #{@key_path}" unless File.exist?(expanded_key_path)

      @private_key = OpenSSL::PKey::EC.new(File.read(expanded_key_path))
    end

    def normalize_proxy_env!
      if self.class.blank?(ENV.fetch("http_proxy", nil)) && !self.class.blank?(ENV.fetch("HTTP_PROXY", nil))
        ENV["http_proxy"] = ENV.fetch("HTTP_PROXY", nil)
      end
      if self.class.blank?(ENV.fetch("https_proxy", nil)) && !self.class.blank?(ENV.fetch("HTTPS_PROXY", nil))
        ENV["https_proxy"] = ENV.fetch("HTTPS_PROXY", nil)
      end

      ENV.delete("HTTP_PROXY")
      ENV.delete("HTTPS_PROXY")
    end
  end
end
