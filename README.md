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
| [`b-auto-run`](skills/b-auto-run/SKILL.md) | Chạy tự động các case cấp B trong Revit/AutoCAD thật bằng HicasTest, trên mọi năm deploy đã cài; gắn báo cáo máy vào `qa-handover.md`, ghi ledger. Không bao giờ ghi Pass | Từ addin-story Phase 5.4 / addin-batch khi `automationBridge` = `hicas-test`, hoặc `/hicas-bimcad:b-auto-run` |
| [`qa-test-session`](skills/qa-test-session/SKILL.md) | QA mô tả bằng lời, Claude điều khiển Revit/AutoCAD từng bước, chụp ảnh mỗi bước, xuất báo cáo | Tự kích hoạt khi QA nhờ test một tính năng, hoặc `/hicas-bimcad:qa-test-session` |
| [`b-desktop-test`](skills/b-desktop-test/SKILL.md) | Sau khi story code + unit test xong, Claude **tự lấy quyền điều khiển máy** (computer-use) chạy các kịch bản test tay B / Critical trong `qa-handover.md` trên bản copy fixture, chụp ảnh từng bước, ghi bằng chứng. Chỉ điều khiển Revit/AutoCAD, dừng ở màn đăng nhập/license/hộp thoại lạ, không bao giờ ghi Pass | Từ addin-story Phase 6 / addin-batch `finish` khi `desktopTest` = `computer-use`, hoặc `/hicas-bimcad:b-desktop-test` |

Subagent đi kèm (`hicas-bimcad:<tên>`): `addin-scout`, `addin-implementer`, `addin-helper-writer`,
`addin-wpf-ui`, `addin-reviewer`, `explorer`, `test-writer`, `architect-reviewer`, `evaluator`.

MCP: plugin **không tự cài** server Redmine; cần một MCP server tên `redmine` (`mcp-redmine`). Hiện lấy từ plugin `harness-redmine`. Khi bỏ plugin đó, dùng cấu hình mẫu [`extras/redmine.mcp.json`](extras/redmine.mcp.json) (chỉ đọc mặc định, đọc biến môi trường).

MCP cho test tự động (tuỳ chọn): `b-auto-run` và `qa-test-session` cần tool
[HicasTest](https://github.com/longpl-1902/hicas-bimcad-test-tool) cài trên máy có Revit/AutoCAD, với MCP server tên
`hicas-test`. Cách nhanh nhất: chạy `install.ps1 -RegisterMcp` trong gói HicasTest; hoặc dùng mẫu
[`extras/hicas-test.mcp.json`](extras/hicas-test.mcp.json). Trong repo add-in, đặt `automationBridge: "hicas-test"`,
`testBuilds`, `testFixtures` trong `.harness/addin-story.json`. Kết quả của tool chỉ là bằng chứng máy — case cấp B
vẫn cần người xác nhận.

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

## Nhánh và bảo vệ nhánh (addin-batch)

Mỗi đợt làm việc có **một nhánh tích hợp** riêng của người dùng, agent chỉ ghi trên nhánh của đợt. Tiền tố là
`lanes.branchUser`, lấy từ `git config user.name` của **từng máy** ở lần chạy đầu (bỏ dấu, chữ thường — vd
`Lê Phi Long` → `lephilong`) và hỏi xác nhận một lần; `longpl` dưới đây chỉ là ví dụ:

```
DEV ──●──────────────────────────────────────── (agent không ghi)
       \
        longpl_20261004 ──●───M(1234)───M(1240)───M(DEV)──► người tự push + mở MR vào DEV
                           \  /         /
                 longpl_20261004_lane1234  longpl_20261004_lane1240   (mỗi US một worktree)
```

- Agent tự tạo nhánh/worktree, commit trên nhánh lane, merge `--no-ff` lane vào nhánh tích hợp (mỗi US một merge
  commit — gỡ một US bằng `git revert -m 1 <merge>`), cuối đợt merge DEV mới nhất **vào** nhánh tích hợp và soạn
  `.harness/batch/mr-<nhánh>.md`.
- **Không push** (`lanes.push: false`); người tự push và mở MR. Redmine vẫn chỉ đọc, comment là bản nháp.
- Hook [`hooks/guard-git.mjs`](hooks/guard-git.mjs) (cài cùng plugin, cần Node.js) chặn mọi lệnh git ghi vào
  `lanes.protectedBranches` (mặc định `DEV, UAT, release*, main, master`) và mọi `git push`. Hook **chỉ có hiệu lực**
  trong repo có `.harness/addin-batch.json`; repo khác không bị ảnh hưởng. Nên bật thêm branch protection trên server Git.

## Dữ liệu trong repo dự án

Các skill ghi file quy trình vào thư mục `.harness/` của repo dự án (phải nằm trong `.git/info/exclude`,
không commit): `tickets/`, `features/<ID>/`, `batch/`, `addin-story.json`, `addin-batch.json`
(mẫu: [`skills/addin-batch/assets/addin-batch.example.json`](skills/addin-batch/assets/addin-batch.example.json)),
`project-map.md`. Tên thư mục giữ nguyên để tương thích dữ liệu cũ; không cần plugin nào khác.

## Thêm / sửa skill

Theo [`spec/agent-skills-spec.md`](spec/agent-skills-spec.md), bắt đầu từ [`template/SKILL.md`](template/SKILL.md),
thêm đường dẫn vào `skills` của plugin trong [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json),
rồi chạy `claude plugin validate .`.
