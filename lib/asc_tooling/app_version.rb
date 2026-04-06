require "json"
require "optparse"

module ASCTooling
  class AppVersion
    RELEASE_TYPE_MAP = {
      "after-approval" => "AFTER_APPROVAL",
      "manual" => "MANUAL"
    }.freeze

    def self.run(argv = ARGV)
      options = {
        platform: "macos",
        command: argv.shift
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: asc-version <create> --bundle-id com.example.app --version 1.0.0 [options]"

        opts.on("--bundle-id BUNDLE_ID", "App bundle identifier") { |value| options[:bundle_id] = value }
        opts.on("--version VERSION", "Version string to create") { |value| options[:version] = value }
        opts.on("--platform PLATFORM", "ios, macos, or tvos (default: macos)") { |value| options[:platform] = value }
        opts.on("--copyright TEXT", "Copyright text") { |value| options[:copyright] = value }
        opts.on("--release-type TYPE", "manual or after-approval (default: manual)") { |value| options[:release_type] = value }
        opts.on("--key-id KEY_ID", "ASC API key id") { |value| options[:key_id] = value }
        opts.on("--issuer-id ISSUER_ID", "ASC API issuer id") { |value| options[:issuer_id] = value }
        opts.on("--key-path PATH", "Path to ASC API .p8 key") { |value| options[:key_path] = value }
        opts.on("--json", "Print output as JSON") { options[:json] = true }
      end

      parser.parse!(argv)

      if options[:command].nil? || options[:bundle_id].nil?
        warn parser.banner
        return 1
      end

      new(options).run
      0
    end

    def initialize(options)
      @options = options
      @asc = ASCTooling::Client.new(
        key_id: ASCTooling::Client.option_or_env(options, :key_id, "ASC_KEY_ID", "APP_STORE_CONNECT_API_KEY_KEY_ID"),
        issuer_id: ASCTooling::Client.option_or_env(options, :issuer_id, "ASC_ISSUER_ID", "APP_STORE_CONNECT_API_ISSUER_ID"),
        key_path: ASCTooling::Client.option_or_env(options, :key_path, "ASC_KEY_PATH", "APP_STORE_CONNECT_API_KEY_KEY_FILEPATH")
      )
    end

    def run
      case @options[:command]
      when "create" then create_version
      else
        raise OptionParser::InvalidArgument, "unknown command: #{@options[:command]}"
      end
    rescue ASCTooling::APIError => e
      warn e.message
      warn @asc.format_api_errors(e.payload)
      exit 1
    rescue ArgumentError, OptionParser::ParseError => e
      warn e.message
      exit 1
    end

    private

    def platform
      @platform ||= @asc.platform(@options[:platform])
    end

    def create_version
      raise OptionParser::MissingArgument, "--version is required" unless @options[:version]

      app = @asc.find_app!(@options[:bundle_id])

      attributes = {
        platform: platform,
        versionString: @options[:version]
      }

      if @options[:release_type]
        attributes[:releaseType] = RELEASE_TYPE_MAP.fetch(@options[:release_type]) do
          raise OptionParser::InvalidArgument, "unsupported release type: #{@options[:release_type]}"
        end
      end

      attributes[:copyright] = @options[:copyright] if @options[:copyright]

      result = @asc.request_json("POST", "/v1/appStoreVersions", body: {
        data: {
          type: "appStoreVersions",
          attributes: attributes,
          relationships: {
            app: {
              data: { type: "apps", id: app.id }
            }
          }
        }
      })

      version_data = result.fetch("data")
      attrs = version_data.fetch("attributes", {})

      summary = {
        id: version_data["id"],
        version: attrs["versionString"],
        state: attrs["appStoreState"],
        release_type: attrs["releaseType"],
        copyright: attrs["copyright"]
      }

      if @options[:json]
        puts JSON.pretty_generate(summary)
        return
      end

      puts "Created version #{summary[:version]} [#{summary[:state]}]"
      puts "Release type: #{summary[:release_type]}" if summary[:release_type]
      puts "Copyright: #{summary[:copyright]}" if summary[:copyright]
    end
  end
end
