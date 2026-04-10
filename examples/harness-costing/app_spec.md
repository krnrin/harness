# 高压线束精算与决策引擎 — App Spec (Phase 1)

## 1. 产品概述

**一句话定义**: 面向汽车高压线束供应商内部团队的成本精算与决策引擎，支持从 BOM 到报价、分摊回收、设变跟踪的全生命周期经营闭环。

**目标用户**: 成本工程师、销售报价人员、财务管理层

**核心价值**:
- 双引擎：内部实绩成本 + 客户报价口径并行，差异可视
- 颗粒度：精算到线束号 / BOM 行，杜绝套级笼统核算
- 闭环：一次性费用从分摊→回收→调价全链路可追踪
- 场景化：初始报价 / 定点 / 设变 / 年降多场景并行管理

**Phase 1 范围**: 本 spec 仅覆盖主链路（P0），即让系统从"能看页面"进入"有经营闭环"所需的最小功能集。

---

## 2. 技术栈

| 层 | 技术 |
|---|---|
| Frontend | React 18 + Vite + TypeScript |
| UI | Tailwind CSS + shadcn/ui（工业蓝图深色风格） |
| Backend | FastAPI (Python 3.11+) |
| Database | SQLite (开发期) → PostgreSQL (生产) |
| Testing | Playwright (E2E) + pytest (API) |
| MCP | Playwright MCP (浏览器自动化测试) |

---

## 3. 页面结构与路由

```
/                           → 项目列表（入口）
/project/:id                → 项目 Dashboard（经营总览 + 模块导航）
/project/:id/scenarios      → 场景列表
/project/:id/scenario/:sid  → 场景详情（关联 BOM/报价/分摊）
/project/:id/bom            → BOM 工作簿
/project/:id/quote          → 客户报价工作台
/project/:id/allocation     → 分摊回收跟踪
/project/:id/changes        → 设变管理
/project/:id/tracking       → 跟踪管理
/settings                   → 系统设置（费率/金属价格/阈值）
```

---

## 4. 数据模型

### 4.1 项目 (Project)

```
Project {
  id: UUID (PK)
  code: string (unique)
  name: string
  customer_name: string
  vehicle_model: string
  status: enum [draft, active, frozen, archived]
  harness_count: int
  created_at: datetime
  updated_at: datetime
}
```

### 4.2 场景 (Scenario)

```
Scenario {
  id: UUID (PK)
  project_id: UUID (FK → Project)
  type: enum [initial_quote, fixed_point, change, annual_drop]
  name: string
  status: enum [draft, calculating, frozen, released, archived]
  lifecycle_years: int
  volume: int                -- 生命周期总产量
  install_ratio: decimal     -- 装车比
  rate_snapshot: JSON        -- 费率快照
  created_at: datetime
  updated_at: datetime
}
```

### 4.3 线束号 (Harness)

```
Harness {
  id: UUID (PK)
  project_id: UUID (FK → Project)
  scenario_id: UUID (FK → Scenario)
  part_number: string
  name: string
  status: enum [active, changed, cancelled]
  created_at: datetime
}
```

### 4.4 BOM 行 (BomRow)

```
BomRow {
  id: UUID (PK)
  project_id: UUID (FK → Project)
  scenario_id: UUID (FK → Scenario)
  harness_id: UUID (FK → Harness)
  part_number: string        -- 料号
  part_name: string
  category: string           -- 分类（导体/端子/护套/辅材等）
  quantity: decimal
  unit_price: decimal
  price_source: string       -- 价格来源
  material_type: string      -- 材料属性
  metal_type: enum [copper, aluminum, none]
  unit_cost: decimal         -- quantity × unit_price
  version_ref: string
  created_at: datetime
  updated_at: datetime
}
```

### 4.5 报价快照 (QuoteSnapshot)

```
QuoteSnapshot {
  id: UUID (PK)
  project_id: UUID (FK → Project)
  scenario_id: UUID (FK → Scenario)
  harness_id: UUID (FK → Harness)
  quote_params: JSON          -- 客户口径参数快照
  quote_result: JSON          -- 客户口径结果
  internal_cost_baseline: decimal
  profit_gap: decimal         -- 报价 - 内部成本
  ex_works_price: decimal     -- 出厂价
  arrival_price: decimal      -- 到厂价
  status: enum [draft, confirmed, released]
  created_at: datetime
  updated_at: datetime
}
```

### 4.6 分摊项 (AllocationItem)

```
AllocationItem {
  id: UUID (PK)
  project_id: UUID (FK → Project)
  scenario_id: UUID (FK → Scenario)
  harness_id: UUID (FK → Harness)
  expense_type: enum [tooling, mold, testing, rnd, other]
  expense_name: string
  total_amount: decimal
  unit_allocation: decimal    -- 单根分摊金额
  planned_recovery: decimal
  actual_recovered: decimal
  remaining_recovery: decimal
  recovery_progress: decimal  -- 百分比
  status: enum [pending, allocated, recovering, completed, closed]
  created_at: datetime
  updated_at: datetime
}
```

### 4.7 设变事件 (ChangeEvent)

```
ChangeEvent {
  id: UUID (PK)
  project_id: UUID (FK → Project)
  scenario_id: UUID (FK → Scenario)
  change_type: enum [add, replace, cancel, adjust]
  reason: string
  affected_harness_ids: JSON  -- [harness_id, ...]
  affected_bom_rows: JSON     -- [{row_id, before, after}, ...]
  cost_impact: decimal
  quote_impact: decimal
  residual_impact: decimal    -- 残余材料池影响
  status: enum [draft, identified, calculated, confirmed, closed]
  created_at: datetime
  updated_at: datetime
}
```

### 4.8 跟踪项 (TrackingItem)

```
TrackingItem {
  id: UUID (PK)
  project_id: UUID (FK → Project)
  scenario_id: UUID (FK → Scenario)
  tracking_type: enum [agreed_price, progress_price, allocation_recovery, residual, exception]
  title: string
  source_ref: string          -- 来源对象引用
  current_status: enum [pending, in_progress, to_confirm, completed, closed]
  planned_action: text
  actual_result: text
  closed_at: datetime
  created_at: datetime
  updated_at: datetime
}
```

### 4.9 系统设置 (Settings)

```
Settings {
  id: UUID (PK)
  category: string            -- cost_structure / metal_price / rates / alert_threshold
  key: string
  value: JSON
  updated_at: datetime
  updated_by: string
}
```

### 关系图

```
Project 1──N Scenario
Project 1──N Harness
Scenario 1──N Harness
Harness 1──N BomRow
Scenario 1──N QuoteSnapshot
Scenario 1──N AllocationItem
Scenario 1──N ChangeEvent
Scenario 1──N TrackingItem
Harness 1──N QuoteSnapshot
Harness 1──N AllocationItem
```

---

## 5. API 设计

### 5.1 项目管理

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/projects` | 项目列表（支持 ?search=&status= 筛选） |
| POST | `/api/projects` | 新建项目 |
| GET | `/api/projects/:id` | 项目详情 + Dashboard 汇总 |
| PUT | `/api/projects/:id` | 更新项目 |
| DELETE | `/api/projects/:id` | 删除项目 |

### 5.2 场景管理

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/projects/:id/scenarios` | 场景列表 |
| POST | `/api/projects/:id/scenarios` | 新建场景（选类型） |
| GET | `/api/scenarios/:sid` | 场景详情 |
| PUT | `/api/scenarios/:sid` | 更新场景 |
| GET | `/api/scenarios/:sid/summary` | 场景汇总指标 |
| GET | `/api/scenarios/compare?ids=a,b` | 场景对比 |

### 5.3 BOM 工作簿

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/scenarios/:sid/bom` | BOM 行列表（支持 ?harness=&category= 筛选） |
| POST | `/api/scenarios/:sid/bom` | 新增 BOM 行 |
| PUT | `/api/bom/:rowId` | 编辑 BOM 行 |
| DELETE | `/api/bom/:rowId` | 删除 BOM 行 |
| POST | `/api/scenarios/:sid/bom/import` | 批量导入 BOM（CSV/Excel） |
| GET | `/api/scenarios/:sid/bom/summary` | BOM 汇总（按线束号/分类） |

### 5.4 客户报价工作台

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/scenarios/:sid/quotes` | 报价列表 |
| POST | `/api/scenarios/:sid/quotes` | 创建报价快照 |
| GET | `/api/quotes/:qid` | 报价详情 |
| PUT | `/api/quotes/:qid` | 更新报价参数 |
| GET | `/api/quotes/:qid/compare` | 报价 vs 内部成本对比 |

### 5.5 分摊回收跟踪

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/scenarios/:sid/allocations` | 分摊项列表 |
| POST | `/api/scenarios/:sid/allocations` | 新增分摊项 |
| GET | `/api/allocations/:aid` | 分摊详情 + 回收进度 |
| PUT | `/api/allocations/:aid` | 更新分摊/回收状态 |
| GET | `/api/allocations/:aid/recovery-history` | 回收记录明细 |

### 5.6 设变管理

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/scenarios/:sid/changes` | 设变事件列表 |
| POST | `/api/scenarios/:sid/changes` | 新建设变事件 |
| GET | `/api/changes/:cid` | 设变详情（含前后对比） |
| PUT | `/api/changes/:cid` | 更新设变状态 |
| GET | `/api/changes/:cid/impact` | 影响分析结果 |

### 5.7 跟踪管理

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/scenarios/:sid/tracking` | 跟踪项列表 |
| POST | `/api/scenarios/:sid/tracking` | 新建跟踪项 |
| GET | `/api/tracking/:tid` | 跟踪详情 |
| PUT | `/api/tracking/:tid` | 更新跟踪状态 |

### 5.8 系统设置

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/settings` | 所有设置 |
| GET | `/api/settings/:category` | 分类设置 |
| PUT | `/api/settings/:category/:key` | 更新设置 |

---

## 6. 业务流程

### 6.1 主链路（P0 — 系统成立的最小闭环）

```
新建项目
  → 创建场景（初始报价）
    → 导入/录入 BOM
      → 系统自动计算内部成本
        → 创建客户报价快照
          → 对比内部成本 vs 客户报价
            → 识别利润空间
              → 确认报价
```

### 6.2 分摊回收链路

```
录入一次性费用（工装/模具/试验/研发）
  → 绑定线束号 + 场景
    → 系统按根计算单根分摊
      → 按 装车比 × 累计产量 跟踪回收
        → 回收完成 → 触发调价提醒
```

### 6.3 设变链路

```
BOM 发生变化（新增/替换/取消）
  → 创建设变事件
    → 系统计算成本影响 + 报价影响
      → 识别残余材料池
        → 生成跟踪项
          → 持续跟踪执行状态
```

### 6.4 场景比较链路

```
同一项目下创建多个场景
  → 各场景独立计算
    → 场景对比（成本/报价/利润/回收）
      → 支撑经营决策
```

---

## 7. 设计要求

### 7.1 整体风格
- **工业蓝图深色主题**: 深蓝/深灰底，白色文字，蓝色/绿色强调
- **信息密度优先**: 表格为主，卡片为辅
- **侧边栏导航**: 左侧项目导航 + 模块入口

### 7.2 关键 UI 组件
- **Dashboard 卡片**: 成本汇总、报价汇总、利润差异、回收进度
- **数据表格**: 可排序、可筛选、可内联编辑的专业表格
- **对比视图**: 双列对比（内部成本 vs 客户报价）
- **状态标签**: 彩色状态 badge（草稿/进行中/已完成/已关闭）
- **进度条**: 回收进度可视化

### 7.3 响应式
- 桌面优先（主要使用场景）
- 最小宽度 1280px

---

## 8. 核心计算规则

### 8.1 BOM 行成本
```
unit_cost = quantity × unit_price
```

### 8.2 线束号成本
```
harness_cost = SUM(bom_rows.unit_cost) WHERE harness_id = ?
```

### 8.3 单根分摊
```
unit_allocation = total_amount / (volume × install_ratio)
```

### 8.4 回收进度
```
recovery_progress = actual_recovered / planned_recovery × 100%
actual_recovered = cumulative_volume × install_ratio × unit_allocation
```

### 8.5 利润差异
```
profit_gap = quote_result.arrival_price - internal_cost_baseline
```

### 8.6 金属价格联动
```
metal_cost_impact = metal_weight × (current_metal_price - base_metal_price)
```

---

## 9. 边界约束（Phase 1 不做）

- ❌ 用户注册/登录/权限系统
- ❌ 审批流
- ❌ 多工厂对标
- ❌ Simulation/年降管理深度功能
- ❌ 预警系统（仅预留数据结构）
- ❌ 管理决策舱
- ❌ Profile/个人中心
- ❌ 版本与发布治理完整实现
- ❌ 客户模板适配与导出

---

## 10. 验收标准摘要

### P0 — 系统成立
1. 能新建项目、搜索项目、进入项目
2. 能在项目下创建多个场景（区分类型）
3. 能录入/导入 BOM，按线束号和分类查看
4. 能创建报价快照，查看内部成本 vs 客户报价差异
5. 能录入一次性费用，查看单根分摊和回收进度
6. 能创建设变事件，查看成本/报价影响
7. 能创建跟踪项，管理执行状态
8. 场景之间能做基础指标对比
9. 系统设置页面能配置基础费率和金属价格

### 质量要求
- 所有页面 Lighthouse Performance ≥ 70
- API 响应时间 < 500ms (p95)
- 表格支持 1000+ 行 BOM 数据
- SQLite 数据持久化，刷新不丢失
