--- 
description: 根据 staged diff 生成 Conventional Commits 消息（中文 subject），显示给用户确认后执行 git commit
allowed-tools: ["Bash(git *)"]
---

# 任务：自动生成 git commit message 并确认提交

## 严格规则（必须 100% 遵守）
- 只处理 staged changes（使用 `git diff --cached` 获取 diff）。
- 生成的 commit message 必须严格遵循 Conventional Commits 规范。
- 类型仅限：feat, fix, docs, style, refactor, perf, test, chore。
- 范围（scope）：可选，优先使用 Swift 项目中的类名、文件名或模块名。
- 标题（subject）：必须用**中文**，不超过 80 字符，不以句号结尾。
- 正文（body）：可选，仅在 diff 复杂或有破坏性变更时使用，分点以 `- ` 开头。
- **绝对禁止**：输出任何解释性文字、Markdown 代码块、模糊描述（如“更新文件”）。
- **绝对禁止**：添加任何 AI 签名或 footer（如 Co-Authored-By Claude）。

## 执行步骤
1. 使用工具运行 `git diff --cached` 获取 staged diff。
2. 分析 diff，确定合适 type 和 scope。
3. 生成一条完整的 commit message（仅消息内容，无额外文字）。
4. 输出生成的 commit message，让用户查看。
5. 询问用户：这个 commit message 是否正确？请回复 y（确认提交）或 n（取消）。
6. 如果用户回复 y：执行 `git commit -m "<生成的完整消息>"`。
7. 如果用户回复 n：取消，不执行 commit，并回复“提交已取消”。
8. 如果 diff 为空：回复“没有 staged changes，无法生成消息”。

## 示例输出（仅消息部分）
feat(Auth): 实现 Apple ID 一键登录

fix(Home): 修复列表内存泄漏

refactor(Database): 迁移 CoreData 到 SwiftData

- 移除旧 CoreData 栈
- 添加 SwiftData 模型迁移逻辑