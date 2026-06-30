require "fileutils"
require "json"
require "pathname"

module ASCTooling
  module SkillInstaller
    SKILL_NAME = "asc-tooling".freeze
    CLIENTS = %w[agents codex claude].freeze

    Result = Struct.new(:action, :paths, keyword_init: true) do
      def to_json(*_args)
        JSON.generate({
                        action: action,
                        paths: paths.map(&:to_s)
                      })
      end
    end

    module_function

    def bundled_skill_dir
      root = Pathname.new(__dir__).join("..", "..").expand_path
      skill_dir = root.join("skills", SKILL_NAME)
      return skill_dir if skill_dir.join("SKILL.md").file?

      raise Errno::ENOENT, "Bundled #{SKILL_NAME} skill was not found."
    end

    def print_skill
      bundled_skill_dir.join("SKILL.md").read
    end

    def resolve_client_destinations(client, home: Pathname.new(Dir.home), env: ENV)
      case client
      when "agents"
        [home.join(".agents", "skills")]
      when "codex"
        [codex_home(env: env, home: home).join("skills")]
      when "claude"
        [claude_home(env: env, home: home).join("skills")]
      else
        raise ArgumentError, "unsupported client: #{client}"
      end
    end

    def codex_home(env:, home:)
      value = env["CODEX_HOME"].to_s.strip
      return Pathname.new(value).expand_path unless value.empty?

      home.join(".codex")
    end

    def claude_home(env:, home:)
      value = env["CLAUDE_CONFIG_DIR"].to_s.strip
      return Pathname.new(value).expand_path unless value.empty?

      home.join(".claude")
    end

    def install_skill(destination, force: false)
      source = bundled_skill_dir
      target = Pathname.new(destination).expand_path.join(SKILL_NAME)
      assert_not_bundled_skill_target!(target)
      FileUtils.mkdir_p(target.dirname)

      if target.exist?
        raise Errno::EEXIST, "Skill already installed at #{target}. Re-run with --force to overwrite." unless force

        FileUtils.rm_rf(target)
      end

      FileUtils.cp_r(source, target)
      target
    end

    def uninstall_skill(destination)
      target = Pathname.new(destination).expand_path.join(SKILL_NAME)
      assert_not_bundled_skill_target!(target)
      FileUtils.rm_rf(target) if target.exist?
      target
    end

    def assert_not_bundled_skill_target!(target)
      source = bundled_skill_dir
      resolved_target = target.exist? ? target.realpath : target.expand_path
      return unless resolved_target == source.realpath

      raise ArgumentError, "Refusing to modify bundled #{SKILL_NAME} skill at #{source}. Choose a different --dest."
    end

    def install_to_targets(destinations, force: false)
      Result.new(
        action: "installed",
        paths: destinations.map { |destination| install_skill(destination, force: force) }
      )
    end

    def uninstall_from_targets(destinations)
      Result.new(
        action: "uninstalled",
        paths: destinations.map { |destination| uninstall_skill(destination) }
      )
    end
  end
end
