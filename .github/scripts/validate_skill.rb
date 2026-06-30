#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

root = File.expand_path("../..", __dir__)
skill_dir = File.join(root, "skills", "asc-tooling")
skill_path = File.join(skill_dir, "SKILL.md")
agent_path = File.join(skill_dir, "agents", "openai.yaml")
reference_path = File.join(skill_dir, "references", "security-boundaries.md")

abort "SKILL.md is missing" unless File.file?(skill_path)

text = File.read(skill_path)
abort "SKILL.md missing YAML frontmatter" unless text.start_with?("---\n")

frontmatter = text.split("---", 3)[1]
data = YAML.safe_load(frontmatter)

abort "SKILL.md name must be asc-tooling" unless data["name"] == "asc-tooling"
abort "SKILL.md description is required" if data["description"].to_s.strip.empty?
abort "agents/openai.yaml is required" unless File.file?(agent_path)
abort "security-boundaries.md is required" unless File.file?(reference_path)

YAML.load_file(agent_path)

puts "Skill is valid!"
