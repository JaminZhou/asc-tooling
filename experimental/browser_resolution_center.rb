#!/usr/bin/env ruby

require "json"
require "net/http"
require "optparse"
require "open3"
require "time"
require "uri"
require_relative "../lib/asc_tooling"

module Experimental
  class BrowserResolutionCenter
    TUNES_BASE_URL = "https://appstoreconnect.apple.com/iris/v1".freeze

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
      @provider_id = cookie_payload.fetch("provider_id")
      @cookie_header = build_cookie_header(cookie_payload.fetch("cookies"), URI(TUNES_BASE_URL))

      submission_id = @options[:submission_id] || find_submission_id_from_bundle!

      threads = get_resolution_center_threads(submission_id)
      raise ArgumentError, "no resolution center thread found for submission #{submission_id}" if threads.empty?

      thread = threads.first
      messages = get_resolution_center_messages(thread["id"])
      raise ArgumentError, "no resolution center messages found for thread #{thread['id']}" if messages.empty?

      latest = messages.max_by { |m| m.dig("attributes", "createdDate") || "0000" }
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

    def build_cookie_header(cookie_data, target_uri)
      host = target_uri.host.downcase
      path = target_uri.path.empty? ? "/" : target_uri.path
      now = Time.now

      cookie_data.select { |c| cookie_applicable?(c, host, path, now) }
                 .sort_by { |c| -c.fetch("path", "/").length }
                 .map { |c| "#{c.fetch('name')}=#{c.fetch('value')}" }
                 .join("; ")
    end

    def cookie_applicable?(cookie, host, path, now)
      return false unless domain_matches?(cookie.fetch("domain"), host)
      return false unless path_matches?(cookie.fetch("path", "/"), path)
      # secure cookies are fine — all Apple endpoints are HTTPS
      return false if cookie["expires"] && Time.at(cookie["expires"]) < now

      true
    end

    def path_matches?(cookie_path, request_path)
      return true if cookie_path == request_path
      return true if request_path.start_with?(cookie_path) &&
                     (cookie_path.end_with?("/") || request_path[cookie_path.length] == "/")

      false
    end

    def domain_matches?(cookie_domain, host)
      cookie_domain = cookie_domain.downcase
      if cookie_domain.start_with?(".")
        suffix = cookie_domain[1..]
        host == suffix || host.end_with?(".#{suffix}")
      else
        host == cookie_domain.downcase
      end
    end

    def tunes_request(path, params = {})
      uri = URI("#{TUNES_BASE_URL}/#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["Cookie"] = @cookie_header
      request["X-Apple-Widget-Key"] = ""
      request["X-Requested-With"] = "XMLHttpRequest"
      request["X-Apple-Provider-Id"] = @provider_id if @provider_id

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 30
      http.read_timeout = 60

      response = http.request(request)
      raise "Tunes API request failed (#{response.code}): #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def get_resolution_center_threads(submission_id)
      data = tunes_request("reviewCenterThreads", {
                             "filter[reviewSubmission]" => submission_id,
                             "include" => "reviewSubmission"
                           })
      data.fetch("data", [])
    end

    def get_resolution_center_messages(thread_id)
      response = tunes_request("reviewCenterThreads/#{thread_id}/reviewCenterMessages", {
                                 "include" => "rejections,fromActor"
                               })
      @included = response.fetch("included", [])
      response.fetch("data", [])
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
      attrs = message.fetch("attributes", {})
      rejection = extract_rejection(message, attrs)
      {
        submission_id: submission_id,
        thread_id: thread["id"],
        thread_type: thread.dig("attributes", "threadType"),
        message_id: message["id"],
        created_date: attrs["createdDate"],
        from_actor_type: attrs["fromActorType"],
        body: attrs["messageBody"] || attrs["body"],
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

    def extract_rejection(message, _attrs)
      refs = message.dig("relationships", "rejections", "data")
      return nil if refs.nil? || refs.empty?

      ref = refs.first
      rejection = @included.find { |r| r["type"] == ref["type"] && r["id"] == ref["id"] }
      return { id: ref["id"], reason_code: nil, reason_description: nil } unless rejection

      reasons = rejection.dig("attributes", "reasons") || []
      reason = reasons.first || {}
      {
        id: rejection["id"],
        reason_code: reason["reasonCode"],
        reason_description: reason["reasonDescription"]
      }
    end
  end
end

Experimental::BrowserResolutionCenter.new(ARGV).run
