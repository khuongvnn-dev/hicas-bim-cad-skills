# Hicas Skills

Marketplace plugin Claude Code cho đội add-in **Revit / AutoCAD** (C#, .NET Framework 4.8).
Cấu trúc theo chuẩn [anthropics/skills](https://github.com/anthropics/skills) và
[Agent Skills spec](https://agentskills.io/specification).

## Plugin `hicas-bimcad`

Quy trình từ thu thập yêu cầu tới hiện thực hóa:

```
Redmine ──► redmine-us-writer-verified ──► ticket .md (có Hợp đồng kiểm thử)
                                               │
        nhiều ticket ──► addin-batch ──► nhóm theo US ──► 1 worktree / US
                                               │
                         addin-story ◄─────────┘  (readiness → design → tasks →
                                                    test-first → thẩm định độc lập → bàn giao QA)
```

| Skill | Làm gì | Gọi |
|---|---|---|
| [`redmine-us-writer-verified`](skills/redmine-us-writer-verified/SKILL.md) | Đọc ticket qua MCP Redmine, viết `.md` cho dev agent kèm ma trận R→AC, oracle có nguồn, bằng chứng, người xác nhận | Tự kích hoạt khi nhắc ticket Redmine, hoặc `/hicas-bimcad:redmine-us-writer-verified <ID>` |
| [`addin-batch`](skills/addin-batch/SKILL.md) | Điều phối nhiều ticket: gom Task/Implement/Bug theo US, lập kế hoạch, kiểm xung đột, 1 lượt duyệt, chạy mỗi US trong git worktree riêng, hàng đợi test level B và MR | `/hicas-bimcad:addin-batch plan` |
| [`addin-story`](skills/addin-story/SKILL.md) | Team-lead playbook cho 1 ticket/US: test-first, maker ≠ checker, evaluator độc lập | `/hicas-bimcad:addin-story <file.md> [auto\|resume]` |

Subagent đi kèm (`hicas-bimcad:<tên>`): `addin-scout`, `addin-implementer`, `addin-helper-writer`,
`addin-wpf-ui`, `addin-reviewer`, `explorer`, `test-writer`, `architect-reviewer`, `evaluator`.

MCP: plugin **không tự cài** server Redmine; cần một MCP server tên `redmine` (`mcp-redmine`). Hiện lấy từ plugin `harness-redmine`. Khi bỏ plugin đó, dùng cấu hình mẫu [`extras/redmine.mcp.json`](extras/redmine.mcp.json) (chỉ đọc mặc định, đọc biến môi trường).

## Cài đặt

1. Cần: Claude Code, `uv` (cho `uvx`), Node.js (lint ticket), Git, MSBuild/Visual Studio 2022 (build add-in).
2. (Chỉ khi không dùng `harness-redmine`) thêm server từ `extras/redmine.mcp.json` và đặt biến môi trường người dùng (Windows):
   ```powershell
   setx REDMINE_URL "https://redmine.<cong-ty>.vn"
   setx REDMINE_API_KEY "<API key cá nhân: Redmine → My account → API access key>"
   ```
   Không commit API key. `REDMINE_READ_ONLY` mặc định `1`; đặt `0` chỉ khi thật sự cần ghi lên Redmine.
3. Trong Claude Code:
   ```
   /plugin marketplace add D:\hicas-skills
   /plugin install hicas-bimcad@hicas-skills
   ```
   (hoặc trỏ tới repo git nội bộ khi đã đẩy lên).

## Dữ liệu trong repo dự án

Các skill ghi file quy trình vào thư mục `.harness/` của repo dự án (phải nằm trong `.git/info/exclude`,
không commit): `tickets/`, `features/<ID>/`, `batch/`, `addin-story.json`, `addin-batch.json`
(mẫu: [`skills/addin-batch/assets/addin-batch.example.json`](skills/addin-batch/assets/addin-batch.example.json)),
`project-map.md`. Tên thư mục giữ nguyên để tương thích dữ liệu cũ; không cần plugin nào khác.

## Thêm / sửa skill

Theo [`spec/agent-skills-spec.md`](spec/agent-skills-spec.md), bắt đầu từ [`template/SKILL.md`](template/SKILL.md),
thêm đường dẫn vào `skills` của plugin trong [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json),
rồi chạy `claude plugin validate .`.
