require "json"
require "optparse"
require "uri"

module ASCTooling
  class Availability
    DEFAULT_LIMIT = 200

    def self.run(argv = ARGV)
      options = {
        command: argv.shift,
        dry_run: false
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: asc-availability <status|apply> --bundle-id com.example.app [options]"

        opts.on("--bundle-id BUNDLE_ID", "App bundle identifier") { |value| options[:bundle_id] = value }
        opts.on("--[no-]available-in-new-territories", "Set whether new App Store territories are auto-enabled") do |value|
          options[:available_in_new_territories] = value
        end
        opts.on("--key-id KEY_ID", "ASC API key id") { |value| options[:key_id] = value }
        opts.on("--issuer-id ISSUER_ID", "ASC API issuer id") { |value| options[:issuer_id] = value }
        opts.on("--key-path PATH", "Path to ASC API .p8 key") { |value| options[:key_path] = value }
        opts.on("--dry-run", "Print changes without mutating App Store Connect") { options[:dry_run] = true }
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

    def print_status
      summary = status_summary

      if @options[:json]
        puts JSON.pretty_generate(summary)
        return
      end

      availability = summary[:availability]
      puts "App: #{summary[:app_name]} (#{summary[:bundle_id]})"
      puts "Availability: #{summary[:ok] ? 'ready' : 'gap'}"
      puts "Territories: #{availability[:available_territory_count]}/#{availability[:all_territory_count]}"
      puts "Available in new territories: #{availability[:available_in_new_territories] ? 'yes' : 'no'}"

      if availability[:missing_territory_ids].empty?
        puts "Missing territories: none"
      else
        puts "Missing territories: #{availability[:missing_territory_ids].join(', ')}"
      end

      return unless summary[:warning]

      puts "Warning: #{summary[:warning]}"
    end

    def apply
      result = apply_availability

      if @options[:json]
        puts JSON.pretty_generate(result)
        return
      end

      puts result[:message]
    end

    def apply_availability
      target = @options.fetch(:available_in_new_territories) do
        raise ArgumentError, "pass --available-in-new-territories or --no-available-in-new-territories"
      end

      current = current_available_in_new_territories
      result = {
        dry_run: @options[:dry_run],
        changed: current != target,
        app_id: app.id,
        bundle_id: @options[:bundle_id],
        available_in_new_territories: {
          from: current,
          to: target
        }
      }

      if current == target
        result[:message] = "No change: available in new territories already #{yes_no(target)}."
        return result
      end

      if @options[:dry_run]
        result[:message] = "Dry run: would set available in new territories #{yes_no(current)} -> #{yes_no(target)}."
        return result
      end

      @asc.update_resource("apps", app.id, attributes: { available_in_new_territories: target })
      @app = nil
      @availability = nil
      result[:message] = "Updated available in new territories to #{yes_no(target)}."
      result
    end

    def status_summary
      availability = availability_resource
      territories = territory_ids
      available_territories = availability ? available_territory_ids(availability.fetch("id")) : []
      current_available_territories = territories & available_territories
      missing_territories = territories - current_available_territories
      unknown_available_territories = available_territories - territories
      available_in_new_territories = current_available_in_new_territories

      {
        ok: !availability.nil? && missing_territories.empty?,
        status: availability_status(availability, missing_territories),
        bundle_id: @options[:bundle_id],
        app_id: app.id,
        app_name: app.name,
        availability: {
          id: availability&.fetch("id", nil),
          present: !availability.nil?,
          available_in_new_territories: available_in_new_territories,
          all_territory_count: territories.size,
          available_territory_count: current_available_territories.size,
          missing_territory_count: missing_territories.size,
          missing_territory_ids: missing_territories,
          unknown_available_territory_ids: unknown_available_territories
        },
        warning: availability_warning(missing_territories, available_in_new_territories)
      }
    end

    def app
      @app ||= @asc.find_app!(@options[:bundle_id])
    end

    def availability_resource
      return @availability if defined?(@availability)

      @availability = @asc.request_json("GET", "/v1/apps/#{app.id}/appAvailabilityV2").fetch("data")
    rescue ASCTooling::APIError => e
      raise unless e.status == 404

      @availability = nil
    end

    def current_available_in_new_territories
      availability_value = availability_resource&.dig("attributes", "availableInNewTerritories")
      return availability_value unless availability_value.nil?

      app.raw.dig("attributes", "availableInNewTerritories")
    end

    def availability_status(availability, missing_territories)
      return "availability_missing" unless availability

      missing_territories.empty? ? "ready" : "availability_gap"
    end

    def availability_warning(missing_territories, available_in_new_territories)
      return nil unless missing_territories.empty? && available_in_new_territories == false

      "App is available in all current territories, but future new territories are not auto-enabled."
    end

    def yes_no(value)
      return "unknown" if value.nil?

      value ? "yes" : "no"
    end

    def territory_ids
      ids = []
      each_paginated("/v1/territories", params: { "fields[territories]" => "currency" }) do |item|
        ids << item.fetch("id")
      end
      ids.uniq.sort
    end

    def available_territory_ids(availability_id)
      ids = []
      each_paginated(
        "/v2/appAvailabilities/#{availability_id}/territoryAvailabilities",
        params: { "include" => "territory" }
      ) do |item|
        territory_id = item.dig("relationships", "territory", "data", "id") ||
                       decode_territory_availability_id(item["id"])
        ids << territory_id if territory_id
      end
      ids.uniq.sort
    end

    def each_paginated(path, params: {}, &block)
      next_path = path
      next_params = params.merge("limit" => DEFAULT_LIMIT.to_s)

      loop do
        response = @asc.request_json("GET", next_path, params: next_params)
        response.fetch("data", []).each(&block)

        next_link = response.dig("links", "next")
        break if ASCTooling::Client.blank?(next_link)

        uri = URI(next_link)
        next_path = uri.path
        next_params = URI.decode_www_form(uri.query || "").to_h
      end
    end

    def decode_territory_availability_id(value)
      JSON.parse(value.unpack1("m0"))["t"]
    rescue ArgumentError, JSON::ParserError, NoMethodError
      nil
    end
  end
end
