require "json"
require "optparse"

module ASCTooling
  class Review
    SUBMISSION_LIMIT = 20
    SUBMISSION_ITEM_LIMIT = 50
    SUBMISSION_ITEM_INCLUDES = %w[
      appStoreVersion
      inAppPurchaseVersion
    ].freeze

    RELEASEABLE_STATES = %w[
      PENDING_DEVELOPER_RELEASE
      PROCESSING_FOR_APP_STORE
      PROCESSING_FOR_DISTRIBUTION
      READY_FOR_DISTRIBUTION
      READY_FOR_SALE
    ].freeze
    WITHDRAWABLE_STATES = %w[
      WAITING_FOR_EXPORT_COMPLIANCE
      WAITING_FOR_REVIEW
      IN_REVIEW
      PENDING_DEVELOPER_RELEASE
      PENDING_APPLE_RELEASE
    ].freeze

    def self.run(argv = ARGV)
      options = {
        platform: "macos",
        command: argv.shift
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: asc-review <status|attach-build|submit|withdraw|release> --bundle-id com.example.app [options]"

        opts.on("--bundle-id BUNDLE_ID", "App bundle identifier") { |value| options[:bundle_id] = value }
        opts.on("--app-version VERSION", "Editable App Store version to target") { |value| options[:app_version] = value }
        opts.on("--build-number BUILD", "Build number to attach instead of latest VALID build") { |value| options[:build_number] = value }
        opts.on("--platform PLATFORM", "ios, macos, or tvos (default: macos)") { |value| options[:platform] = value }
        opts.on("--release-type TYPE", "manual or after-approval (submit only)") { |value| options[:release_type] = value }
        opts.on("--items", "Include review submission items in status output") { options[:items] = true }
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
      if options[:command] == "attach-build" && options[:app_version].nil?
        warn "--app-version is required for attach-build"
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
      when "attach-build" then attach_build
      when "submit" then submit_for_review
      when "withdraw" then withdraw_from_review
      when "release" then release_to_store
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
      version = @asc.find_version!(app, platform: platform, app_version: @options[:app_version])
      current_build = version.build
      latest_build = find_candidate_build(app.id, version.version_string)
      submissions = review_submissions(app.id)

      summary = {
        app_id: app.id,
        app_name: app.name,
        bundle_id: app.bundle_id,
        version: version.version_string,
        version_state: version.app_store_state,
        release_type: version.release_type,
        current_build: build_summary(current_build),
        latest_valid_build: build_summary(latest_build),
        review_submissions: submissions.map do |submission|
          review_submission_summary(submission, include_items: @options[:items])
        end
      }

      if @options[:json]
        puts JSON.pretty_generate(summary)
        return
      end

      puts "App: #{summary[:app_name]} (#{summary[:bundle_id]})"
      puts "Version: #{summary[:version]} [#{summary[:version_state]}]"
      puts "Release type: #{summary[:release_type]}"

      if summary[:current_build]
        puts "Attached build: #{summary[:current_build][:number]} [#{summary[:current_build][:processing_state]}]"
      else
        puts "Attached build: none"
      end

      if summary[:latest_valid_build]
        puts "Latest valid build: #{summary[:latest_valid_build][:number]}"
      else
        puts "Latest valid build: none"
      end

      if submissions.empty?
        puts "Review submissions: none"
      else
        summary[:review_submissions].each do |submission|
          puts "Review submission: #{submission[:id]} [#{submission[:state]}]"
          next unless submission.key?(:items)

          if submission[:items].empty?
            puts "  Items: none"
          else
            submission[:items].each do |item|
              puts "  Item: #{review_submission_item_label(item)}"
            end
          end
        end
      end
    end

    def attach_build
      app = @asc.find_app!(@options[:bundle_id])
      version = @asc.find_editable_version!(app, platform: platform, app_version: @options[:app_version])
      target_build = find_target_build!(app.id, version.version_string)
      target_number = target_build.dig("attributes", "version")

      if version.build&.version == target_number
        puts "Build #{target_number} is already attached to version #{version.version_string}; nothing to change"
        return
      end

      if @options[:dry_run]
        puts "Dry run: would attach build #{target_number} to version #{version.version_string}."
        return
      end

      version = attach_build_to_version!(app, version, target_build)
      puts "Attached build #{version.build.version} to version #{version.version_string}"
    end

    def submit_for_review
      app = @asc.find_app!(@options[:bundle_id])
      version = @asc.find_editable_version!(app, platform: platform, app_version: @options[:app_version])

      desired_release_type = nil
      if @options[:release_type]
        desired_release_type = ASCTooling::Client::RELEASE_TYPE_MAP.fetch(@options[:release_type]) do
          raise OptionParser::InvalidArgument, "unsupported release type: #{@options[:release_type]}"
        end
      end

      submitted_submission = review_submissions(app.id).find { |submission| submission.dig("attributes", "state") == "WAITING_FOR_REVIEW" }
      if submitted_submission
        puts "Already waiting for review: #{submitted_submission['id']}"
        return
      end

      target_build = find_target_build!(app.id, version.version_string)

      if @options[:dry_run]
        parts = ["would attach build #{target_build.dig('attributes', 'version')} to version #{version.version_string}"]
        parts << "set release type to #{@options[:release_type]}" if desired_release_type && version.release_type != desired_release_type
        puts "Dry run: #{parts.join(', ')} and submit for review."
        return
      end

      if desired_release_type && version.release_type != desired_release_type
        @asc.update_resource("appStoreVersions", version.id,
                             attributes: { releaseType: desired_release_type })
        version = @asc.find_editable_version!(app, platform: platform, app_version: @options[:app_version])
      end

      if version.build.nil? || version.build.version != target_build.dig("attributes", "version")
        version = attach_build_to_version!(app, version, target_build)
      end

      draft_submission = review_submissions(app.id).find { |submission| submission.dig("attributes", "state") == "READY_FOR_REVIEW" }
      draft_submission ||= create_review_submission(app.id)

      create_review_submission_item(draft_submission["id"], version.id) unless review_submission_contains_version?(draft_submission["id"], version.id)

      submitted = submit_review_submission(draft_submission["id"])
      puts "Submitted #{version.version_string} (#{version.build&.version || target_build.dig('attributes', 'version')})"
      puts "Review submission #{submitted['id']} is now #{submitted.dig('attributes', 'state')}"
    end

    def withdraw_from_review
      app = @asc.find_app!(@options[:bundle_id])
      version = @asc.find_version!(app, platform: platform, app_version: @options[:app_version])

      unless WITHDRAWABLE_STATES.include?(version.app_store_state)
        puts "Version #{version.version_string} is #{version.app_store_state}; nothing to withdraw"
        return
      end

      submission_data = @asc.request_json(
        "GET",
        "/v1/appStoreVersions/#{version.id}/appStoreVersionSubmission"
      )
      submission = submission_data.fetch("data", nil)
      raise ArgumentError, "app store version submission not found" unless submission

      if @options[:dry_run]
        puts "Dry run: would withdraw version #{version.version_string} from review."
        return
      end

      @asc.delete_resource("/v1/appStoreVersionSubmissions/#{submission['id']}")
      version = @asc.find_version!(app, platform: platform, app_version: @options[:app_version])

      puts "Withdrew #{version.version_string}; version state is now #{version.app_store_state}"
    end

    def release_to_store
      app = @asc.find_app!(@options[:bundle_id])
      version = find_release_target_version!(app)

      case version.app_store_state
      when "PENDING_DEVELOPER_RELEASE"
        if @options[:dry_run]
          puts "Dry run: would create release request for version #{version.version_string}."
          return
        end

        release_request = create_release_request(version.id)
        version = @asc.find_version!(app, platform: platform, app_version: version.version_string)
        puts "Release request #{release_request['id']} created for #{version.version_string}"
        puts "Version #{version.version_string} is now #{version.app_store_state}"
      when "PROCESSING_FOR_APP_STORE", "PROCESSING_FOR_DISTRIBUTION", "READY_FOR_DISTRIBUTION", "READY_FOR_SALE"
        puts "Version #{version.version_string} is #{version.app_store_state}; nothing to release"
      else
        puts "Version #{version.version_string} is #{version.app_store_state}; release is only available after approval"
      end
    end

    def find_target_build!(app_id, app_version)
      if @options[:build_number]
        build = @asc.find_build_by_number(
          app_id,
          app_version,
          @options[:build_number],
          platform: platform
        )
        raise OptionParser::InvalidArgument, "build #{@options[:build_number]} not found for version #{app_version}" unless build
        unless valid_app_store_build?(build)
          raise OptionParser::InvalidArgument,
                "build #{@options[:build_number]} is not VALID and APP_STORE_ELIGIBLE for version #{app_version}"
        end

        return build
      end

      build = find_candidate_build(app_id, app_version)
      raise OptionParser::InvalidArgument, "no VALID App Store eligible build found for version #{app_version}" unless build

      build
    end

    def find_candidate_build(app_id, app_version)
      @asc.find_latest_eligible_build(app_id, app_version, platform: platform)
    end

    def valid_app_store_build?(build)
      attrs = build.fetch("attributes", {})
      attrs["processingState"] == "VALID" && attrs["buildAudienceType"] == "APP_STORE_ELIGIBLE"
    end

    def attach_build_to_version!(app, version, target_build)
      @asc.request_json(
        "PATCH",
        "/v1/appStoreVersions/#{version.id}/relationships/build",
        body: {
          data: { type: "builds", id: target_build["id"] }
        }
      )

      refreshed = @asc.find_editable_version!(app, platform: platform, app_version: version.version_string)
      target_number = target_build.dig("attributes", "version")
      unless refreshed.build&.version == target_number
        raise ArgumentError, "build attachment verification failed: expected #{target_number}, got #{refreshed.build&.version || 'none'}"
      end

      refreshed
    end

    def review_submissions(app_id)
      @asc.request_json(
        "GET",
        "/v1/reviewSubmissions",
        params: {
          "filter[app]" => app_id,
          "filter[platform]" => platform,
          "limit" => SUBMISSION_LIMIT.to_s
        }
      ).fetch("data", [])
    end

    def create_review_submission(app_id)
      @asc.request_json(
        "POST",
        "/v1/reviewSubmissions",
        body: {
          data: {
            type: "reviewSubmissions",
            attributes: { platform: platform },
            relationships: {
              app: {
                data: { type: "apps", id: app_id }
              }
            }
          }
        }
      ).fetch("data")
    end

    def review_submission_contains_version?(submission_id, version_id)
      review_submission_items_response(submission_id).fetch("data", []).any? do |item|
        item.dig("relationships", "appStoreVersion", "data", "id") == version_id
      end
    end

    def review_submission_items_response(submission_id)
      @asc.paginated_document(
        "/v1/reviewSubmissions/#{submission_id}/items",
        params: {
          "include" => SUBMISSION_ITEM_INCLUDES.join(",")
        },
        limit: SUBMISSION_ITEM_LIMIT
      )
    end

    def review_submission_items(submission_id)
      response = review_submission_items_response(submission_id)
      included_by_linkage = response.fetch("included", []).to_h do |resource|
        [[resource["type"], resource["id"]], resource]
      end

      response.fetch("data", []).map do |item|
        relationship_name, linkage = reviewable_item_linkage(item)
        included = included_by_linkage[[linkage&.fetch("type", nil), linkage&.fetch("id", nil)]]
        attributes = included&.fetch("attributes", {}) || {}

        {
          id: item["id"],
          state: item.dig("attributes", "state"),
          relationship: relationship_name,
          resource_type: linkage&.fetch("type", nil),
          resource_id: linkage&.fetch("id", nil),
          version: attributes["versionString"] || attributes["version"],
          name: attributes["name"],
          product_id: attributes["productId"]
        }.compact
      end
    end

    def reviewable_item_linkage(item)
      item.fetch("relationships", {}).each do |name, relationship|
        linkage = relationship["data"]
        return [name, linkage] if linkage.is_a?(Hash) && linkage["id"]
      end

      [nil, nil]
    end

    def create_review_submission_item(submission_id, version_id)
      @asc.request_json(
        "POST",
        "/v1/reviewSubmissionItems",
        body: {
          data: {
            type: "reviewSubmissionItems",
            relationships: {
              reviewSubmission: {
                data: { type: "reviewSubmissions", id: submission_id }
              },
              appStoreVersion: {
                data: { type: "appStoreVersions", id: version_id }
              }
            }
          }
        }
      ).fetch("data")
    end

    def create_release_request(version_id)
      @asc.request_json(
        "POST",
        "/v1/appStoreVersionReleaseRequests",
        body: {
          data: {
            type: "appStoreVersionReleaseRequests",
            relationships: {
              appStoreVersion: {
                data: { type: "appStoreVersions", id: version_id }
              }
            }
          }
        }
      ).fetch("data")
    end

    def find_release_target_version!(app)
      return @asc.find_version!(app, platform: platform, app_version: @options[:app_version]) if @options[:app_version]

      @asc.find_version!(app, platform: platform, states: RELEASEABLE_STATES)
    rescue ArgumentError
      @asc.find_version!(app, platform: platform)
    end

    def submit_review_submission(submission_id)
      @asc.request_json(
        "PATCH",
        "/v1/reviewSubmissions/#{submission_id}",
        body: {
          data: {
            type: "reviewSubmissions",
            id: submission_id,
            attributes: {
              submitted: true
            }
          }
        }
      ).fetch("data")
    end

    def build_summary(build)
      return nil unless build

      if build.is_a?(Hash)
        attrs = build.fetch("attributes", {})
        return {
          id: build["id"],
          number: attrs["version"],
          processing_state: attrs["processingState"],
          uploaded_date: attrs["uploadedDate"]
        }
      end

      {
        id: build.id,
        number: build.version,
        processing_state: build.processing_state
      }
    end

    def review_submission_summary(submission, include_items: false)
      summary = {
        id: submission["id"],
        platform: submission.dig("attributes", "platform"),
        state: submission.dig("attributes", "state"),
        submitted_date: submission.dig("attributes", "submittedDate")
      }
      summary[:items] = review_submission_items(submission["id"]) if include_items
      summary
    end

    def review_submission_item_label(item)
      resource = item[:relationship] || item[:resource_type] || "unknown"
      identity = if resource == "inAppPurchaseVersion"
                   iap_identity = item[:product_id] || item[:name] || item[:resource_id] || "unknown"
                   item[:version] ? "#{iap_identity} (version #{item[:version]})" : iap_identity
                 else
                   item[:version] || item[:product_id] || item[:name] || item[:resource_id] || "unknown"
                 end
      state = item[:state] || "UNKNOWN"
      "#{resource} #{identity} [#{state}]"
    end
  end
end
