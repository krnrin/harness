# CLAUDE.md — 高压线束精算与决策引擎

> 本文件是 Claude Code 的项目级约定，每次会话自动注入。

## 项目概要

这是一个面向汽车高压线束供应商的**成本精算与决策引擎**，支持 BOM → 报价 → 分摊回收 → 设变跟踪 → 预警 的全生命周期经营闭环。

技术栈：React 18 + Vite + TypeScript（前端）/ FastAPI + Python 3.11+（后端）/ SQLite（开发期数据库）

## 绝对不可违反的业务规则

1. **颗粒度到线束号/BOM 行** — 所有成本、报价、分摊必须精确到线束号和 BOM 行级别，绝不允许回退为项目平均值
2. **双引擎并行** — 内部实绩成本 与 客户报价 是两个独立口径，必须分层实现、并行展示，不得混为一谈
3. **分摊 ≠ 回收** — 分摊是成本口径（单根分摊金额），回收是执行进度（装车比×累计产量）。分摊表和回收记录必须分层实现
4. **按根分摊** — `unit_allocation = total_amount / (volume × install_ratio)`，不得使用其他分摊公式
5. **进度价 ≠ 加权混合价** — 进度价 = 协议价 vs 当前批量价差距追踪，不是历史价格的加权平均
6. **残余材料不计入当前产品成本** — 设变产生的残余材料进入残余材料池 → 呆滞提报流程，不继续计入当前产品成本
7. **场景 ≠ 版本** — 场景是经营语义（初始报价/定点/设变/年降），版本是时间线追溯。二者独立实现
8. **参数快照化** — 关键节点（BOM 冻结、报价发布、场景发布）必须保留费率、参数、BOM 快照，后续修改不覆盖历史结果

## 12 个功能模块

| 编号 | 模块 | 优先级 |
|------|------|--------|
| F01 | 项目管理与 Dashboard | P0 |
| F02 | 场景管理 | P0 |
| F03 | BOM 工作簿 | P0 |
| F04 | 客户报价工作台 | P0 |
| F05 | Simulation 与年降管理 | P1 |
| F06 | 分摊回收跟踪 | P0 |
| F07 | 设变与跟踪 | P1 |
| F08 | 预警系统与 Alerts | P1 |
| F09 | 管理决策舱 | P2 |
| F10 | 版本与发布治理 | P2 |
| F11 | 系统设置与参数治理 | P0 |
| F12 | Profile 与个人中心 | P2 |

建议开发顺序：F01 → F02 → F03 → F04 → F11 → F06 → F07 → F08 → F05 → F10 → F09 → F12

## 开发约定

### 目录结构

```
examples/harness-costing/
├── CLAUDE.md          # 本文件
├── app_spec.md        # 完整功能规格
├── frontend/          # React + Vite + TypeScript
│   ├── src/
│   │   ├── components/
│   │   ├── pages/
│   │   ├── hooks/
│   │   ├── services/   # API 调用
│   │   ├── types/
│   │   └── utils/
│   └── package.json
├── backend/           # FastAPI
│   ├── app/
│   │   ├── api/        # 路由
│   │   ├── models/     # SQLAlchemy 模型
│   │   ├── schemas/    # Pydantic 模型
│   │   ├── services/   # 业务逻辑
│   │   ├── core/       # 配置/安全
│   │   └── db/         # 数据库初始化
│   ├── tests/
│   └── requirements.txt
├── e2e/               # Playwright E2E 测试
│   ├── tests/
│   └── playwright.config.ts
└── progress.txt       # 跨 session 进度记录
```

### 代码风格

- **前端**：TypeScript strict mode，组件用函数式 + hooks，shadcn/ui 组件库
- **后端**：FastAPI + SQLAlchemy + Pydantic v2，async 优先
- **命名**：前端 camelCase，后端 snake_case，API 路由 kebab-case
- **错误处理**：所有 API 返回统一错误格式 `{"detail": string, "code": string}`
- **数据库**：SQLite 开发期，所有查询通过 SQLAlchemy ORM

### 测试策略

- 每个 API 端点必须有 pytest 测试
- 每个关键业务流程（主链路、分摊回收、设变）必须有 Playwright E2E 测试
- 计算规则必须有单元测试验证精度

### UI 设计

- **主题**：工业蓝图深色风格（深蓝/深灰底，白色文字，蓝色/绿色强调）
- **信息密度优先**：表格为主，卡片为辅
- **桌面优先**：最小宽度 1280px
- **组件库**：shadcn/ui + Tailwind CSS

## 阻塞处理协议

遇到以下情况，**停止执行并记录到 progress.txt**：

1. 业务规则不明确（如：某种费用是否需要按根分摊）
2. 数据模型冲突（如：发现关系图需要重构）
3. 依赖缺失（如：需要但未安装的库）
4. 测试持续失败超过 3 次
5. 任何可能破坏已有数据的操作

## 核心计算公式速查

```python
# BOM 行成本
unit_cost = quantity * unit_price

# 线束号成本
harness_cost = sum(bom_row.unit_cost for bom_row in harness.bom_rows)

# 单根分摊
unit_allocation = total_amount / (volume * install_ratio)

# 回收进度
recovery_progress = actual_recovered / planned_recovery * 100
actual_recovered = cumulative_volume * install_ratio * unit_allocation

# 利润差异
profit_gap = arrival_price - internal_cost_baseline

# 金属价格联动
metal_cost_impact = metal_weight * (current_metal_price - base_metal_price)

# 设变成本影响
cost_impact = sum(after.unit_cost) - sum(before.unit_cost)
residual_impact = sum(cancelled.unit_cost * remaining_quantity)

# 年降影响
cost_after = cost_before * (1 - drop_rate)
```

## 参考资料

- 完整 PRD：统一PRD资料包_落地版_完整版（Notion 工作区）
- 完整 Spec：`app_spec.md`（同目录）
- Harness 框架：`../../`（根目录）
