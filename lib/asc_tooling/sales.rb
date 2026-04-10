require "csv"
require "date"
require "json"
require "optparse"
require "stringio"
require "zlib"

module ASCTooling
  class Sales
    DEFAULT_REPORT_TYPE = "SALES".freeze
    DEFAULT_REPORT_SUBTYPE = "SUMMARY".freeze
    DEFAULT_FREQUENCY = "DAILY".freeze
    DEFAULT_REPORT_VERSION = "1_1".freeze

    DOWNLOAD_PRODUCT_TYPES = %w[1 1E 1EP 1EU 1F 1T F1].freeze
    REDOWNLOAD_PRODUCT_TYPES = %w[3 3F F3].freeze
    UPDATE_PRODUCT_TYPES = %w[7 7F F7].freeze

    def self.run(argv = ARGV)
      options = {
        command: argv.shift,
        report_type: DEFAULT_REPORT_TYPE,
        report_subtype: DEFAULT_REPORT_SUBTYPE,
        frequency: DEFAULT_FREQUENCY,
        report_version: DEFAULT_REPORT_VERSION,
        platform: "macos"
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: asc-sales <report|units> [options]"

        opts.on("--bundle-id BUNDLE_ID", "App bundle identifier (required for units)") { |value| options[:bundle_id] = value }
        opts.on("--vendor-number VENDOR_NUMBER", "Sales and Trends vendor number") { |value| options[:vendor_number] = value }
        opts.on("--report-type TYPE", "Report type (default: #{DEFAULT_REPORT_TYPE})") { |value| options[:report_type] = value }
        opts.on("--report-subtype TYPE", "Report subtype (default: #{DEFAULT_REPORT_SUBTYPE})") { |value| options[:report_subtype] = value }
        opts.on("--frequency FREQUENCY", "Report frequency (default: #{DEFAULT_FREQUENCY})") { |value| options[:frequency] = value }
        opts.on("--report-date DATE", "Report date in YYYY-MM-DD") { |value| options[:report_date] = value }
        opts.on("--report-version VERSION", "Report version (default: #{DEFAULT_REPORT_VERSION})") { |value| options[:report_version] = value }
        opts.on("--country COUNTRY", "Filter units output to a country code such as US") { |value| options[:country] = value }
        opts.on("--output PATH", "Write the downloaded TSV report to a file") { |value| options[:output] = value }
        opts.on("--platform PLATFORM", "ios, macos, or tvos (default: macos)") { |value| options[:platform] = value }
        opts.on("--key-id KEY_ID", "ASC API key id") { |value| options[:key_id] = value }
        opts.on("--issuer-id ISSUER_ID", "ASC API issuer id") { |value| options[:issuer_id] = value }
        opts.on("--key-path PATH", "Path to ASC API .p8 key") { |value| options[:key_path] = value }
        opts.on("--json", "Print units output as JSON") { options[:json] = true }
      end

      parser.parse!(argv)

      if options[:command].nil?
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
      when "report" then print_report
      when "units" then print_units
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

    def vendor_number
      vendor = ASCTooling::Client.option_or_env(
        @options,
        :vendor_number,
        "ASC_VENDOR_NUMBER",
        "APP_STORE_CONNECT_VENDOR_NUMBER"
      )
      raise OptionParser::MissingArgument, "--vendor-number is required" if ASCTooling::Client.blank?(vendor)

      vendor
    end

    def print_report
      text = report_text
      if @options[:output]
        output_path = File.expand_path(@options[:output])
        File.write(output_path, text)
        puts "Saved report to #{output_path}"
      else
        puts text
      end
    end

    def print_units
      raise OptionParser::MissingArgument, "--bundle-id is required for units" if ASCTooling::Client.blank?(@options[:bundle_id])

      app = @asc.find_app!(@options[:bundle_id])
      summary = summarize_units(app)

      if @options[:json]
        puts JSON.pretty_generate(summary)
        return
      end

      puts "App: #{summary.dig(:app, :name)} (#{summary.dig(:app, :bundle_id)})"
      puts "Apple Identifier: #{summary.dig(:app, :apple_identifier)}"
      puts "Report: #{summary.dig(:report, :report_type)} / #{summary.dig(:report, :report_subtype)} / #{summary.dig(:report, :frequency)}"
      puts "Requested date: #{summary.dig(:report, :report_date) || '-'}"
      puts "Report version: #{summary.dig(:report, :report_version)}"
      puts "Country filter: #{summary[:country_filter] || '-'}"
      puts "Date range: #{summary[:begin_date] || '-'} -> #{summary[:end_date] || '-'}"
      puts "Matched rows: #{summary[:matching_rows]}"
      puts "Downloads: #{format_units(summary[:downloads_units])}"
      puts "Redownloads: #{format_units(summary[:redownload_units])}"
      puts "Updates: #{format_units(summary[:updates_units])}"
      puts "Other units: #{format_units(summary[:other_units])}"
      puts "Total units: #{format_units(summary[:total_units])}"

      unless summary[:by_country].empty?
        puts "By country:"
        summary[:by_country].each do |country_code, units|
          puts "  #{country_code}: #{format_units(units)}"
        end
      end
    end

    def summarize_units(app)
      rows = parse_report_rows(report_text)
      filtered_rows = rows.select { |row| row["Apple Identifier"].to_s == app.id.to_s }

      if @options[:country]
        country = @options[:country].to_s.upcase
        filtered_rows.select! { |row| row["Country Code"].to_s.upcase == country }
      end

      summary = {
        app: {
          name: app.name,
          bundle_id: app.bundle_id,
          apple_identifier: app.id
        },
        report: {
          report_type: normalized_report_option(:report_type),
          report_subtype: normalized_report_option(:report_subtype),
          frequency: normalized_report_option(:frequency),
          report_date: @options[:report_date],
          report_version: @options[:report_version]
        },
        country_filter: @options[:country]&.upcase,
        begin_date: filtered_rows.map { |row| row["Begin Date"] }.compact.min,
        end_date: filtered_rows.map { |row| row["End Date"] }.compact.max,
        matching_rows: filtered_rows.length,
        downloads_units: 0.0,
        redownload_units: 0.0,
        updates_units: 0.0,
        other_units: 0.0,
        total_units: 0.0,
        by_country: Hash.new(0.0)
      }

      filtered_rows.each do |row|
        units = row["Units"].to_f
        summary[:total_units] += units
        summary[:by_country][row["Country Code"].to_s.upcase] += units unless ASCTooling::Client.blank?(row["Country Code"])

        case classify_product_type(row["Product Type Identifier"])
        when :download then summary[:downloads_units] += units
        when :redownload then summary[:redownload_units] += units
        when :update then summary[:updates_units] += units
        else
          summary[:other_units] += units
        end
      end

      summary[:by_country] = summary[:by_country].sort.to_h
      summary
    end

    def report_text
      inflate_report(
        @asc.request_blob(
          "GET",
          "/v1/salesReports",
          params: report_params
        )
      )
    end

    def report_params
      params = {
        "filter[vendorNumber]" => vendor_number,
        "filter[reportType]" => normalized_report_option(:report_type),
        "filter[reportSubType]" => normalized_report_option(:report_subtype),
        "filter[frequency]" => normalized_report_option(:frequency),
        "filter[version]" => @options[:report_version]
      }

      params["filter[reportDate]"] = normalized_report_date if @options[:report_date]
      params
    end

    def normalized_report_option(key)
      @options.fetch(key).to_s.strip.upcase
    end

    def normalized_report_date
      Date.iso8601(@options[:report_date]).iso8601
    rescue Date::Error
      raise OptionParser::InvalidArgument, "invalid --report-date: #{@options[:report_date]}"
    end

    def inflate_report(binary)
      data = binary.to_s.b
      return data if data.empty?
      return data unless gzip?(data)

      Zlib::GzipReader.new(StringIO.new(data)).read
    end

    def gzip?(binary)
      binary.b.byteslice(0, 2) == "\x1F\x8B".b
    end

    def parse_report_rows(text)
      sanitized = text.to_s.b.sub(/\A\xEF\xBB\xBF/n, "").force_encoding("UTF-8")
      CSV.parse(
        sanitized,
        headers: true,
        col_sep: "\t",
        return_headers: false
      ).map do |row|
        row.to_h.transform_keys { |key| key.to_s.strip }
      end
    end

    def classify_product_type(value)
      normalized = value.to_s.strip.upcase
      return :download if DOWNLOAD_PRODUCT_TYPES.include?(normalized)
      return :redownload if REDOWNLOAD_PRODUCT_TYPES.include?(normalized)
      return :update if UPDATE_PRODUCT_TYPES.include?(normalized)

      :other
    end

    def format_units(value)
      if value.round == value
        value.to_i.to_s
      else
        format("%.2f", value)
      end
    end
  end
end
