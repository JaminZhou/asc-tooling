require "json"
require "optparse"

module ASCTooling
  class StoreSetupOptions
    REVIEW_CONTACT_ENV = {
      review_contact_first_name: "ASC_REVIEW_CONTACT_FIRST_NAME",
      review_contact_last_name: "ASC_REVIEW_CONTACT_LAST_NAME",
      review_contact_phone: "ASC_REVIEW_CONTACT_PHONE",
      review_contact_email: "ASC_REVIEW_CONTACT_EMAIL"
    }.freeze

    def self.parse(argv)
      options = default_options(argv.shift)
      parser = option_parser(options)
      parser.parse!(argv)

      [options, parser]
    end

    def self.default_options(command)
      options = {
        command: command,
        platform: "macos",
        dry_run: false,
        json: false,
        price_base_territory: "USA",
        free_pricing: false,
        clear_demo_account: false
      }

      REVIEW_CONTACT_ENV.each do |key, env_name|
        options[key] = ENV.fetch(env_name, nil)
      end

      options
    end
    private_class_method :default_options

    def self.option_parser(options)
      OptionParser.new do |opts|
        opts.banner = "Usage: asc-store-setup <status|apply> --bundle-id com.example.app --app-version 1.0.0 [options]"
        opts.on("--bundle-id BUNDLE_ID", "App bundle identifier") { |value| options[:bundle_id] = value }
        opts.on("--app-version VERSION", "Editable App Store version") { |value| options[:app_version] = value }
        opts.on("--platform PLATFORM", "ios, macos, or tvos (default: macos)") { |value| options[:platform] = value }
        opts.on("--primary-category ID", "Primary App Store category id, e.g. SHOPPING") { |value| options[:primary_category] = value }
        opts.on("--secondary-category ID", "Secondary App Store category id") { |value| options[:secondary_category] = value }
        opts.on("--age-rating-template TEMPLATE", "Age rating template, currently: 4-plus") { |value| options[:age_rating_template] = value }
        opts.on("--release-type TYPE", "manual or after-approval") { |value| options[:release_type] = value }
        opts.on("--price-base-territory ID", "Base territory for free price-point lookup") { |value| options[:price_base_territory] = value }
        opts.on("--free-pricing", "Create a free app price schedule when one is missing") { options[:free_pricing] = true }
        opts.on("--review-contact-first-name NAME", "App Review contact first name") { |value| options[:review_contact_first_name] = value }
        opts.on("--review-contact-last-name NAME", "App Review contact last name") { |value| options[:review_contact_last_name] = value }
        opts.on("--review-contact-phone PHONE", "App Review contact phone") { |value| options[:review_contact_phone] = value }
        opts.on("--review-contact-email EMAIL", "App Review contact email") { |value| options[:review_contact_email] = value }
        opts.on("--review-notes TEXT", "App Review notes") { |value| options[:review_notes] = value }
        opts.on("--review-notes-file PATH", "Text file for App Review notes") { |value| options[:review_notes_file] = value }
        opts.on("--demo-account-required", "Mark review detail as requiring a demo account") { options[:demo_account_required] = true }
        opts.on("--demo-account-name NAME", "Demo account username for App Review") { |value| options[:demo_account_name] = value }
        opts.on("--demo-account-password PASSWORD", "Demo account password for App Review") { |value| options[:demo_account_password] = value }
        opts.on("--no-demo-account", "Mark review detail as not requiring a demo account") { options[:clear_demo_account] = true }
        opts.on("--key-id KEY_ID", "ASC API key id") { |value| options[:key_id] = value }
        opts.on("--issuer-id ISSUER_ID", "ASC API issuer id") { |value| options[:issuer_id] = value }
        opts.on("--key-path PATH", "Path to ASC API .p8 key") { |value| options[:key_path] = value }
        opts.on("--dry-run", "Print changes without mutating App Store Connect") { options[:dry_run] = true }
        opts.on("--json", "Print machine-readable JSON") { options[:json] = true }
      end
    end
    private_class_method :option_parser
  end

  class StoreSetup
    AGE_RATING_TEMPLATES = {
      "4-plus" => {
        advertising: false,
        alcoholTobaccoOrDrugUseOrReferences: "NONE",
        contests: "NONE",
        gambling: false,
        gamblingSimulated: "NONE",
        gunsOrOtherWeapons: "NONE",
        healthOrWellnessTopics: false,
        kidsAgeBand: nil,
        lootBox: false,
        medicalOrTreatmentInformation: "NONE",
        messagingAndChat: false,
        parentalControls: false,
        profanityOrCrudeHumor: "NONE",
        ageAssurance: false,
        sexualContentGraphicAndNudity: "NONE",
        sexualContentOrNudity: "NONE",
        horrorOrFearThemes: "NONE",
        matureOrSuggestiveThemes: "NONE",
        unrestrictedWebAccess: false,
        userGeneratedContent: false,
        violenceCartoonOrFantasy: "NONE",
        violenceRealisticProlongedGraphicOrSadistic: "NONE",
        violenceRealistic: "NONE",
        ageRatingOverrideV2: "NONE",
        koreaAgeRatingOverride: "NONE",
        developerAgeRatingInfoUrl: nil
      }.freeze
    }.freeze

    def self.run(argv = ARGV)
      options, parser = StoreSetupOptions.parse(argv)

      if options[:command].nil? || options[:bundle_id].nil? || options[:app_version].nil?
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

      puts "App: #{summary[:app][:name]} (#{summary[:app][:bundle_id]})"
      puts "Version: #{summary[:version][:version]} [#{summary[:version][:state]}]"
      puts "Release type: #{summary[:version][:release_type] || 'none'}#{target_label(:release_type)}"
      puts "Primary category: #{summary[:category][:primary] || 'none'}#{target_label(:primary_category)}"
      puts "Secondary category: #{summary[:category][:secondary] || 'none'}#{target_label(:secondary_category)}"
      puts "Age rating: #{summary[:age_rating][:app_store_age_rating] || 'none'}"
      puts "Age rating template match: #{summary[:age_rating][:template_match] ? 'yes' : 'no'}" if @options[:age_rating_template]
      puts "Review detail: #{summary[:review_detail][:present] ? 'present' : 'missing'}"
      puts "Review notes: #{summary[:review_detail][:has_notes] ? 'present' : 'missing'}"
      puts "Price schedule: #{summary[:pricing][:present] ? 'present' : 'missing'}"
      puts "Free price point (#{@options[:price_base_territory]}): #{summary[:pricing][:free_price_point_id] || 'not found'}"
      puts "Availability: #{summary[:availability][:present] ? 'present' : 'missing'}"
    end

    def apply
      actions = [
        apply_release_type,
        apply_category,
        apply_age_rating,
        apply_free_pricing,
        apply_review_detail
      ].compact

      if @options[:json]
        puts JSON.pretty_generate({ dry_run: @options[:dry_run], actions: actions })
        return
      end

      if actions.empty?
        puts "No configured store setup actions. Pass category, release type, age rating, pricing, or review detail options."
      else
        actions.each { |line| puts line }
      end
      puts "Pricing/Availability are status-checked only; confirm first-release sale settings in App Store Connect."
      puts "App Privacy remains an App Store Connect web item."
    end

    def apply_release_type
      return nil unless @options[:release_type]

      target = ASCTooling::Client::RELEASE_TYPE_MAP.fetch(@options[:release_type]) do
        raise OptionParser::InvalidArgument, "unsupported release type: #{@options[:release_type]}"
      end

      current = version.release_type
      return "No change: release type already #{current}." if current == target
      return "Dry run: would set release type #{current || 'none'} -> #{target}." if @options[:dry_run]

      @asc.update_resource("appStoreVersions", version.id, attributes: { releaseType: target })
      @version = nil
      "Updated release type to #{target}."
    end

    def apply_category
      return nil unless @options[:primary_category] || @options[:secondary_category]

      validate_category!(@options[:primary_category]) if @options[:primary_category]
      validate_category!(@options[:secondary_category]) if @options[:secondary_category]

      current_primary = category_id("primaryCategory")
      current_secondary = category_id("secondaryCategory")
      target_primary = @options[:primary_category] || current_primary
      target_secondary = @options[:secondary_category] || current_secondary

      if current_primary == target_primary && current_secondary == target_secondary
        return "No change: category already primary=#{current_primary || 'none'}, secondary=#{current_secondary || 'none'}."
      end

      relationships = {}
      relationships[:primaryCategory] = category_relationship(target_primary) if target_primary
      relationships[:secondaryCategory] = category_relationship(target_secondary) if target_secondary

      if @options[:dry_run]
        parts = []
        parts << "primary #{current_primary || 'none'} -> #{target_primary}" if current_primary != target_primary
        parts << "secondary #{current_secondary || 'none'} -> #{target_secondary}" if current_secondary != target_secondary
        return "Dry run: would update category: #{parts.join(', ')}."
      end

      @asc.request_json(
        "PATCH",
        "/v1/appInfos/#{app_info.id}",
        body: {
          data: {
            type: "appInfos",
            id: app_info.id,
            relationships: relationships
          }
        }
      )
      "Updated category: primary=#{target_primary || 'none'}, secondary=#{target_secondary || 'none'}."
    end

    def apply_age_rating
      template = age_rating_template
      return nil unless template

      current_attrs = age_rating_declaration.fetch("attributes", {})
      unchanged = template.all? { |key, value| current_attrs[key.to_s] == value }
      return "No change: age rating declaration already matches #{@options[:age_rating_template]}." if unchanged

      if @options[:dry_run]
        changed = template.keys.reject { |key| current_attrs[key.to_s] == template[key] }
        return "Dry run: would update age rating fields: #{changed.join(', ')}."
      end

      @asc.request_json(
        "PATCH",
        "/v1/ageRatingDeclarations/#{age_rating_declaration.fetch('id')}",
        body: {
          data: {
            type: "ageRatingDeclarations",
            id: age_rating_declaration.fetch("id"),
            attributes: template
          }
        }
      )
      "Updated age rating declaration with #{@options[:age_rating_template]}."
    end

    def apply_review_detail
      attrs = desired_review_detail_attributes
      return nil if attrs.empty?

      detail = review_detail
      missing = required_review_contact_fields(attrs)
      return "Skipped review detail: set #{missing.join(', ')} before creating it." if detail.nil? && missing.any?
      if detail.nil? && !demo_account_state_explicit?
        return "Skipped review detail: pass --no-demo-account or --demo-account-required before creating it."
      end

      current_attrs = detail&.fetch("attributes", {}) || {}
      missing_demo = required_demo_account_fields(attrs, current_attrs)
      return "Skipped review detail: set #{missing_demo.join(', ')} when using --demo-account-required." if missing_demo.any?

      if detail
        unchanged = attrs.all? { |key, value| current_attrs[key.to_s] == value }
        return "No change: App Review detail already matches desired fields." if unchanged
        return "Dry run: would update App Review detail #{detail.fetch('id')}." if @options[:dry_run]

        @asc.request_json(
          "PATCH",
          "/v1/appStoreReviewDetails/#{detail.fetch('id')}",
          body: {
            data: {
              type: "appStoreReviewDetails",
              id: detail.fetch("id"),
              attributes: attrs
            }
          }
        )
        return "Updated App Review detail."
      end

      return "Dry run: would create App Review detail." if @options[:dry_run]

      @asc.request_json(
        "POST",
        "/v1/appStoreReviewDetails",
        body: {
          data: {
            type: "appStoreReviewDetails",
            attributes: attrs,
            relationships: {
              appStoreVersion: {
                data: { type: "appStoreVersions", id: version.id }
              }
            }
          }
        }
      )
      "Created App Review detail."
    end

    def apply_free_pricing
      return nil unless @options[:free_pricing]

      schedule = price_schedule
      if schedule
        message = "No change: price schedule already exists"
        message += " (#{schedule['id']})" if schedule["id"]
        return "#{message}."
      end

      price_point_id = free_price_point_id
      return "Skipped free pricing: no free app price point found for #{@options[:price_base_territory]}." unless present?(price_point_id)

      return "Dry run: would create free price schedule using #{@options[:price_base_territory]} price point #{price_point_id}." if @options[:dry_run]

      create_free_price_schedule!(price_point_id)
      @price_schedule = nil
      "Created free price schedule using #{@options[:price_base_territory]} price point #{price_point_id}."
    end

    def status_summary
      detail = review_detail
      age_attrs = age_rating_declaration.fetch("attributes", {})

      {
        app: {
          id: app.id,
          name: app.name,
          bundle_id: app.bundle_id
        },
        app_info: {
          id: app_info.id,
          state: app_info.raw.dig("attributes", "state")
        },
        version: {
          id: version.id,
          version: version.version_string,
          state: version.app_store_state,
          release_type: version.release_type
        },
        category: {
          primary: category_id("primaryCategory"),
          secondary: category_id("secondaryCategory")
        },
        age_rating: {
          app_store_age_rating: app_info.raw.dig("attributes", "appStoreAgeRating"),
          declaration_id: age_rating_declaration.fetch("id"),
          template: @options[:age_rating_template],
          template_match: age_rating_template&.all? { |key, value| age_attrs[key.to_s] == value }
        },
        review_detail: {
          present: !detail.nil?,
          has_notes: present?(detail&.dig("attributes", "notes")),
          id: detail&.fetch("id", nil)
        },
        pricing: {
          present: !price_schedule.nil?,
          id: price_schedule&.fetch("id", nil),
          free_price_point_id: free_price_point_id
        },
        availability: {
          present: !app_availability.nil?,
          id: app_availability&.fetch("id", nil),
          available_in_new_territories: app_availability&.dig("attributes", "availableInNewTerritories")
        }
      }
    end

    def desired_review_detail_attributes
      attrs = {}
      attrs[:contactFirstName] = @options[:review_contact_first_name] if @options[:review_contact_first_name]
      attrs[:contactLastName] = @options[:review_contact_last_name] if @options[:review_contact_last_name]
      attrs[:contactPhone] = @options[:review_contact_phone] if @options[:review_contact_phone]
      attrs[:contactEmail] = @options[:review_contact_email] if @options[:review_contact_email]
      attrs[:notes] = review_notes if review_notes
      attrs[:demoAccountName] = @options[:demo_account_name] if @options[:demo_account_name]
      attrs[:demoAccountPassword] = @options[:demo_account_password] if @options[:demo_account_password]
      attrs[:demoAccountRequired] = @options[:demo_account_required] if @options.key?(:demo_account_required)
      if @options[:clear_demo_account]
        attrs[:demoAccountName] = nil
        attrs[:demoAccountPassword] = nil
        attrs[:demoAccountRequired] = false
      end
      attrs
    end

    def required_review_contact_fields(attrs)
      {
        "ASC_REVIEW_CONTACT_FIRST_NAME or --review-contact-first-name" => attrs[:contactFirstName],
        "ASC_REVIEW_CONTACT_LAST_NAME or --review-contact-last-name" => attrs[:contactLastName],
        "ASC_REVIEW_CONTACT_PHONE or --review-contact-phone" => attrs[:contactPhone],
        "ASC_REVIEW_CONTACT_EMAIL or --review-contact-email" => attrs[:contactEmail]
      }.reject { |_, value| present?(value) }.keys
    end

    def required_demo_account_fields(attrs, current_attrs)
      return [] unless attrs[:demoAccountRequired] == true

      {
        "--demo-account-name" => attrs[:demoAccountName] || current_attrs["demoAccountName"],
        "--demo-account-password" => attrs[:demoAccountPassword] || current_attrs["demoAccountPassword"]
      }.reject { |_, value| present?(value) }.keys
    end

    def demo_account_state_explicit?
      @options[:clear_demo_account] || @options.key?(:demo_account_required)
    end

    def review_notes
      return @options[:review_notes] if @options.key?(:review_notes) && @options[:review_notes]
      return nil unless @options[:review_notes_file]

      File.read(@options[:review_notes_file]).strip
    end

    def age_rating_template
      return nil unless @options[:age_rating_template]

      AGE_RATING_TEMPLATES.fetch(@options[:age_rating_template]) do
        raise OptionParser::InvalidArgument, "unsupported age rating template: #{@options[:age_rating_template]}"
      end
    end

    def validate_category!(category_id)
      categories = @asc.request_json(
        "GET",
        "/v1/appCategories",
        params: {
          "filter[platforms]" => platform,
          "fields[appCategories]" => "platforms",
          "limit" => "200"
        }
      ).fetch("data", [])
      return if categories.any? { |category| category["id"] == category_id }

      raise ArgumentError, "App Store category not found for #{platform}: #{category_id}"
    end

    def category_relationship(category_id)
      { data: { type: "appCategories", id: category_id } }
    end

    def category_id(relationship_name)
      optional_json("GET", "/v1/appInfos/#{app_info.id}/#{relationship_name}")&.dig("data", "id")
    end

    def age_rating_declaration
      @age_rating_declaration ||= begin
        data = @asc.request_json("GET", "/v1/appInfos/#{app_info.id}/ageRatingDeclaration").fetch("data")
        raise ArgumentError, "age rating declaration not found" unless data

        data
      end
    end

    def review_detail
      @review_detail ||= optional_json("GET", "/v1/appStoreVersions/#{version.id}/appStoreReviewDetail")&.fetch("data", nil)
    end

    def price_schedule
      @price_schedule ||= optional_json(
        "GET",
        "/v1/apps/#{app.id}/appPriceSchedule",
        params: {
          "include" => "baseTerritory,manualPrices,automaticPrices",
          "limit[manualPrices]" => "50",
          "limit[automaticPrices]" => "50"
        }
      )&.fetch("data", nil)
    end

    def app_availability
      @app_availability ||= optional_json(
        "GET",
        "/v1/apps/#{app.id}/appAvailabilityV2",
        params: {
          "include" => "territoryAvailabilities",
          "limit[territoryAvailabilities]" => "50"
        }
      )&.fetch("data", nil)
    end

    def free_price_point_id
      @free_price_point_id ||= begin
        data = @asc.request_json(
          "GET",
          "/v1/apps/#{app.id}/appPricePoints",
          params: {
            "filter[territory]" => @options[:price_base_territory],
            "fields[appPricePoints]" => "customerPrice,proceeds,territory",
            "limit" => "200"
          }
        ).fetch("data", [])
        data.find { |item| item.dig("attributes", "customerPrice").to_f.zero? }&.fetch("id", nil)
      end
    end

    def create_free_price_schedule!(price_point_id)
      local_price_id = "$free-price"
      @asc.request_json(
        "POST",
        "/v1/appPriceSchedules",
        body: {
          data: {
            type: "appPriceSchedules",
            attributes: {},
            relationships: {
              app: {
                data: { type: "apps", id: app.id }
              },
              baseTerritory: {
                data: { type: "territories", id: @options[:price_base_territory] }
              },
              manualPrices: {
                data: [
                  { type: "appPrices", id: local_price_id }
                ]
              }
            }
          },
          included: [
            {
              type: "appPrices",
              id: local_price_id,
              attributes: {
                startDate: nil,
                endDate: nil
              },
              relationships: {
                appPricePoint: {
                  data: { type: "appPricePoints", id: price_point_id }
                }
              }
            }
          ]
        }
      )
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

    def app_info
      @app_info ||= @asc.fetch_edit_app_info!(app)
    end

    def version
      @version ||= @asc.find_version!(app, platform: platform, app_version: @options[:app_version])
    end

    def platform
      @platform ||= @asc.platform(@options[:platform])
    end

    def present?(value)
      !ASCTooling::Client.blank?(value)
    end

    def target_label(key)
      @options[key] ? " (target: #{@options[key]})" : ""
    end
  end
end
