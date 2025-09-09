说明：以下内容默认 Go 1.23.x / Node 20 / Wails v2 / Vitest+Playwright，并采用你建议的覆盖率梯度（单元≥85%，集成≥75%，E2E≥60%，接口包目标 100%）。如与现仓库目录有出入，改一下路径即可。

⸻

TDD_GUIDE.md

# TDD 指南（Go/Wails/TypeScript）

> 目标：以 **Research → Red → Green → Refactor** 驱动开发；先研究最佳实践，产出测试与黄金样本，再实现最小绿条；在 **CI** 中强制执行覆盖率与安全/合规检查。

## 0. TDD 工作流程（增强版）

### 0.1 Research Phase（新增 - 任务开始时必须执行）
当任务状态设置为 `in-progress` 时，**必须先进行研究阶段**：

1. **知识收集（并行执行）**：
   - 使用 **Context7** 获取官方文档和最佳实践
   - 使用 **DeepWiki** 深入理解技术概念和实现细节
   - 使用 **Exa Deep Research** 搜索最新的行业实践和案例

2. **研究内容**：
   - 相关技术的最佳实践和设计模式
   - 性能优化技巧和陷阱
   - 安全考虑和常见漏洞
   - 测试策略和边界案例
   - 类似系统的架构决策

3. **研究输出**：
   - 记录关键发现到任务笔记：`task-master update-subtask --id=<id> --prompt="research findings"`
   - 识别潜在风险和技术债务
   - 制定基于研究的实现策略

### 0.2 Standard TDD Flow
**Research → Red → Green → Refactor → Validate**

```bash
# 1. RESEARCH (新增必须步骤)
task-master set-status --id=X.Y --status=in-progress
# 自动触发研究工具：Context7 + DeepWiki + Exa
# 记录研究发现到任务

# 2. RED - 写失败的测试
touch internal/module/feature_test.go
# 编写全面的测试用例

# 3. GREEN - 最小实现
touch internal/module/feature.go
# 实现到测试通过

# 4. REFACTOR - 优化
# 基于研究发现进行优化

# 5. VALIDATE - 验证
make test-go cover-check-go
./scripts/tdd-guard.sh --wait
```

## 0.3 前置规范（与接口一致）
- **命名**：统一使用 `HooksConfig`；公共 API 遵循一致的大小写与前缀。
- **上下文**：所有可能阻塞的 I/O 或远端调用统一接收 `ctx context.Context`；测试需覆盖超时/取消。
- **错误模型**：统一使用 `errors.Is/As` 与哨兵错误（如 `ErrNotFound/ErrConflict/ErrInvalidHook/...`），必要时使用 `AppError{Code, Message, Cause}`。
- **ID/时间**：ID 为 UUID v4 字符串；时间为 `time.Time`（UTC 存储，展示本地化）。
- **路径/XDG**：默认遵循各平台数据目录，支持“便携模式”与可配置覆盖。

## 1. 测试金字塔与工具
- **单元测试（Go/TS）**：表驱动测试为主；Go 使用 `testing` + `rapid`（或 `testing/quick`）做性质测试；TS 使用 `Vitest`。
- **集成测试**：组件边界（如 Storage ↔ Checkpoint ↔ Filesystem / MCP Provider ↔ RPC）；优先用 fake / mock + 临时目录 + `testcontainers-go`（如需外部 DB）。
- **端到端（E2E）**：Wails 应用主要路径（启动、会话创建、执行指令、流式输出、保存/恢复检查点、退出）；前端用 `Playwright`。
- **覆盖率门槛**：  
  - 单元 ≥ **85%**（核心/接口包**100%**优先）、集成 ≥ **75%**、E2E ≥ **60%**  
  - 任何新 PR 若核心包覆盖率下降，CI 直接失败。

## 2. 目录与约定

/docs
/spec
acceptance/.feature        # 若采用 Gherkin
golden/.json               # 请求/响应黄金样本
/desktop                      # Go (Wails)
internal/…                # 非导出实现
pkg/…                     # 导出包（接口/领域模型尽量在此，便于复用与测试）
cmd/app/…                 # 程序入口
/frontend                     # TypeScript (Vite/Vitest/Playwright)
src/
tests/
/.mocks                       # 生成的接口 mock（可选）

## 3. 表驱动与统一测试壳（Go）
```go
type TestCase[I any, O any] struct {
  Name     string
  Input    I
  Want     O
  WantErr  error
  Setup    func(t *testing.T)
  Teardown func(t *testing.T)
}

func RunTable[I any, O any](t *testing.T, cases []TestCase[I, O], fn func(ctx context.Context, in I) (O, error)) {
  t.Helper()
  for _, tc := range cases {
    t.Run(tc.Name, func(t *testing.T) {
      if tc.Setup != nil { tc.Setup(t) }
      t.Cleanup(func() { if tc.Teardown != nil { tc.Teardown(t) } })
      ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
      defer cancel()

      got, err := fn(ctx, tc.Input)
      if tc.WantErr != nil {
        if !errors.Is(err, tc.WantErr) { t.Fatalf("want err %v, got %v", tc.WantErr, err) }
        return
      }
      if err != nil { t.Fatalf("unexpected err: %v", err) }
      if diff := cmp.Diff(tc.Want, got, cmpopts.EquateEmpty()); diff != "" {
        t.Fatalf("(-want +got):\n%s", diff)
      }
    })
  }
}

4. 关键子系统的“可观测行为”与测试要点

4.1 Agent / Session / Core
	•	Start/Stop/Wait：
	•	红：Start 在无效可执行路径返回 ErrNotFound；
	•	绿：在有效配置下 Start 返回会话 ID，GetStatus→Running，Wait 返回 0 退出码；
	•	流式输出：StreamOutput 事件按时间序单调递增；无重复/错序（在测试中断言 seq）。
	•	历史与幂等：重复调用 GetSessionHistory 应稳定；空历史返回空 slice 而非 nil。

4.2 Checkpoint
	•	创建/恢复：
	•	创建后生成内容哈希（含元数据）；立即恢复应得到哈希等价的状态。
	•	DAG 无环：对任意新增边，若成环应返回 ErrConflict。
	•	修剪策略：保留 N 条最近 + 标记的关键点；测试验证修剪不破坏“最后一次成功点”。
	•	性质测试（示例）：
	•	幂等：对同一状态重复创建检查点→哈希不变。
	•	可逆：恢复→再创建→哈希一致。
	•	拓扑：随机生成边集合，检测是否有环。

4.3 Storage
	•	列表/分页：ListTables 字典序；ReadTable 稳定排序 + 幂等；边界（limit=0/负数/超大）与 offset 溢出。
	•	事务/超时：长查询超时触发 context.DeadlineExceeded；取消触发 context.Canceled。
	•	备份/恢复：恢复到空目录或覆盖场景需确认策略并测试。

4.4 Hooks（安全）
	•	命令白名单：不在白名单内→ErrPermissionDenied；参数包含 .. 或绝对路径跳转→拒绝。
	•	工作目录与环境：注入/清理可逆；失败保证回滚。

4.5 MCP Provider
	•	连通性：AddServer 后 Ping 成功；无效地址→ErrNotFound/ErrConnection。
	•	配置：项目级覆盖全局级；测试断言优先级。

4.6 Proxy
	•	注入/清理：前后环境 diff 为 0（可逆）；无代理时操作幂等。

4.7 Analytics / Privacy
	•	匿名化：事件不含 PII；若含保留字段（如文件路径），需哈希或裁剪。
	•	采样：采样率在 [0,1]；0/1 边界测试。

4.8 Usage / Cost
	•	聚合：多会话并发上报，最终统计应与顺序处理等价（结合性质测试）。
	•	时间窗：UTC 窗口切分；跨日/跨月边界。

5. 黄金样本（/spec/golden）
	•	API/序列化约定放入 *.json/ndjson；测试用 testdata/ 加载。
	•	对流式输出，使用 ndjson + 递增 seq 与 ts 字段。

6. Gherkin（可选）

Feature: Restore last successful checkpoint
  Scenario: restore after crash
    Given a running session with recent successful checkpoint
    When the process crashes
    And I issue a restore command
    Then the session state equals the checkpoint hash

7. Mock 与生成
	•	//go:generate mockgen -source=desktop/pkg/xyz/interfaces.go -destination=.mocks/xyz_mock.go -package=mocks
	•	将接口分层至 pkg/，便于 mock 与复用。

8. 失败信息与命名
	•	Test<被测对象>_<场景>_<预期>，失败信息包含 期望/实际/上下文。
	•	对错误断言统一使用 errors.Is/As，避免比对字符串。

9. PR 最小步与检查清单
	•	勾子：先测后码；测试与实现分 PR 或分 commit；每个 PR 说明“覆盖用例 ID”。
	•	CI 必过：Go/TS 测试+覆盖率、lint、gosec、OSV、REUSE。

10. 本地运行

make deps        # go, node, playwright browsers
make test-go     # go vet + go test -race -cover
make test-ts     # vitest
make test-e2e    # playwright
make lint-go     # golangci-lint


⸻

和TDD_GUIDE.md（red_team项目测试指南，TDD先行相关联的文档：
	•	.github/workflows/ci.yml（持续集成）
	•	.github/workflows/release.yml（跨平台构建与可选签名/公证占位）
	•	AGENT_GUIDE.md（代理系统提示/护栏，干净室策略）
	•	PULL_REQUEST_TEMPLATE.md
	•	.pre-commit-config.yaml
	•	Makefile
	•	LICENSES/MIT.txt
	•	COPYRIGHT
	•	templates/SPDX-Header.go.txt
	•	templates/SPDX-Header.ts.txt
	•	REUSE-README.md

⸻

内容要点

1) PR 模板（PULL_REQUEST_TEMPLATE.md）
	•	强制 TDD 声明（先测后码）、覆盖率门槛（Unit≥85% / Integration≥75% / E2E≥60%）、安全与隐私、合规来源（SPDX+REUSE）、本地验证清单。
	•	便于审阅人与 CI 一致对齐，减少来回。

2) pre-commit 钩子（.pre-commit-config.yaml）
	•	通用基础：冲突检查、行尾、YAML、超大文件保护。
	•	本地 hooks（无需额外第三方仓库）：
	•	go fmt 校验
	•	golangci-lint / staticcheck（若已安装则运行，否则跳过）
	•	reuse lint（若已安装则运行）
	•	前端 tsc、eslint（检测到 frontend/ 时启用）
	•	轻量 Go 单测 -short（不阻塞提交的快速回归）

安装启用：

pipx install pre-commit  # 或 pip install pre-commit
pre-commit install



3) 最小 Makefile
	•	make deps：Go mod + 前端 npm + Playwright 浏览器安装
	•	make test-go / make cover-check-go：-race + 覆盖率摘要与阈值检查（默认 85%）
	•	make test-ts：Vitest + 覆盖率阈值（默认 70%）
	•	make test-e2e：Playwright（自动回退到 npm run e2e）
	•	make lint：汇总 fmt/Go/TS Lint
	•	make build：Wails 最小构建（sanity）
	•	make reuse-lint：本地 REUSE 检查（未安装工具时不失败）

覆盖率阈值可通过环境变量覆盖：
COVER_MIN_GO=90 make cover-check-go、COVER_MIN_TS=80 make test-ts

4) REUSE 基础结构
	•	LICENSES/MIT.txt：MIT 正文
	•	COPYRIGHT：默认版权标注（可替换为你的组织名）
	•	templates/SPDX-Header.*.txt：Go/TS 文件头模板
	•	REUSE-README.md：快速使用说明与示例

新文件头示例（Go）：

// SPDX-FileCopyrightText: 2025 Yongbing Tang and contributors
// SPDX-License-Identifier: MIT



⸻

建议的落地步骤
	1.	把以上文件放入仓库对应位置（或直接下载上述链接后拷贝）。
	2.	（可选）在 README 中补一行：
本仓库采用 REUSE 规范，详见 REUSE-README.md。
	3.	本地启用 pre-commit：pre-commit install。
	4.	试跑：

make deps
make test-go && make cover-check-go
make test-ts
make lint
make reuse-lint

——————

好的，已为你把两项都生成好了，并打包成可直接落地的文件：

🔧 新增文件（可直接下载/拷贝进仓库）
	•	PULL_REQUEST_TEMPLATE.md
	•	.pre-commit-config.yaml
	•	Makefile
	•	LICENSES/MIT.txt
	•	COPYRIGHT
	•	templates/SPDX-Header.go.txt
	•	templates/SPDX-Header.ts.txt
	•	REUSE-README.md

⸻

内容要点

1) PR 模板（PULL_REQUEST_TEMPLATE.md）
	•	强制 TDD 声明（先测后码）、覆盖率门槛（Unit≥85% / Integration≥75% / E2E≥60%）、安全与隐私、合规来源（SPDX+REUSE）、本地验证清单。
	•	便于审阅人与 CI 一致对齐，减少来回。

2) pre-commit 钩子（.pre-commit-config.yaml）
	•	通用基础：冲突检查、行尾、YAML、超大文件保护。
	•	本地 hooks（无需额外第三方仓库）：
	•	go fmt 校验
	•	golangci-lint / staticcheck（若已安装则运行，否则跳过）
	•	reuse lint（若已安装则运行）
	•	前端 tsc、eslint（检测到 frontend/ 时启用）
	•	轻量 Go 单测 -short（不阻塞提交的快速回归）

安装启用：

pipx install pre-commit  # 或 pip install pre-commit
pre-commit install



3) 最小 Makefile
	•	make deps：Go mod + 前端 npm + Playwright 浏览器安装
	•	make test-go / make cover-check-go：-race + 覆盖率摘要与阈值检查（默认 85%）
	•	make test-ts：Vitest + 覆盖率阈值（默认 70%）
	•	make test-e2e：Playwright（自动回退到 npm run e2e）
	•	make lint：汇总 fmt/Go/TS Lint
	•	make build：Wails 最小构建（sanity）
	•	make reuse-lint：本地 REUSE 检查（未安装工具时不失败）

覆盖率阈值可通过环境变量覆盖：
COVER_MIN_GO=90 make cover-check-go、COVER_MIN_TS=80 make test-ts

4) REUSE 基础结构
	•	LICENSES/MIT.txt：MIT 正文
	•	COPYRIGHT：默认版权标注（可替换为你的组织名）
	•	templates/SPDX-Header.*.txt：Go/TS 文件头模板
	•	REUSE-README.md：快速使用说明与示例

新文件头示例（Go）：

// SPDX-FileCopyrightText: 2025 Yongbing Tang and contributors
// SPDX-License-Identifier: MIT



⸻

建议的落地步骤
	1.	把以上文件放入仓库对应位置（或直接下载上述链接后拷贝）。
	2.	（可选）在 README 中补一行：
本仓库采用 REUSE 规范，详见 REUSE-README.md。
	3.	本地启用 pre-commit：pre-commit install。
	4.	试跑：

make deps
make test-go && make cover-check-go
make test-ts
make lint
make reuse-lint


需要把这些改动合并进前面给你的 ci.yml / release.yml 说明（在“本地复现”与“合规检查”章节补充命令），或者生成 /.github/ISSUE_TEMPLATE/ 