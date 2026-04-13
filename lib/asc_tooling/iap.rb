require "digest/md5"
require "json"
require "optparse"
require "digest"

module ASCTooling
  class IAP
    DEFAULT_REVIEW_SCREENSHOT_PATH = "build/review-screenshots/iap-review-support-ui.png".freeze
    DEFAULT_LIMIT = 200
    LOCALIZATION_LIMIT = 50
    POLL_INTERVAL_SECONDS = 2
    POLL_ATTEMPTS = 30
    FIRST_IAP_REVIEW_ERROR = "STATE_ERROR.FIRST_IAP_MUST_BE_SUBMITTED_ON_VERSION".freeze

    def self.run(argv = ARGV)
      options = {
        command: argv.shift,
        product_ids: [],
        review_screenshot_path: DEFAULT_REVIEW_SCREENSHOT_PATH,
        wait_for_processing: true,
        replace_review_screenshot: false
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: asc-iap <status|sync-review-screenshot|sync-availability|prepare|submit> --bundle-id com.example.app [options]"

        opts.on("--bundle-id BUNDLE_ID", "App bundle identifier") { |value| options[:bundle_id] = value }
        opts.on("--product-id PRODUCT_ID", "IAP product id to target (repeatable; defaults to all app IAPs)") do |value|
          options[:product_ids] << value
        end
        opts.on("--review-screenshot PATH", "PNG to upload as the IAP review screenshot") do |value|
          options[:review_screenshot_path] = value
        end
        opts.on("--replace-review-screenshot", "Replace an existing review screenshot instead of skipping it") do
          options[:replace_review_screenshot] = true
        end
        opts.on("--no-wait", "Do not wait for review screenshot processing to finish") do
          options[:wait_for_processing] = false
        end
        opts.on("--key-id KEY_ID", "ASC API key id") { |value| options[:key_id] = value }
        opts.on("--issuer-id ISSUER_ID", "ASC API issuer id") { |value| options[:issuer_id] = value }
        opts.on("--key-path PATH", "Path to ASC API .p8 key") { |value| options[:key_path] = value }
        opts.on("--dry-run", "Print what would happen without making changes") { options[:dry_run] = true }
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
      when "sync-review-screenshot" then sync_review_screenshot
      when "sync-availability" then sync_availability
      when "prepare" then prepare
      when "submit" then submit
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

      puts "App: #{summary[:app_name]} (#{summary[:bundle_id]})"
      puts "Products: #{summary[:count]}"

      summary[:products].each_with_index do |product, index|
        puts "  #{index + 1}. #{product[:name]} (#{product[:product_id]}) [#{product[:state]}]"

        if product[:localizations].empty?
          puts "     Localizations: none"
        else
          locales = product[:localizations].map { |item| "#{item[:locale]} [#{item[:state]}]" }
          puts "     Localizations: #{locales.join(', ')}"
        end

        if product[:review_screenshot]
          puts "     Review screenshot: #{product[:review_screenshot][:state]} [#{product[:review_screenshot][:id]}]"
        else
          puts "     Review screenshot: none"
        end

        puts "     Availability: #{product[:availability] ? 'set' : 'missing'}"
        puts "     Review note: #{product[:has_review_note] ? 'yes' : 'no'}"
        puts "     Blockers: #{product[:blockers].empty? ? 'none' : product[:blockers].join('; ')}"
      end
    end

    def sync_review_screenshot
      path = File.expand_path(@options[:review_screenshot_path])
      raise ArgumentError, "review screenshot not found: #{@options[:review_screenshot_path]}" unless File.exist?(path)

      bytes = File.binread(path)
      file_name = File.basename(path)
      file_size = File.size(path)
      checksum = Digest::MD5.hexdigest(bytes)
      changed = 0

      target_iaps.each do |iap|
        existing = review_screenshot_data(iap["id"])
        if existing && !@options[:replace_review_screenshot]
          puts "No change needed: #{product_label(iap)} already has review screenshot #{existing['id']} [#{review_screenshot_state(existing)}]."
          next
        end

        if @options[:dry_run]
          action = existing ? "replace" : "upload"
          puts "Dry run: would #{action} review screenshot for #{product_label(iap)}."
          changed += 1
          next
        end

        if existing
          @asc.request_json("DELETE", "/v1/inAppPurchaseAppStoreReviewScreenshots/#{existing['id']}")
          puts "Deleted review screenshot #{existing['id']} for #{product_label(iap)}."
        end

        created = @asc.request_json(
          "POST",
          "/v1/inAppPurchaseAppStoreReviewScreenshots",
          body: {
            data: {
              type: "inAppPurchaseAppStoreReviewScreenshots",
              attributes: {
                fileName: file_name,
                fileSize: file_size
              },
              relationships: {
                inAppPurchaseV2: {
                  data: {
                    type: "inAppPurchases",
                    id: iap["id"]
                  }
                }
              }
            }
          }
        ).fetch("data")

        @asc.upload_asset(created.dig("attributes", "uploadOperations") || [], bytes)

        patched = @asc.request_json(
          "PATCH",
          "/v1/inAppPurchaseAppStoreReviewScreenshots/#{created['id']}",
          body: {
            data: {
              type: "inAppPurchaseAppStoreReviewScreenshots",
              id: created["id"],
              attributes: {
                uploaded: true,
                sourceFileChecksum: checksum
              }
            }
          }
        ).fetch("data")

        final = @options[:wait_for_processing] ? wait_for_review_screenshot!(patched["id"]) : patched
        puts "Uploaded review screenshot for #{product_label(iap)}: #{final['id']} [#{review_screenshot_state(final)}]"
        changed += 1
      end

      puts "Review screenshot sync complete: #{changed} changed, #{target_iaps.size - changed} unchanged."
    end

    def sync_availability
      availability_template = app_availability_template
      changed = 0

      target_iaps.each do |iap|
        existing = availability_data(iap["id"])
        if existing
          puts "No change needed: #{product_label(iap)} already has availability #{existing['id']}."
          next
        end

        if @options[:dry_run]
          puts "Dry run: would create availability for #{product_label(iap)} (#{availability_template[:territory_ids].size} territories)."
          changed += 1
          next
        end

        created = @asc.request_json(
          "POST",
          "/v1/inAppPurchaseAvailabilities",
          body: {
            data: {
              type: "inAppPurchaseAvailabilities",
              attributes: {
                availableInNewTerritories: availability_template[:available_in_new_territories]
              },
              relationships: {
                inAppPurchase: {
                  data: {
                    type: "inAppPurchases",
                    id: iap["id"]
                  }
                },
                availableTerritories: {
                  data: availability_template[:territory_ids].map { |territory_id| { type: "territories", id: territory_id } }
                }
              }
            }
          }
        ).fetch("data")

        puts "Created availability for #{product_label(iap)}: #{created['id']} (#{availability_template[:territory_ids].size} territories)."
        changed += 1
      end

      puts "Availability sync complete: #{changed} changed, #{target_iaps.size - changed} unchanged."
    end

    def prepare
      sync_review_screenshot
      sync_availability
    end

    def submit
      submitted = 0

      target_iaps.each do |iap|
        state = iap.dig("attributes", "state")
        if state == "WAITING_FOR_REVIEW"
          puts "No change needed: #{product_label(iap)} is already waiting for review."
          next
        end

        if @options[:dry_run]
          puts "Dry run: would submit #{product_label(iap)} for review."
          submitted += 1
          next
        end

        begin
          response = @asc.request_json(
            "POST",
            "/v1/inAppPurchaseSubmissions",
            body: {
              data: {
                type: "inAppPurchaseSubmissions",
                relationships: {
                  inAppPurchaseV2: {
                    data: {
                      type: "inAppPurchases",
                      id: iap["id"]
                    }
                  }
                }
              }
            }
          )
        rescue ASCTooling::APIError => e
          if @asc.api_error_codes(e.payload).include?(FIRST_IAP_REVIEW_ERROR)
            raise ArgumentError, <<~MESSAGE.strip
              Apple still requires the app's first in-app purchase to be attached to the app version submission in the App Store Connect web UI.
              Use `asc-iap prepare` to automate screenshot and availability setup, then select the IAPs on the app version page before submitting that version for review.
            MESSAGE
          end

          raise
        end

        puts "Submitted #{product_label(iap)}: #{response.dig('data', 'id')}"
        submitted += 1
      end

      puts "IAP submission complete: #{submitted} submitted, #{target_iaps.size - submitted} unchanged."
    end

    def status_summary
      {
        app_name: app.name,
        bundle_id: app.bundle_id,
        count: target_iaps.size,
        products: target_iaps.map { |iap| product_summary(iap) }
      }
    end

    def product_summary(iap)
      localizations = localization_summaries(iap["id"])
      review_screenshot = review_screenshot_data(iap["id"])
      availability = availability_data(iap["id"])
      blockers = []

      blockers << "missing localizations" if localizations.empty?
      blockers << "missing review screenshot" unless review_screenshot
      blockers << "review screenshot not complete" if review_screenshot && review_screenshot_state(review_screenshot) != "COMPLETE"
      blockers << "availability not set" unless availability
      blockers << "review note missing" if ASCTooling::Client.blank?(iap.dig("attributes", "reviewNote"))
      blockers << "ASC state is #{iap.dig('attributes', 'state')}" if blockers.empty? && iap.dig("attributes", "state") == "MISSING_METADATA"

      {
        id: iap["id"],
        product_id: iap.dig("attributes", "productId"),
        name: iap.dig("attributes", "name"),
        state: iap.dig("attributes", "state"),
        has_review_note: !ASCTooling::Client.blank?(iap.dig("attributes", "reviewNote")),
        localizations: localizations,
        review_screenshot: review_screenshot && {
          id: review_screenshot["id"],
          state: review_screenshot_state(review_screenshot),
          file_name: review_screenshot.dig("attributes", "fileName")
        },
        availability: availability && {
          id: availability["id"],
          available_in_new_territories: availability.dig("attributes", "availableInNewTerritories")
        },
        blockers: blockers
      }
    end

    def localization_summaries(iap_id)
      response = @asc.request_json(
        "GET",
        "/v2/inAppPurchases/#{iap_id}/inAppPurchaseLocalizations",
        params: { "limit" => LOCALIZATION_LIMIT.to_s }
      )

      response.fetch("data", []).map do |item|
        {
          id: item["id"],
          locale: item.dig("attributes", "locale"),
          state: item.dig("attributes", "state"),
          name: item.dig("attributes", "name"),
          description: item.dig("attributes", "description")
        }
      end
    end

    def review_screenshot_data(iap_id)
      response = optional_json("GET", "/v2/inAppPurchases/#{iap_id}/appStoreReviewScreenshot")
      response && response["data"]
    end

    def availability_data(iap_id)
      response = optional_json("GET", "/v2/inAppPurchases/#{iap_id}/inAppPurchaseAvailability")
      response && response["data"]
    end

    def wait_for_review_screenshot!(screenshot_id)
      POLL_ATTEMPTS.times do
        current = @asc.request_json("GET", "/v1/inAppPurchaseAppStoreReviewScreenshots/#{screenshot_id}").fetch("data")
        state = review_screenshot_state(current)
        return current if state == "COMPLETE"

        raise ArgumentError, "review screenshot #{screenshot_id} failed processing" if state == "FAILED"

        sleep(POLL_INTERVAL_SECONDS)
      end

      raise ArgumentError, "timed out waiting for review screenshot processing"
    end

    def review_screenshot_state(data)
      data.dig("attributes", "assetDeliveryState", "state") || "UNKNOWN"
    end

    def optional_json(method, path, params: nil, body: nil)
      @asc.request_json(method, path, params: params, body: body)
    rescue ASCTooling::APIError => e
      return nil if e.status == 404

      raise
    end

    def app
      @app ||= @asc.find_app!(@options[:bundle_id])
    end

    def target_iaps
      @target_iaps ||= begin
        iaps = @asc.request_json(
          "GET",
          "/v1/apps/#{app.id}/inAppPurchasesV2",
          params: { "limit" => DEFAULT_LIMIT.to_s }
        ).fetch("data", [])

        product_ids = @options[:product_ids].uniq
        if product_ids.empty?
          iaps.sort_by { |item| item.dig("attributes", "productId").to_s }
        else
          by_product_id = iaps.to_h do |item|
            [item.dig("attributes", "productId"), item]
          end
          missing = product_ids.reject { |product_id| by_product_id.key?(product_id) }
          raise ArgumentError, "IAP product id(s) not found: #{missing.join(', ')}" unless missing.empty?

          product_ids.map { |product_id| by_product_id.fetch(product_id) }
        end
      end
    end

    def app_availability_template
      @app_availability_template ||= begin
        availability = @asc.request_json("GET", "/v1/apps/#{app.id}/appAvailabilityV2").fetch("data")
        territory_response = @asc.request_json(
          "GET",
          "/v2/appAvailabilities/#{availability['id']}/territoryAvailabilities",
          params: {
            "include" => "territory",
            "limit" => DEFAULT_LIMIT.to_s
          }
        )
        territory_ids = territory_response.fetch("data", []).filter_map do |item|
          item.dig("relationships", "territory", "data", "id") || decode_territory_availability_id(item["id"])
        end.uniq.sort

        raise ArgumentError, "app availability does not expose any territories" if territory_ids.empty?

        {
          available_in_new_territories: availability.dig("attributes", "availableInNewTerritories") || false,
          territory_ids: territory_ids
        }
      end
    end

    def decode_territory_availability_id(value)
      decoded = JSON.parse(value.unpack1("m0"))
      decoded["t"]
    rescue ArgumentError, JSON::ParserError, NoMethodError => e
      warn "Warning: could not decode territory availability id #{value.inspect}: #{e.message}"
      nil
    end

    def product_label(iap)
      name = iap.dig("attributes", "name")
      product_id = iap.dig("attributes", "productId")
      ASCTooling::Client.blank?(name) ? product_id : "#{name} (#{product_id})"
    end
  end
end
