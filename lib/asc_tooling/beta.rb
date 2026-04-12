require "json"
require "optparse"

module ASCTooling
  class Beta
    def self.run(argv = ARGV)
      options = {
        command: argv.shift
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: asc-beta <status|create-group|add-build|add-tester|remove-tester|set-test-notes> --bundle-id com.example.app [options]"

        opts.on("--bundle-id BUNDLE_ID", "App bundle identifier") { |value| options[:bundle_id] = value }
        opts.on("--app-version VERSION", "Pre-release version to filter builds") { |value| options[:app_version] = value }
        opts.on("--group-name NAME", "Beta group name") { |value| options[:group_name] = value }
        opts.on("--group-id ID", "Beta group id") { |value| options[:group_id] = value }
        opts.on("--build-number BUILD", "Build number to add instead of latest VALID build") { |value| options[:build_number] = value }
        opts.on("--tester-id ID", "Beta tester id") { |value| options[:tester_id] = value }
        opts.on("--email EMAIL", "Beta tester email") { |value| options[:email] = value }
        opts.on("--first-name NAME", "First name when creating a tester") { |value| options[:first_name] = value }
        opts.on("--last-name NAME", "Last name when creating a tester") { |value| options[:last_name] = value }
        opts.on("--create-if-missing", "Create a tester if the email does not already exist") { options[:create_if_missing] = true }
        opts.on("--internal", "Create an internal beta group (team members only)") { options[:internal] = true }
        opts.on("--all-builds", "Give the beta group access to all builds") { options[:all_builds] = true }
        opts.on("--notes TEXT", "Test notes (What to Test) for set-test-notes") { |value| options[:notes] = value }
        opts.on("--locale LOCALE", "Locale for test notes (default: en-US)") { |value| options[:locale] = value }
        opts.on("--dry-run", "Show what would happen without changing ASC") { options[:dry_run] = true }
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
      when "create-group" then create_group
      when "add-build" then add_build
      when "add-tester" then add_tester
      when "remove-tester" then remove_tester
      when "set-test-notes" then set_test_notes
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
      app = @asc.find_app!(@options[:bundle_id])
      latest_build = latest_valid_build(app.id, @options[:app_version])
      groups = beta_groups(app.id)

      summary = {
        app_name: app.name,
        bundle_id: app.bundle_id,
        latest_valid_build: build_summary(latest_build),
        groups: groups.map { |group| beta_group_summary(group) }
      }

      if @options[:json]
        puts JSON.pretty_generate(summary)
        return
      end

      puts "App: #{summary[:app_name]} (#{summary[:bundle_id]})"
      puts(latest_build ? "Latest valid build: #{latest_build.dig('attributes', 'version')}" : "Latest valid build: none")

      if summary[:groups].empty?
        puts "Beta groups: none"
        return
      end

      summary[:groups].each do |group|
        internal_label = group[:is_internal] ? "internal" : "external"
        all_builds_label = group[:all_builds] ? ", all builds" : ""
        puts "Group: #{group[:name]} [#{internal_label}#{all_builds_label}]"
        puts "  Testers (#{group[:tester_count]}): #{group[:testers].join(', ')}" unless group[:testers].empty?
        puts "  Builds (#{group[:build_count]}): #{group[:builds].join(', ')}" unless group[:builds].empty?
      end
    end

    def create_group
      group_name = @options[:group_name]
      raise OptionParser::MissingArgument, "--group-name is required for create-group" if ASCTooling::Client.blank?(group_name)

      app = @asc.find_app!(@options[:bundle_id])
      existing = beta_groups(app.id).find { |item| item.dig("attributes", "name") == group_name }

      if existing
        puts "No change needed: beta group #{group_name.inspect} already exists."
        return
      end

      if @options[:dry_run]
        puts "Dry run: would create beta group #{group_name.inspect} for #{app.name}."
        return
      end

      @asc.request_json(
        "POST",
        "/v1/betaGroups",
        body: {
          data: {
            type: "betaGroups",
            attributes: {
              name: group_name,
              isInternalGroup: @options[:internal] ? true : false,
              hasAccessToAllBuilds: @options[:all_builds] ? true : false
            },
            relationships: {
              app: {
                data: {
                  type: "apps",
                  id: app.id
                }
              }
            }
          }
        }
      )

      puts "Created beta group #{group_name.inspect} for #{app.name}."
    end

    def add_build
      app = @asc.find_app!(@options[:bundle_id])
      group = target_group!(app.id)
      build = target_build!(app.id)

      if group.dig("attributes", "hasAccessToAllBuilds")
        puts "No change needed: beta group #{group.dig('attributes', 'name')} already has access to all builds."
        return
      end

      existing_build_ids = group.fetch("relationships", {}).fetch("builds", {}).fetch("data", []).map { |item| item["id"] }
      if existing_build_ids.include?(build["id"])
        puts "No change needed: build #{build.dig('attributes', 'version')} is already in beta group #{group.dig('attributes', 'name')}."
        return
      end

      if @options[:dry_run]
        puts "Dry run: would add build #{build.dig('attributes', 'version')} to beta group #{group.dig('attributes', 'name')}."
        return
      end

      @asc.request_json(
        "POST",
        "/v1/betaGroups/#{group['id']}/relationships/builds",
        body: {
          data: [
            {
              type: "builds",
              id: build["id"]
            }
          ]
        }
      )

      puts "Added build #{build.dig('attributes', 'version')} to beta group #{group.dig('attributes', 'name')}."
    end

    def add_tester
      app = @asc.find_app!(@options[:bundle_id])
      group = target_group!(app.id)
      tester = target_tester!(app.id, group: group, allow_create: @options[:create_if_missing])

      if group_tester_ids(group).include?(tester["id"])
        puts "No change needed: tester #{tester_label(tester)} is already in beta group #{group.dig('attributes', 'name')}."
        return
      end

      if @options[:dry_run]
        puts "Dry run: would add tester #{tester_label(tester)} to beta group #{group.dig('attributes', 'name')}."
        return
      end

      @asc.request_json(
        "POST",
        "/v1/betaTesters/#{tester['id']}/relationships/betaGroups",
        body: {
          data: [
            {
              type: "betaGroups",
              id: group["id"]
            }
          ]
        }
      )

      puts "Added tester #{tester_label(tester)} to beta group #{group.dig('attributes', 'name')}."
    end

    def remove_tester
      app = @asc.find_app!(@options[:bundle_id])
      group = target_group!(app.id)
      tester = target_tester!(app.id, group: group, require_group_membership: true)

      if @options[:dry_run]
        puts "Dry run: would remove tester #{tester_label(tester)} from beta group #{group.dig('attributes', 'name')}."
        return
      end

      @asc.request_json(
        "DELETE",
        "/v1/betaTesters/#{tester['id']}/relationships/betaGroups",
        body: {
          data: [
            {
              type: "betaGroups",
              id: group["id"]
            }
          ]
        }
      )

      puts "Removed tester #{tester_label(tester)} from beta group #{group.dig('attributes', 'name')}."
    end

    def set_test_notes
      notes = @options[:notes]
      raise OptionParser::MissingArgument, "--notes is required for set-test-notes" if ASCTooling::Client.blank?(notes)

      app = @asc.find_app!(@options[:bundle_id])
      build = target_build!(app.id)
      locale = @options[:locale] || "en-US"
      build_version = build.dig("attributes", "version")

      localizations = @asc.request_json(
        "GET",
        "/v1/builds/#{build['id']}/betaBuildLocalizations"
      ).fetch("data", [])

      localization = localizations.find { |item| item.dig("attributes", "locale") == locale }

      if localization
        @asc.request_json(
          "PATCH",
          "/v1/betaBuildLocalizations/#{localization['id']}",
          body: {
            data: {
              type: "betaBuildLocalizations",
              id: localization["id"],
              attributes: { whatsNew: notes }
            }
          }
        )
      else
        @asc.request_json(
          "POST",
          "/v1/betaBuildLocalizations",
          body: {
            data: {
              type: "betaBuildLocalizations",
              attributes: { locale: locale, whatsNew: notes },
              relationships: {
                build: { data: { type: "builds", id: build["id"] } }
              }
            }
          }
        )
      end

      puts "Set test notes for build #{build_version} (#{locale})."
    end

    def target_group!(app_id)
      groups = beta_groups(app_id)

      if @options[:group_id]
        group = groups.find { |item| item["id"] == @options[:group_id] }
        raise ArgumentError, "beta group #{@options[:group_id]} not found" unless group

        return group
      end

      group_name = @options[:group_name]
      raise OptionParser::MissingArgument, "group name or group id is required" if ASCTooling::Client.blank?(group_name)

      group = groups.find { |item| item.dig("attributes", "name") == group_name }
      raise ArgumentError, "beta group #{group_name.inspect} not found" unless group

      group
    end

    def target_tester!(app_id, group:, allow_create: false, require_group_membership: false)
      if @options[:tester_id]
        tester = fetch_beta_tester!(@options[:tester_id])
        if require_group_membership && !group_tester_ids(group).include?(tester["id"])
          raise ArgumentError, "tester #{@options[:tester_id]} is not in beta group #{group.dig('attributes', 'name')}"
        end

        return tester
      end

      email = @options[:email]
      raise OptionParser::MissingArgument, "tester email or tester id is required" if ASCTooling::Client.blank?(email)

      app_testers = app_testers_by_email(app_id, email)
      app_testers.select! { |tester| group_tester_ids(group).include?(tester["id"]) } if require_group_membership

      case app_testers.size
      when 1
        app_testers.first
      when 0
        if require_group_membership
          raise ArgumentError, "tester #{email.inspect} is not in beta group #{group.dig('attributes', 'name')}"
        end

        global_testers = beta_testers_by_email(email)
        resolved_global_tester = resolve_global_tester(global_testers, app_id: app_id, group: group)
        return resolved_global_tester if resolved_global_tester

        if global_testers.size > 1
          raise ArgumentError, "multiple testers found for #{email.inspect}; use --tester-id to disambiguate"
        end

        return create_beta_tester!(email) if allow_create

        raise ArgumentError, "tester #{email.inspect} not found; retry with --create-if-missing to create one"
      else
        raise ArgumentError, "multiple testers found for #{email.inspect}; use --tester-id to disambiguate"
      end
    end

    def target_build!(app_id)
      if @options[:build_number]
        build = build_candidates(app_id, @options[:app_version]).find { |item| item.dig("attributes", "version") == @options[:build_number] }
        raise ArgumentError, "build #{@options[:build_number]} not found" unless build

        return build
      end

      build = latest_valid_build(app_id, @options[:app_version])
      raise ArgumentError, "no VALID build found" unless build

      build
    end

    def latest_valid_build(app_id, app_version)
      build_candidates(app_id, app_version).find do |item|
        item.dig("attributes", "processingState") == "VALID"
      end
    end

    def build_candidates(app_id, app_version)
      params = {
        "filter[app]" => app_id,
        "sort" => "-uploadedDate",
        "limit" => "20"
      }
      params["filter[preReleaseVersion.version]"] = app_version unless ASCTooling::Client.blank?(app_version)

      @asc.request_json("GET", "/v1/builds", params: params).fetch("data", [])
    end

    def beta_groups(app_id)
      @asc.request_json(
        "GET",
        "/v1/betaGroups",
        params: {
          "filter[app]" => app_id,
          "include" => "builds,betaTesters",
          "limit" => "50"
        }
      ).fetch("data", [])
        .sort_by { |item| item.dig("attributes", "name").to_s.downcase }
    end

    def beta_testers_by_email(email)
      @asc.request_json(
        "GET",
        "/v1/betaTesters",
        params: {
          "filter[email]" => email,
          "limit" => "50"
        }
      ).fetch("data", [])
    end

    def resolve_global_tester(testers, app_id:, group:)
      return nil if testers.empty?
      return testers.first if testers.size == 1

      group_ids = beta_groups(app_id).map { |item| item["id"] }
      prioritized = testers
        .map { |tester| [tester, tester_group_ids(tester)] }
        .sort_by do |tester, tester_group_ids|
          [
            tester_group_ids.include?(group["id"]) ? 0 : 1,
            (tester_group_ids & group_ids).empty? ? 1 : 0,
            tester_group_ids.empty? ? 1 : 0,
            tester["id"]
          ]
        end

      best_tester, best_group_ids = prioritized.first
      next_tester, next_group_ids = prioritized[1]
      return best_tester if next_tester.nil?

      best_score = [
        best_group_ids.include?(group["id"]) ? 0 : 1,
        (best_group_ids & group_ids).empty? ? 1 : 0,
        best_group_ids.empty? ? 1 : 0
      ]
      next_score = [
        next_group_ids.include?(group["id"]) ? 0 : 1,
        (next_group_ids & group_ids).empty? ? 1 : 0,
        next_group_ids.empty? ? 1 : 0
      ]

      (best_score <=> next_score) == -1 ? best_tester : nil
    end

    def fetch_beta_tester!(tester_id)
      @asc.request_json("GET", "/v1/betaTesters/#{tester_id}").fetch("data")
    rescue ASCTooling::APIError => e
      raise unless e.status == 404

      raise ArgumentError, "beta tester #{tester_id} not found"
    end

    def create_beta_tester!(email)
      first_name = @options[:first_name]
      last_name = @options[:last_name]

      if ASCTooling::Client.blank?(first_name) || ASCTooling::Client.blank?(last_name)
        raise OptionParser::MissingArgument, "first name and last name are required when creating a tester"
      end

      if @options[:dry_run]
        return {
          "id" => "dry-run",
          "attributes" => {
            "email" => email,
            "firstName" => first_name,
            "lastName" => last_name,
            "state" => "DRY_RUN"
          }
        }
      end

      @asc.request_json(
        "POST",
        "/v1/betaTesters",
        body: {
          data: {
            type: "betaTesters",
            attributes: {
              email: email,
              firstName: first_name,
              lastName: last_name
            }
          }
        }
      ).fetch("data")
    end

    def app_testers_by_email(app_id, email)
      groups = beta_groups(app_id)
      tester_ids = groups.flat_map { |group| group_tester_ids(group) }.uniq
      testers = groups.flat_map do |group|
        included_objects_for(group).fetch("betaTesters", [])
      end
      testers.select { |tester| tester_ids.include?(tester["id"]) && tester.dig("attributes", "email") == email }.uniq { |tester| tester["id"] }
    end

    def group_tester_ids(group)
      group.fetch("relationships", {}).fetch("betaTesters", {}).fetch("data", []).map { |item| item["id"] }
    end

    def tester_group_ids(tester)
      @asc.request_json(
        "GET",
        "/v1/betaTesters/#{tester['id']}",
        params: {
          "include" => "betaGroups"
        }
      ).fetch("included", [])
        .select { |item| item["type"] == "betaGroups" }
        .map { |item| item["id"] }
    end

    def beta_group_summary(group)
      included = included_objects_for(group)
      builds = included.fetch("builds", []).map { |item| item.dig("attributes", "version") }.sort
      testers = included.fetch("betaTesters", []).map { |item| tester_label(item) }.sort

      {
        id: group["id"],
        name: group.dig("attributes", "name"),
        is_internal: group.dig("attributes", "isInternalGroup"),
        all_builds: group.dig("attributes", "hasAccessToAllBuilds"),
        build_count: builds.size,
        builds: builds,
        tester_count: testers.size,
        testers: testers
      }
    end

    def included_objects_for(group)
      payload = @asc.request_json(
        "GET",
        "/v1/betaGroups",
        params: {
          "filter[id]" => group["id"],
          "include" => "builds,betaTesters",
          "limit" => "1"
        }
      )
      included = payload.fetch("included", [])
      included.group_by { |item| item["type"] }
    end

    def tester_label(tester)
      state = tester.dig("attributes", "state")
      email = tester.dig("attributes", "email")
      state_label = ASCTooling::Client.blank?(state) ? "UNKNOWN" : state
      "#{email} [#{state_label}]"
    end

    def build_summary(build)
      return nil unless build

      {
        id: build["id"],
        number: build.dig("attributes", "version"),
        processing_state: build.dig("attributes", "processingState"),
        uploaded_date: build.dig("attributes", "uploadedDate")
      }
    end
  end
end
