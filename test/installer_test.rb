require "tmpdir"

require "test_helper"

class InstallerTest < Minitest::Test
  def test_print_skill_includes_frontmatter
    content = ASCTooling::SkillInstaller.print_skill

    assert_includes content, "name: asc-tooling"
    assert_includes content, "App Store Connect"
  end

  def test_install_skill_copies_bundled_skill_to_destination
    Dir.mktmpdir do |dir|
      target = ASCTooling::SkillInstaller.install_skill(dir)

      assert_equal File.join(dir, "asc-tooling"), target.to_s
      assert File.file?(File.join(target, "SKILL.md"))
      assert File.file?(File.join(target, "references", "security-boundaries.md"))
    end
  end

  def test_install_skill_refuses_existing_without_force
    Dir.mktmpdir do |dir|
      target = File.join(dir, "asc-tooling")
      FileUtils.mkdir_p(target)
      File.write(File.join(target, "SKILL.md"), "local edits")

      assert_raises(Errno::EEXIST) { ASCTooling::SkillInstaller.install_skill(dir) }
      assert_equal "local edits", File.read(File.join(target, "SKILL.md"))
    end
  end

  def test_install_skill_force_replaces_existing_skill
    Dir.mktmpdir do |dir|
      target = File.join(dir, "asc-tooling")
      FileUtils.mkdir_p(target)
      File.write(File.join(target, "SKILL.md"), "local edits")

      ASCTooling::SkillInstaller.install_skill(dir, force: true)

      assert_includes File.read(File.join(target, "SKILL.md")), "name: asc-tooling"
    end
  end

  def test_uninstall_skill_removes_installed_skill
    Dir.mktmpdir do |dir|
      target = ASCTooling::SkillInstaller.install_skill(dir)

      removed = ASCTooling::SkillInstaller.uninstall_skill(dir)

      assert_equal target, removed
      refute File.exist?(target)
    end
  end

  def test_resolve_client_destinations_supports_agents_codex_and_claude
    Dir.mktmpdir do |dir|
      home = Pathname.new(dir)

      assert_equal [home.join(".agents", "skills")], ASCTooling::SkillInstaller.resolve_client_destinations("agents", home: home)
      assert_equal [home.join(".agents", "skills")], ASCTooling::SkillInstaller.resolve_client_destinations("codex", home: home)
      assert_equal [home.join(".claude", "skills")], ASCTooling::SkillInstaller.resolve_client_destinations("claude", home: home)
    end
  end
end
