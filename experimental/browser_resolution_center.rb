#!/usr/bin/env ruby

require "json"
require "optparse"
require "open3"
require "time"
require_relative "../lib/asc_tooling"

begin
  require "http/cookie_jar"
  require "http/cookie"
  require "spaceship"
rescue LoadError => e
  warn "This experimental script requires additional gems: gem install fastlane http-cookie"
  raise e
end

module Experimental
  class BrowserResolutionCenter
    def initialize(argv)
      @argv = argv
      @options = {
        platform: "mac",
        json: false
      }
    end

    def run
      parse_options!
      cookie_payload = JSON.parse(File.read(@options[:cookie_json]))
      provider_id = cookie_payload.fetch("provider_id")
      jar = build_cookie_jar(cookie_payload.fetch("cookies"))

      submission_id = @options[:submission_id] || find_submission_id_from_bundle!

      client = Spaceship::ConnectAPI::Tunes::Client.new(
        cookie: jar,
        current_team_id: provider_id
      )

      thread_response = client.get_resolution_center_threads(
        filter: { reviewSubmission: submission_id },
        includes: "reviewSubmission"
      )
      threads = thread_response.to_models
      raise ArgumentError, "no resolution center thread found for submission #{submission_id}" if threads.empty?

      thread = threads.first
      message_response = client.get_resolution_center_messages(
        thread_id: thread.id,
        includes: "rejections,fromActor"
      )
      messages = message_response.to_models
      raise ArgumentError, "no resolution center messages found for thread #{thread.id}" if messages.empty?

      latest = messages.max_by { |message| message.created_date || Time.at(0) }
      payload = format_output(submission_id, thread, latest)

      if @options[:json]
        puts JSON.pretty_generate(payload)
      else
        print_human(payload)
      end
    end

    private

    def parse_options!
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: browser_resolution_center.rb --cookie-json /tmp/cookies.json [--submission-id ... | --bundle-id ...] [options]"
        opts.on("--cookie-json PATH", "JSON exported by experimental/export_browser_asc_session.py") { |value| @options[:cookie_json] = value }
        opts.on("--submission-id ID", "Explicit App Store review submission id") { |value| @options[:submission_id] = value }
        opts.on("--bundle-id ID", "Bundle id to auto-resolve the latest relevant review submission") { |value| @options[:bundle_id] = value }
        opts.on("--key-id KEY_ID", "ASC API key id used when resolving a bundle id") { |value| @options[:key_id] = value }
        opts.on("--issuer-id ISSUER_ID", "ASC API issuer id used when resolving a bundle id") { |value| @options[:issuer_id] = value }
        opts.on("--key-path PATH", "Path to ASC API .p8 key used when resolving a bundle id") { |value| @options[:key_path] = value }
        opts.on("--platform PLATFORM", "mac, ios, tvos (default: mac)") { |value| @options[:platform] = value }
        opts.on("--json", "Emit JSON instead of text") { @options[:json] = true }
        opts.on("-h", "--help", "Show help") do
          puts opts
          exit 0
        end
      end
      parser.parse!(@argv)

      raise OptionParser::MissingArgument, "--cookie-json is required" unless @options[:cookie_json]
      raise OptionParser::MissingArgument, "pass --submission-id or --bundle-id" unless @options[:submission_id] || @options[:bundle_id]
    end

    def build_cookie_jar(cookie_data)
      jar = HTTP::CookieJar.new
      cookie_data.each do |row|
        cookie = HTTP::Cookie.new(
          row.fetch("name"),
          row.fetch("value"),
          domain: row.fetch("domain"),
          path: row.fetch("path"),
          secure: row.fetch("secure"),
          expires: row["expires"] ? Time.at(row["expires"]) : nil
        )
        jar.add(cookie)
      end
      jar
    end

    def find_submission_id_from_bundle!
      command = [
        "bundle", "exec", "asc-review", "status",
        "--bundle-id", @options.fetch(:bundle_id),
        *auth_command_args,
        "--json"
      ]
      stdout, stderr, status = Open3.capture3(*command)
      raise "asc-review status failed: #{stderr}" unless status.success?

      payload = JSON.parse(stdout)
      prioritized = Array(payload["review_submissions"]).sort_by do |submission|
        state_rank = case submission["state"]
                     when "UNRESOLVED_ISSUES" then 0
                     when "WAITING_FOR_REVIEW" then 1
                     when "IN_REVIEW" then 2
                     else 3
                     end
        submitted_date = submission["submitted_date"] || ""
        [state_rank, submitted_date.empty? ? "0000" : submitted_date]
      end
      submission = prioritized.first
      raise "no review submission found for #{payload['bundle_id']}" unless submission

      submission.fetch("id")
    end

    def auth_command_args
      auth_options = ASCTooling::Client.auth_options_from(@options)
      args = []
      args.push("--key-id", auth_options[:key_id]) unless ASCTooling::Client.blank?(auth_options[:key_id])
      args.push("--issuer-id", auth_options[:issuer_id]) unless ASCTooling::Client.blank?(auth_options[:issuer_id])
      args.push("--key-path", auth_options[:key_path]) unless ASCTooling::Client.blank?(auth_options[:key_path])
      args
    end

    def format_output(submission_id, thread, message)
      rejection = extract_rejection(Array(message.rejections).first)
      {
        submission_id: submission_id,
        thread_id: thread.id,
        thread_type: thread.thread_type,
        message_id: message.id,
        created_date: normalize_time(message.created_date),
        from_actor_type: actor_type(message.from_actor),
        body: message_body(message),
        rejection: rejection
      }
    end

    def print_human(payload)
      puts "Submission: #{payload[:submission_id]}"
      puts "Thread: #{payload[:thread_id]} (#{payload[:thread_type]})"
      puts "Message: #{payload[:message_id]}"
      puts "Created: #{payload[:created_date]}" if payload[:created_date]
      puts "Reason: #{payload[:rejection][:reason_code]} - #{payload[:rejection][:reason_description]}" if payload[:rejection]
      puts
      puts payload[:body].to_s.strip
    end

    def normalize_time(value)
      return nil if value.nil?
      return value.iso8601 if value.respond_to?(:iso8601)

      value.to_s
    end

    def actor_type(value)
      return nil if value.nil?
      return value.actor_type if value.respond_to?(:actor_type)
      return value.type if value.respond_to?(:type)

      value.to_s
    end

    def message_body(message)
      return message.message_body if message.respond_to?(:message_body)
      return message.body if message.respond_to?(:body)

      message.to_s
    end

    def extract_rejection(rejection)
      return nil if rejection.nil?

      reasons = rejection.respond_to?(:reasons) ? Array(rejection.reasons) : []
      reason = reasons.first || {}
      {
        id: rejection.respond_to?(:id) ? rejection.id : nil,
        reason_code: reason["reasonCode"] || reason[:reasonCode],
        reason_description: reason["reasonDescription"] || reason[:reasonDescription]
      }
    end
  end
end

Experimental::BrowserResolutionCenter.new(ARGV).run
