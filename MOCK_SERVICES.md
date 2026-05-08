# TRAX Mock Services & Test Data

> 本文档列出项目中所有 Mock 服务、模拟数据、硬编码测试值，用于后续调整和生产上线前清理。

---

## Backend (Java Spring Boot)

### 1. ModuleSimulatorService — eBike GPS/传感器模拟器

**文件:** `backend/src/main/java/com/trax/service/ModuleSimulatorService.java`

**功能:** 模拟 TRAX 模块的实时 GPS 位移、速度、电池、信号强度等遥测数据。

| 项目 | 值 | 行号 |
|------|----|------|
| 默认坐标 | `34.0522, -118.2437` (洛杉矶) | 47-48 |
| 定时频率 | 每 2 秒 | 64 |
| 电池消耗 | 0.05%/tick | 137 |
| 信号强度 | 随机 70-101 | 141 |

**模拟速度分布:**
- 5% → 5-15 km/h（减速/刹车）
- 10% → 15-25 km/h（中速）
- 70% → 20-45 km/h（正常eBike）
- 15% → 35-60 km/h（加速冲刺）

---

### 2. VerificationCodeService — 验证码服务（含Dev绕过）

**文件:** `backend/src/main/java/com/trax/service/VerificationCodeService.java`

| 项目 | 值 | 行号 |
|------|----|------|
| Dev绕过码 | `111111`（任何邮箱均通过） | 29 |
| 验证码生成 | 随机6位数字 | 19 |
| 验证码输出 | `System.out.printf` 打印到控制台 | 22 |
| 有效期 | 10 分钟 | 21 |

---

### 3. DataInitializer — 启动数据种子

**文件:** `backend/src/main/java/com/trax/config/DataInitializer.java`

**功能:** 应用启动时自动填充品牌、车型、TRAX 模块数据（仅在数据库为空时执行）。

**种子品牌 (6个):** BONNELL, RISTRETTO, Talaria, Sur-Ron, E Ride, RERODE

**种子 TRAX 模块 (6个):**

| 序列号 | 名称 |
|--------|------|
| TRX-7A2B | CYC Gen4 |
| TRX-3F9C | Sur-Ron Custom |
| TRX-12DE | Generic |
| TRX-4B1A | CYC Photon |
| TRX-9D5B | BONNELL 805 |
| TRX-8C3A | BONNELL 902 |

**种子车型:** 20+ 款，含电机功率、扭矩、电压、电池容量、控制器等参数。

---

### 4. BicycleController — 自动创建测试用户

**文件:** `backend/src/main/java/com/trax/controller/BicycleController.java`

| 项目 | 值 | 行号 |
|------|----|------|
| 自动创建逻辑 | 用户不存在时自动新建 | 39-46 |
| 测试密码 | `"test"` | 43 |
| 测试用户名 | `"Test User"` | 44 |

---

### 5. 硬编码配置

**文件:** `backend/src/main/resources/application.yml`

| 项目 | 值 | 行号 |
|------|----|------|
| 数据库 | `jdbc:h2:file:./traxdb` (H2文件数据库) | 5 |
| H2控制台 | 启用，路径 `/h2-console` | 10-12 |
| JWT Secret | `trax-secret-key-for-jwt-token-generation-min-256-bits-long-key` | 29 |
| JWT过期时间 | 86400000 ms (24小时) | 30 |

---

## Frontend (Flutter)

### 6. Mock Lap 模拟 — 录制页面模拟骑行

**文件:** `trax_app/lib/screens/trails/trail_record_page.dart`

**功能:** `_onStartMockLap()` 在当前位置周围生成4个方向250m的路径点，通过 Google Directions API 获取闭合路径，模拟骑行轨迹录制。

| 项目 | 值 | 行号 |
|------|----|------|
| 默认坐标 | `34.0522, -118.2437` (洛杉矶) | 22 |
| Google Maps API Key | `AIzaSyDmzdgVvZu4f5Q7zCKytQ5Syz0RLQzUxng` | 159 |
| 模拟时长 | 120 秒 | 160 |
| GPS 抖动 | ±2m 随机偏移 | 230 |
| 模拟海拔 | `50.0 + sin(tick * 0.2) * 5` | 235 |
| 路径点间距 | 250m (东南西北各一个) | 254-266 |

---

### 7. Mock Events — 骑行事件假数据

**文件:** `trax_app/lib/screens/ride/ride_screen.dart`

**功能:** 硬编码3个模拟骑行事件用于 UI 展示。

| 事件名称 | 类型 | 日期 | 人数 | 状态 |
|----------|------|------|------|------|
| Sunday Hill Climb | hosted | Apr 20, 2026 · 9:00 AM | 6 | Upcoming |
| Downtown Circuit | joined | Apr 22, 2026 · 3:00 PM | 12 | Upcoming |
| Night Ride Challenge | hosted | Apr 27, 2026 · 7:30 PM | 4 | Open |

---

### 8. 硬编码 Google Maps API Key（4处）

| 文件 | 行号 |
|------|------|
| `trax_app/lib/screens/trails/trail_record_page.dart` | 159 |
| `trax_app/lib/screens/trails/trail_save_page.dart` | 27 |
| `trax_app/lib/screens/trails/trail_detail_page.dart` | 29 |
| `trax_app/lib/screens/trails/trails_screen.dart` | 346 |

**Key:** `AIzaSyDmzdgVvZu4f5Q7zCKytQ5Syz0RLQzUxng`

---

### 9. 硬编码 Localhost URL

| 文件 | 值 | 用途 |
|------|----|------|
| `trax_app/lib/common/network/trax_api.dart:10-11` | `http://localhost:8080/api` | API 基础地址（Release/Debug 相同） |
| `trax_app/lib/common/widgets/model_image_card.dart` | `http://localhost:8080$imageUrl` | 车型图片加载 |

---

### 10. 模拟 API 端点（前端调用后端模拟器）

**文件:** `trax_app/lib/common/network/trax_api.dart`

| 方法 | 端点 | 行号 |
|------|------|------|
| `startSimulation()` | POST `/modules/simulate/start` | 317 |
| `pauseSimulation()` | POST `/modules/simulate/pause` | 323 |
| `resumeSimulation()` | POST `/modules/simulate/resume` | 327 |
| `stopSimulation()` | POST `/modules/simulate/stop` | 331 |

---

### 11. ActiveRideService — 默认坐标

**文件:** `trax_app/lib/services/active_ride_service.dart`

| 项目 | 值 | 行号 |
|------|----|------|
| 默认坐标 | `34.0522, -118.2437` (洛杉矶) | 23 |

---

## 生产上线前需处理项汇总

| 类别 | 数量 | 优先级 |
|------|------|--------|
| 硬编码 API Key (Google Maps) | 4 处 | **高** |
| Dev 绕过验证码 (`111111`) | 1 处 | **高** |
| 硬编码 JWT Secret | 1 处 | **高** |
| 硬编码 Localhost URL | 2 处 | **高** |
| 自动创建测试用户 | 1 处 | **中** |
| 硬编码测试密码 (`"test"`) | 1 处 | **中** |
| 硬编码默认坐标 (LA) | 3 处 | **中** |
| 模拟服务 (ModuleSimulator) | 1 处 | **低** |
| Mock 事件数据 | 1 处 | **低** |
| 种子数据 (品牌/车型) | 1 处 | **低** |
