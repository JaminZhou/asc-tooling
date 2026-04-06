require "json"
require "optparse"

module ASCTooling
  class Metadata
    VERSION_FIELD_OPTIONS = {
      description: :description_file,
      keywords: nil,
      marketing_url: nil,
      promotional_text: :promotional_text_file,
      support_url: nil,
      whats_new: :whats_new_file
    }.freeze

    APP_INFO_FIELD_OPTIONS = {
      name: nil,
      subtitle: nil,
      privacy_policy_url: nil,
      privacy_choices_url: nil
    }.freeze

    VERSION_DIRECT_OPTIONS = {
      copyright: nil
    }.freeze

    def self.run(argv = ARGV)
      options = {
        platform: "macos",
        locale: "en-US",
        command: argv.shift
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: asc-metadata <status|apply> --bundle-id com.example.app [options]"

        opts.on("--bundle-id BUNDLE_ID", "App bundle identifier") { |value| options[:bundle_id] = value }
        opts.on("--app-version VERSION", "Editable App Store version to target") { |value| options[:app_version] = value }
        opts.on("--locale LOCALE", "Localization to read or update (default: en-US)") { |value| options[:locale] = value }
        opts.on("--platform PLATFORM", "ios, macos, or tvos (default: macos)") { |value| options[:platform] = value }
        opts.on("--name NAME", "Localized app name") { |value| options[:name] = value }
        opts.on("--subtitle SUBTITLE", "Localized subtitle") { |value| options[:subtitle] = value }
        opts.on("--privacy-policy-url URL", "Privacy policy URL") { |value| options[:privacy_policy_url] = value }
        opts.on("--privacy-choices-url URL", "Privacy choices URL") { |value| options[:privacy_choices_url] = value }
        opts.on("--description TEXT", "Version description") { |value| options[:description] = value }
        opts.on("--description-file PATH", "Read version description from a file") { |value| options[:description_file] = value }
        opts.on("--keywords TEXT", "Comma-separated keywords") { |value| options[:keywords] = value }
        opts.on("--marketing-url URL", "Marketing URL") { |value| options[:marketing_url] = value }
        opts.on("--promotional-text TEXT", "Promotional text") { |value| options[:promotional_text] = value }
        opts.on("--promotional-text-file PATH", "Read promotional text from a file") { |value| options[:promotional_text_file] = value }
        opts.on("--support-url URL", "Support URL") { |value| options[:support_url] = value }
        opts.on("--whats-new TEXT", "What's New text") { |value| options[:whats_new] = value }
        opts.on("--whats-new-file PATH", "Read What's New text from a file") { |value| options[:whats_new_file] = value }
        opts.on("--copyright TEXT", "Copyright text (version-level, not localized)") { |value| options[:copyright] = value }
        opts.on("--key-id KEY_ID", "ASC API key id") { |value| options[:key_id] = value }
        opts.on("--issuer-id ISSUER_ID", "ASC API issuer id") { |value| options[:issuer_id] = value }
        opts.on("--key-path PATH", "Path to ASC API .p8 key") { |value| options[:key_path] = value }
        opts.on("--json", "Print status output as JSON") { options[:json] = true }
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
      when "status" then print_status
      when "apply" then apply
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

    def print_status
      app = @asc.find_app!(@options[:bundle_id])
      version = @asc.find_editable_version!(app, platform: platform, app_version: @options[:app_version])
      _, app_info_localization = @asc.find_app_info_localization(app, @options[:locale])
      version_localization = @asc.find_version_localization(version, @options[:locale])

      summary = {
        app: {
          name: app.name,
          bundle_id: app.bundle_id
        },
        locale: @options[:locale],
        version: version.version_string,
        copyright: version.copyright,
        app_info_localization: app_info_localization && {
          name: app_info_localization.name,
          subtitle: app_info_localization.subtitle,
          privacy_policy_url: app_info_localization.privacy_policy_url,
          privacy_choices_url: app_info_localization.privacy_choices_url
        },
        version_localization: version_localization && {
          description: version_localization.description,
          keywords: version_localization.keywords,
          marketing_url: version_localization.marketing_url,
          promotional_text: version_localization.promotional_text,
          support_url: version_localization.support_url,
          whats_new: version_localization.whats_new
        }
      }

      if @options[:json]
        puts JSON.pretty_generate(summary)
        return
      end

      puts "App: #{summary.dig(:app, :name)} (#{summary.dig(:app, :bundle_id)})"
      puts "Version: #{summary[:version]}"
      puts "Copyright: #{summary[:copyright] || '-'}"
      puts "Locale: #{summary[:locale]}"

      if summary[:app_info_localization]
        puts "App info:"
        summary[:app_info_localization].each do |key, value|
          puts "  #{key}: #{value || '-'}"
        end
      else
        puts "App info localization: none"
      end

      if summary[:version_localization]
        puts "Version metadata:"
        summary[:version_localization].each do |key, value|
          puts "  #{key}: #{value || '-'}"
        end
      else
        puts "Version localization: none"
      end
    end

    def apply
      app = @asc.find_app!(@options[:bundle_id])
      version = @asc.find_editable_version!(app, platform: platform, app_version: @options[:app_version])

      app_info_attributes = resolved_attributes(APP_INFO_FIELD_OPTIONS)
      version_attributes = resolved_attributes(VERSION_FIELD_OPTIONS)
      version_direct_attributes = resolved_attributes(VERSION_DIRECT_OPTIONS)
      raise OptionParser::MissingArgument, "no metadata fields provided" if app_info_attributes.empty? && version_attributes.empty? && version_direct_attributes.empty?

      updated_sections = []

      unless version_direct_attributes.empty?
        version.update(client: @asc.client, attributes: version_direct_attributes)
        updated_sections << "version info"
      end

      unless app_info_attributes.empty?
        _, app_info_localization = @asc.find_or_create_app_info_localization!(app, @options[:locale])
        app_info_localization.update(client: @asc.client, attributes: app_info_attributes)
        updated_sections << "app info"
      end

      unless version_attributes.empty?
        version_localization = @asc.find_or_create_version_localization!(version, @options[:locale])
        version_localization.update(client: @asc.client, attributes: version_attributes)
        updated_sections << "version metadata"
      end

      puts "Updated #{updated_sections.join(' and ')} for #{@options[:bundle_id]} #{@options[:locale]} on version #{version.version_string}"
    end

    def resolved_attributes(fields)
      fields.each_with_object({}) do |(attribute_key, file_key), attrs|
        value = @options[attribute_key]
        value = File.read(File.expand_path(@options[file_key])).strip if value.nil? && file_key && @options[file_key]
        next if value.nil?

        attrs[attribute_key] = value
      end
    end
  end
end
