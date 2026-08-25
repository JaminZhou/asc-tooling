# asc-tooling

[![CI](https://github.com/JaminZhou/asc-tooling/actions/workflows/ci.yml/badge.svg)](https://github.com/JaminZhou/asc-tooling/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/JaminZhou/asc-tooling?sort=semver)](https://github.com/JaminZhou/asc-tooling/releases)
[![Ruby](https://img.shields.io/badge/ruby-3.1--3.3-red.svg)](.github/workflows/ci.yml)
[![Status](https://img.shields.io/badge/status-production%20local%20tooling-2563eb.svg)](CHANGELOG.md)
[![Agent Skill](https://img.shields.io/badge/Agent%20skill-Codex%20%2F%20Claude-111827.svg)](skills/asc-tooling/SKILL.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

语言：[English](README.md) | 中文

`asc_tooling` 是从产品仓库中抽出的 App Store Connect 自动化工具集，用统一 CLI、细分子命令和内置 Agent/Codex/Claude skill 覆盖审核、元数据、商店设置、截图、TestFlight、内购、版本、可售地区和 Sales and Trends 报表流程。

> 重要边界：本项目不是 Apple 官方工具。它使用调用方提供的 App Store Connect API 凭证，只通过显式 CLI 命令执行 App Store Connect 动作；仓库中不得保存 `.p8` 密钥、浏览器 Cookie、产品密钥或具体 app 的发布状态。

## 覆盖范围

- App Review 提交、撤回和手动发布
- App 版本创建
- 元数据检查和更新
- 商店设置检查与应用，包括分类、年龄分级、发布类型和审核信息
- 截图检查与上传
- TestFlight 分组、构建和测试员管理
- 内购准备度辅助
- App 可售地区检查和新增地区启用
- Sales and Trends 报表下载与销量汇总

## 命令

- `asc-tooling`
- `asc-review`
- `asc-metadata`
- `asc-beta`
- `asc-sales`
- `asc-screenshots`
- `asc-iap`
- `asc-version`
- `asc-availability`
- `asc-store-setup`

产品专属资产，例如截图渲染器、发布说明模板和 app-specific release state，应该留在具体产品仓库中。

潜在的后续 API 覆盖面记录在
[docs/api-gap-matrix.md](docs/api-gap-matrix.md)。它是探测 backlog，不代表本项目要封装完整 App Store Connect API。

## 环境变量

所有命令都需要：

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_PATH`

`asc-sales` 还需要：

- `ASC_VENDOR_NUMBER`

## 安装

当前项目通过 GitHub tag 分发，而不是 RubyGems。

在产品仓库的 `Gemfile` 中引用：

```ruby
gem "asc_tooling",
  git: "https://github.com/JaminZhou/asc-tooling.git",
  tag: "v0.10.0"
```

然后通过 Bundler 使用：

```bash
bundle install
bundle exec asc-tooling commands
bundle exec asc-tooling review status --bundle-id com.example.app
bundle exec asc-review status --bundle-id com.example.app
bundle exec asc-review release --bundle-id com.example.app --app-version 1.2.0
```

从本地 checkout 调试工具本身：

```bash
bundle install
./exe/asc-tooling commands
./exe/asc-review status --bundle-id com.example.app
```

## 统一 CLI 与 Skill

新自动化优先使用 `asc-tooling` 入口。它会委派到现有命令实现，同时给人和 agent 一个稳定的命令发现、执行和 skill 安装入口。
基础统一命令需要 `v0.9.0` 或更新版本。`asc-review attach-build` 和
`asc-review status --items` 当前仅在 `main` 分支提供，并将在下一个 tag
版本发布。

```bash
bundle exec asc-tooling commands
bundle exec asc-tooling --version
bundle exec asc-tooling review status --bundle-id com.example.app
bundle exec asc-tooling review status --bundle-id com.example.app --app-version 1.2.0 --items
bundle exec asc-tooling review attach-build --bundle-id com.example.app --app-version 1.2.0 --build-number 2026082501 --dry-run
bundle exec asc-tooling version create --bundle-id com.example.app --version 1.2.0 --platform ios --dry-run
bundle exec asc-tooling availability status --bundle-id com.example.app
```

安装内置 skill：

```bash
bundle exec asc-tooling init --client codex --force    # $CODEX_HOME/skills，或 ~/.codex/skills
bundle exec asc-tooling init --client agents --force   # ~/.agents/skills
bundle exec asc-tooling init --client claude --force   # $CLAUDE_CONFIG_DIR/skills，或 ~/.claude/skills
bundle exec asc-tooling init --print
```

`--client codex` 使用 Codex 自身的 `CODEX_HOME` 约定；`--client agents`
使用兼容 Agent Skills 的开放用户目录；`--client claude` 使用 Claude Code
的 `CLAUDE_CONFIG_DIR` 约定，未设置时回落到 `~/.claude`。

旧的可执行命令仍然保留，方便现有脚本继续使用：

```bash
./exe/asc-review status --bundle-id com.example.app
./exe/asc-review status --bundle-id com.example.app --app-version 1.2.0 --items
./exe/asc-review attach-build --bundle-id com.example.app --app-version 1.2.0 --build-number 2026082501 --dry-run
./exe/asc-review withdraw --bundle-id com.example.app --app-version 1.2.0 --dry-run
./exe/asc-metadata status --bundle-id com.example.app --locale en-US
./exe/asc-beta status --bundle-id com.example.app
./exe/asc-sales units --bundle-id com.example.app --vendor-number 12345678 --report-date 2026-04-10
./exe/asc-screenshots status --bundle-id com.example.app --locale en-US --display-type APP_DESKTOP
./exe/asc-iap status --bundle-id com.example.app
./exe/asc-version create --bundle-id com.example.app --version 1.2.0 --platform ios --dry-run
./exe/asc-availability status --bundle-id com.example.app
./exe/asc-store-setup status --bundle-id com.example.app --app-version 1.0.0 --platform ios
```

`asc-metadata status` 和 `asc-screenshots status` 可以通过 `--app-version`
读取指定的可编辑或已上架版本；对应的写入命令 `asc-metadata apply` 和
`asc-screenshots upload` 仍然只允许操作可编辑的 App Store 版本。

`asc-review attach-build` 会把一个同时满足 `VALID` 和
`APP_STORE_ELIGIBLE` 的构建显式关联到可编辑版本，并在写入后回读验证。
`asc-review submit --build-number ...` 仍保留“关联指定构建并立即提审”的
单命令路径。给 `asc-review status` 增加 `--items` 可以回读每个 review
submission 中的 App 版本和 IAP 版本项目。

`asc-iap status` 会标记首个 IAP 是否仍需要 App Store Connect 网页联合
提交；`asc-iap submit` 会在任何提交写入前执行该预检。首个 IAP 仍需在
网页中随 App 版本提交，之后处于 `READY_TO_SUBMIT` 的 IAP 可以直接使用
CLI 提交。

更完整的使用说明和发布流程见 [docs/release-and-usage.md](docs/release-and-usage.md)。

## 支持边界

正式支持的是基于 JWT 的 CLI 工作流：

- `asc-tooling`
- `asc-review`
- `asc-metadata`
- `asc-beta`
- `asc-sales`
- `asc-screenshots`
- `asc-iap`
- `asc-version`
- `asc-availability`
- `asc-store-setup`

`experimental/` 下的 Resolution Center 辅助工具只用于本地浏览器会话调试，不属于稳定公共接口，不应在 CI、共享发布脚本或产品自动化中使用。任何导出的 Cookie JSON 都必须留在仓库外，并在使用后立即删除。

## 贡献

贡献流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按 [SECURITY.md](SECURITY.md) 处理，不要在公开 issue 中粘贴凭证、Cookie、`.p8` 密钥或产品敏感信息。
发布历史见 [CHANGELOG.md](CHANGELOG.md)。
