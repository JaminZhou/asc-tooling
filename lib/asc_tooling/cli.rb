require "json"
require "optparse"
require "pathname"

module ASCTooling
  class CLI
    COMMANDS = {
      "review" => ["asc-review", ASCTooling::Review],
      "metadata" => ["asc-metadata", ASCTooling::Metadata],
      "beta" => ["asc-beta", ASCTooling::Beta],
      "sales" => ["asc-sales", ASCTooling::Sales],
      "screenshots" => ["asc-screenshots", ASCTooling::Screenshots],
      "iap" => ["asc-iap", ASCTooling::IAP],
      "version" => ["asc-version", ASCTooling::AppVersion],
      "availability" => ["asc-availability", ASCTooling::Availability],
      "store-setup" => ["asc-store-setup", ASCTooling::StoreSetup]
    }.freeze

    def self.run(argv = ARGV)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv.dup
    end

    def run
      command = @argv.shift

      case command
      when nil, "-h", "--help", "help"
        print_help
        0
      when "commands"
        print_commands
        0
      when "init"
        run_init(@argv)
      else
        dispatch(command, @argv)
      end
    rescue ArgumentError, OptionParser::ParseError, SystemCallError => e
      warn "asc-tooling: #{e.message}"
      1
    end

    private

    def dispatch(command, args)
      executable, klass = COMMANDS.fetch(command) do
        raise OptionParser::InvalidArgument, "unknown command: #{command.inspect}. Run `asc-tooling commands`."
      end
      warn "Delegating to #{executable}..." if args.delete("--verbose-dispatch")
      klass.run(args)
    end

    def print_help
      puts <<~HELP
        Usage: asc-tooling <command> [options]

        Unified entrypoint for asc_tooling's App Store Connect CLIs.

        Commands:
          init           Install, print, or remove the bundled Agent/Codex/Claude skill
          commands       List command aliases
          review         Delegate to asc-review
          metadata       Delegate to asc-metadata
          beta           Delegate to asc-beta
          sales          Delegate to asc-sales
          screenshots    Delegate to asc-screenshots
          iap            Delegate to asc-iap
          version        Delegate to asc-version
          availability   Delegate to asc-availability
          store-setup    Delegate to asc-store-setup

        Examples:
          asc-tooling init --client codex
          asc-tooling init --client claude
          asc-tooling review status --bundle-id com.example.app
          asc-tooling commands
      HELP
    end

    def print_commands
      puts "| alias | executable |"
      puts "| --- | --- |"
      COMMANDS.each do |alias_name, (executable, _klass)|
        puts "| #{alias_name} | #{executable} |"
      end
    end

    def run_init(args)
      options = {
        client: "codex",
        force: false,
        uninstall: false,
        print: false,
        json: false
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: asc-tooling init [options]"
        opts.on("--client CLIENT", ASCTooling::SkillInstaller::CLIENTS, "agents, codex, or claude (default: codex)") do |value|
          options[:client] = value
        end
        opts.on("--dest PATH", "Custom skills directory. Overrides --client.") { |value| options[:dest] = Pathname.new(value) }
        opts.on("--force", "Overwrite an existing installed skill") { options[:force] = true }
        opts.on("--uninstall", "Remove the installed skill") { options[:uninstall] = true }
        opts.on("--print", "Print bundled SKILL.md without installing") { options[:print] = true }
        opts.on("--json", "Emit compact JSON") { options[:json] = true }
      end
      parser.parse!(args)

      if options[:print]
        if options[:uninstall] || options[:dest] || options[:force]
          raise OptionParser::InvalidOption,
                "init --print cannot be combined with --uninstall, --dest, or --force"
        end

        content = ASCTooling::SkillInstaller.print_skill
        options[:json] ? puts(JSON.generate({ action: "printed", content: content })) : print(content)
        return 0
      end

      destinations = options[:dest] ? [options[:dest]] : ASCTooling::SkillInstaller.resolve_client_destinations(options[:client])
      result = if options[:uninstall]
                 ASCTooling::SkillInstaller.uninstall_from_targets(destinations)
               else
                 ASCTooling::SkillInstaller.install_to_targets(destinations, force: options[:force])
               end

      if options[:json]
        puts result.to_json
      else
        verb = options[:uninstall] ? "Removed" : "Installed"
        result.paths.each { |path| puts "#{verb} #{ASCTooling::SkillInstaller::SKILL_NAME} skill -> #{path}" }
      end
      0
    end
  end
end
