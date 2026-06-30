require "tmpdir"

require "test_helper"

class CLITest < Minitest::Test
  def test_commands_lists_unified_aliases
    stdout, stderr = capture_io do
      assert_equal 0, ASCTooling::CLI.run(["commands"])
    end

    assert_empty stderr
    assert_includes stdout, "review"
    assert_includes stdout, "asc-review"
    assert_includes stdout, "store-setup"
  end

  def test_init_print_outputs_skill
    stdout, stderr = capture_io do
      assert_equal 0, ASCTooling::CLI.run(["init", "--print"])
    end

    assert_empty stderr
    assert_includes stdout, "name: asc-tooling"
  end

  def test_init_installs_skill_to_custom_destination
    Dir.mktmpdir do |dir|
      stdout, stderr = capture_io do
        assert_equal 0, ASCTooling::CLI.run(["init", "--dest", dir])
      end

      assert_empty stderr
      assert_includes stdout, "Installed asc-tooling skill"
      assert File.file?(File.join(dir, "asc-tooling", "SKILL.md"))
    end
  end

  def test_init_defaults_to_codex_home_skills
    Dir.mktmpdir do |dir|
      codex_home = File.join(dir, ".codex")

      with_env("CODEX_HOME" => codex_home) do
        stdout, stderr = capture_io do
          assert_equal 0, ASCTooling::CLI.run(["init"])
        end

        assert_empty stderr
        assert_includes stdout, "Installed asc-tooling skill"
        assert File.file?(File.join(codex_home, "skills", "asc-tooling", "SKILL.md"))
      end
    end
  end

  def test_init_with_claude_client_honors_claude_config_dir
    Dir.mktmpdir do |dir|
      claude_home = File.join(dir, ".claude")

      with_env("CLAUDE_CONFIG_DIR" => claude_home) do
        stdout, stderr = capture_io do
          assert_equal 0, ASCTooling::CLI.run(["init", "--client", "claude"])
        end

        assert_empty stderr
        assert_includes stdout, "Installed asc-tooling skill"
        assert File.file?(File.join(claude_home, "skills", "asc-tooling", "SKILL.md"))
      end
    end
  end

  def test_init_uninstalls_skill_from_custom_destination
    Dir.mktmpdir do |dir|
      assert_equal 0, ASCTooling::CLI.run(["init", "--dest", dir])

      stdout, stderr = capture_io do
        assert_equal 0, ASCTooling::CLI.run(["init", "--dest", dir, "--uninstall"])
      end

      assert_empty stderr
      assert_includes stdout, "Removed asc-tooling skill"
      refute File.exist?(File.join(dir, "asc-tooling"))
    end
  end
end
