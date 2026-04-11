require "json"
require "optparse"
require "spaceship"

module ASCTooling
  class Screenshots
    def self.run(argv = ARGV)
      options = {
        platform: "macos",
        locale: "en-US",
        display_type: "APP_DESKTOP",
        source_dir: "build/app-store-screenshots",
        pattern: "*.png",
        keep_existing: false,
        wait_for_processing: true,
        command: argv.shift
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: asc-screenshots <status|upload> --bundle-id com.example.app [options]"

        opts.on("--bundle-id BUNDLE_ID", "App bundle identifier") { |value| options[:bundle_id] = value }
        opts.on("--app-version VERSION", "Editable App Store version to target") { |value| options[:app_version] = value }
        opts.on("--locale LOCALE", "Localization to read or update (default: en-US)") { |value| options[:locale] = value }
        opts.on("--platform PLATFORM", "ios, macos, or tvos (default: macos)") { |value| options[:platform] = value }
        opts.on("--display-type TYPE", "Screenshot display type (default: APP_DESKTOP)") { |value| options[:display_type] = value }
        opts.on("--source-dir PATH", "Directory containing screenshots to upload") { |value| options[:source_dir] = value }
        opts.on("--pattern GLOB", "Filename glob inside source dir (default: *.png)") { |value| options[:pattern] = value }
        opts.on("--keep-existing", "Append without clearing existing screenshots first") { options[:keep_existing] = true }
        opts.on("--no-wait", "Do not wait for screenshot processing to finish") { options[:wait_for_processing] = false }
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
      @asc = ASCTooling::Client.new(**ASCTooling::Client.auth_options_from(options))
    end

    def run
      case @options[:command]
      when "status" then print_status
      when "upload" then upload
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

    def display_type
      type = @options[:display_type]
      valid = Spaceship::ConnectAPI::AppScreenshotSet::DisplayType::ALL
      raise ArgumentError, "unsupported screenshot display type: #{type}" unless valid.include?(type)

      type
    end

    def print_status
      app = @asc.find_app!(@options[:bundle_id])
      version = @asc.find_editable_version!(app, platform: platform, app_version: @options[:app_version])
      version_localization = @asc.find_version_localization(version, @options[:locale])
      summary = summary_for_set(version_localization && @asc.find_screenshot_set(version_localization, display_type))
      summary[:app_name] = app.name
      summary[:bundle_id] = app.bundle_id
      summary[:version] = version.version_string
      summary[:locale] = @options[:locale]

      if @options[:json]
        puts JSON.pretty_generate(summary)
        return
      end

      puts "App: #{summary[:app_name]} (#{summary[:bundle_id]})"
      puts "Version: #{summary[:version]}"
      puts "Locale: #{summary[:locale]}"
      puts "Display type: #{summary[:display_type]}"
      puts "Screenshot set: #{summary[:set_id] || 'none'}"
      puts "Count: #{summary[:count]}"

      summary[:screenshots].each_with_index do |screenshot, index|
        puts "  #{index + 1}. #{screenshot[:file_name]} [#{screenshot[:state]}]"
      end
    end

    def upload
      source_paths = Dir.glob(File.join(File.expand_path(@options[:source_dir]), @options[:pattern])).sort
      raise ArgumentError, "no screenshots found in #{@options[:source_dir]} matching #{@options[:pattern]}" if source_paths.empty?

      app = @asc.find_app!(@options[:bundle_id])
      version = @asc.find_editable_version!(app, platform: platform, app_version: @options[:app_version])
      version_localization = @asc.find_or_create_version_localization!(version, @options[:locale])
      screenshot_set = @asc.find_or_create_screenshot_set!(version_localization, display_type)

      unless @options[:keep_existing]
        Array(screenshot_set.app_screenshots).each do |screenshot|
          screenshot.delete!(client: @asc.client)
        end
        screenshot_set = Spaceship::ConnectAPI::AppScreenshotSet.get(client: @asc.client, app_screenshot_set_id: screenshot_set.id)
      end

      uploaded = source_paths.each_with_index.map do |path, index|
        screenshot_set.upload_screenshot(
          client: @asc.client,
          path: path,
          wait_for_processing: @options[:wait_for_processing],
          position: @options[:keep_existing] ? nil : index
        )
      end

      puts "Uploaded #{uploaded.size} screenshots to #{app.bundle_id} #{@options[:locale]} #{display_type}"
    end

    def summary_for_set(screenshot_set)
      screenshots = Array(screenshot_set&.app_screenshots).map do |screenshot|
        {
          id: screenshot.id,
          file_name: screenshot.file_name,
          state: screenshot.asset_delivery_state&.fetch("state", nil) || "UNKNOWN"
        }
      end

      {
        set_id: screenshot_set&.id,
        display_type: screenshot_set&.screenshot_display_type || display_type,
        count: screenshots.size,
        screenshots: screenshots
      }
    end
  end
end
