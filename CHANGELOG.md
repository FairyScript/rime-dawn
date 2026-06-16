# Changelog

## [1.0.0-alpha.1] - 2026-06-16

### ⚠ BREAKING CHANGES

- 移除 `/` 命令切换拼音方案（改为方案选单切换）
- 移除辅助码相关功能（直接辅助码、间接辅助码、辅助码提示）
- 反查前缀从 `` ` `` 改为 `~`
- 造词引导符从 `` `` `` 改为 `@`
- 英文造词触发符从 `\` 改为 `$$`

### Features

- 添加拼音方案选单切换（Ctrl+` 或 F4）
- `Ctrl+\` 进入造词模式
- `\` 直接输入顿号
- `$` 加入编码字符集，支持英文造词

### Bug Fixes

- 修复过时的注释和文档

### Docs

- 更新 README：添加项目宗旨、更新功能列表
- 更新 CHANGELOG：记录本项目独立的更新历史

## [2026-06-14]

### Features

- `\` 输入顿号

### Bug Fixes

- 移除 `/` 响应输入法内容
- 解除 `/` 按键占用

### Init

- Fork 自 [Fidelxyz/rime-wanxiang-slim](https://github.com/Fidelxyz/rime-wanxiang-slim) v0.6.0-beta.2
