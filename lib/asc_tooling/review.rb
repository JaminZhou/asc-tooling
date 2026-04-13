require "json"
require "optparse"

module ASCTooling
  class Review
    BUILD_LIMIT = 20
    SUBMISSION_LIMIT = 20
    SUBMISSION_ITEM_LIMIT = 50

    RELEASEABLE_STATES = %w[
      PENDING_DEVELOPER_RELEASE
      PROCESSING_FOR_APP_STORE
      PROCESSING_FOR_DISTRIBUTION
      READY_FOR_DISTRIBUTION
      READY_FOR_SALE
    ].freeze

    def self.run(argv = ARGV)
      options = {
        platform: "macos",
        command: argv.shift
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: asc-review <status|submit|withdraw|release> --bundle-id com.example.app [options]"

        opts.on("--bundle-id BUNDLE_ID", "App bundle identifier") { |value| options[:bundle_id] = value }
        opts.on("--app-version VERSION", "Editable App Store version to target") { |value| options[:app_version] = value }
        opts.on("--build-number BUILD", "Build number to attach instead of latest VALID build") { |value| options[:build_number] = value }
        opts.on("--platform PLATFORM", "ios, macos, or tvos (default: macos)") { |value| options[:platform] = value }
        opts.on("--release-type TYPE", "manual or after-approval (submit only)") { |value| options[:release_type] = value }
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
        review_submissions: submissions.map { |submission| review_submission_summary(submission) }
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
        submissions.each do |submission|
          puts "Review submission: #{submission['id']} [#{submission.dig('attributes', 'state')}]"
        end
      end
    end

    def submit_for_review
      app = @asc.find_app!(@options[:bundle_id])
      version = @asc.find_editable_version!(app, platform: platform, app_version: @options[:app_version])

      if @options[:release_type]
        desired_release_type = ASCTooling::Client::RELEASE_TYPE_MAP.fetch(@options[:release_type]) do
          raise OptionParser::InvalidArgument, "unsupported release type: #{@options[:release_type]}"
        end
        if version.release_type != desired_release_type
          @asc.update_resource("appStoreVersions", version.id,
                               attributes: { releaseType: desired_release_type })
        end
        version = @asc.find_editable_version!(app, platform: platform, app_version: @options[:app_version])
      end

      submitted_submission = review_submissions(app.id).find { |submission| submission.dig("attributes", "state") == "WAITING_FOR_REVIEW" }
      if submitted_submission
        puts "Already waiting for review: #{submitted_submission['id']}"
        return
      end

      target_build = find_target_build!(app.id, version.version_string)

      if @options[:dry_run]
        puts "Dry run: would attach build #{target_build.dig('attributes', 'version')} to version #{version.version_string} and submit for review."
        return
      end

      if version.build.nil? || version.build.version != target_build.dig("attributes", "version")
        @asc.request_json(
          "PATCH",
          "/v1/appStoreVersions/#{version.id}",
          body: {
            data: {
              type: "appStoreVersions",
              id: version.id,
              relationships: {
                build: { data: { type: "builds", id: target_build["id"] } }
              }
            }
          }
        )
        version = @asc.find_editable_version!(app, platform: platform, app_version: @options[:app_version])
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
      version = @asc.find_editable_version!(app, platform: platform, app_version: @options[:app_version])

      unless version.app_store_state == "WAITING_FOR_REVIEW"
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
      version = @asc.find_editable_version!(app, platform: platform, app_version: @options[:app_version])

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
        build = build_candidates(app_id, app_version).find { |item| item.dig("attributes", "version") == @options[:build_number] }
        raise OptionParser::InvalidArgument, "build #{@options[:build_number]} not found for version #{app_version}" unless build

        return build
      end

      build = find_candidate_build(app_id, app_version)
      raise OptionParser::InvalidArgument, "no VALID App Store eligible build found for version #{app_version}" unless build

      build
    end

    def find_candidate_build(app_id, app_version)
      build_candidates(app_id, app_version).find do |item|
        attrs = item.fetch("attributes", {})
        attrs["processingState"] == "VALID" && attrs["buildAudienceType"] == "APP_STORE_ELIGIBLE"
      end
    end

    def build_candidates(app_id, app_version)
      @asc.build_candidates(app_id, app_version, limit: BUILD_LIMIT)
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
      @asc.request_json(
        "GET",
        "/v1/reviewSubmissions/#{submission_id}/items",
        params: {
          "include" => "appStoreVersion",
          "limit" => SUBMISSION_ITEM_LIMIT.to_s
        }
      ).fetch("included", []).any? do |included|
        included["type"] == "appStoreVersions" && included["id"] == version_id
      end
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

    def review_submission_summary(submission)
      {
        id: submission["id"],
        platform: submission.dig("attributes", "platform"),
        state: submission.dig("attributes", "state"),
        submitted_date: submission.dig("attributes", "submittedDate")
      }
    end
  end
end
