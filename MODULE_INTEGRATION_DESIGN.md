# TRAX Module × App 集成设计方案 v1.0

> **状态**：评估稿 · 2026-05-18
> **作者**：研发团队
> **关联代码**：`backend/`、`trax_app/lib/`
> **关联文档**：`deploy_plan.txt`、`MOCK_SERVICES.md`

---

## 0. 决策摘要（已与产品确认）

| # | 决策点 | 结论 |
|---|---|---|
| 1 | Module 联网 | **仅 4G/5G**，不连 Wi-Fi |
| 2 | Module ↔ Server 协议 | **MQTTS** |
| 3 | 一辆车 ↔ Module | **1 : 1**（不支持多模块） |
| 4 | A-GNSS | **启用**（提升冷启动 / 地库出库体验） |
| 5 | 采样率上限 | **待硬件评估后定**，软件先按 1 Hz 默认，可调档 1/2/5 Hz |
| 6 | 隐私授权 | App 端弹窗解决，不影响协议设计 |
| 7 | MQTT Broker | **阶段 1：自建 Mosquitto**（与 backend 同机器）；阶段 2：EMQX 或阿里云 IoT |
| 8 | 解绑权限 | 持有者 + **客服后台** 均可强制解绑 |
| 9 | 其他骑手数据 | 仅 **位置 + 速度**（与现有 App 行为一致） |
| 10 | Race / Lap Review | **必须支持**，使用服务端缓存的全程数据回放（App 已具备）|
| 11 | 多人活动 | host laps / host race 当前用手机 GPS 已实现；**module 模式需保持功能等价** |

---

## 1. 总体架构

```
 ┌────────┐   BLE  ┌────────┐   MQTTS / 4G   ┌──────────┐
 │  App   │ ─────► │ Module │ ─────────────► │  Broker  │
 │ Phone  │  仅    │ Bike    │                │ Mosquitto│
 │        │ 一次   │         │ ◄───────────── │ (TLS)    │
 │        │ 配网   │         │   命令推送      └────┬─────┘
 └───┬────┘        └─────────┘                     │
     │                                              ▼
     │              HTTPS  + WebSocket        ┌──────────┐
     └────────────────────────────────────────►│  Server  │
                                              │  Spring  │
                                              │  Boot    │
                                              └──────────┘
```

- **BLE**：仅承担首次"配网 + 绑定"（无 Wi-Fi 凭据，因为 Module 走 4G/5G）。
- **MQTTS**：Module 与 Server 之间所有运行时数据 / 命令的唯一通道。
- **HTTPS / WebSocket**：App 与 Server 之间所有数据 / 命令的唯一通道。
- **App 与 Module 永不直连**（除 BLE 配网阶段），保证手机不在车旁也能查看 / 控制。

---

## 2. 角色边界

| 维度 | App | Module | Server |
|---|---|---|---|
| GPS 数据源 | 仅当 bike 无 module 时启用手机 GPS | 主力（GNSS + IMU） | — |
| 命令发起 | 用户点按 → REST | — | 转发到 Module |
| 数据采集 | — | 主体 | 持久化、扇出 |
| 数据展示 | 唯一入口 | — | 提供 API + WS 推送 |
| 多人订阅 | WebSocket 订阅活动频道 | 不关心他人 | 扇出 |
| Review | 历史轨迹回放 | — | 提供 `/api/rides/{id}/track` |

### 2.1 Module 模式判定（App 内）

```
hasModule = bike.module != null
         && module.online == true
         && (now - module.lastSeenAt) < 60s
```

- `true` → `mode = with_module`，App 不再读取手机 GPS，监听 WS 接收 telemetry。
- `false` → `mode = without_module`，App 用手机 GPS，POST 到 `/api/rides/{id}/location`。

> 现有 `ActiveRideService._hasModule` 字段已存在；只需把判定阈值 60 s 写实，并在 module 上线 / 离线时实时切换。

---

## 3. BLE 配网协议（仅首次绑定）

### 3.1 GATT 设计

| Service UUID | 用途 |
|---|---|
| `0000FE5A-...` (TRAX Service) | 配网与状态 |

| Characteristic | Properties | Payload |
|---|---|---|
| `0xFE01` Info | Read | `{ serialNo, fwVersion, hwRev, imei }` |
| `0xFE02` BindChallenge | Read | 32 B 随机 nonce（每次广播刷新） |
| `0xFE03` BindCommit | Write + Notify | App→ `{ bindToken, serverEndpoint, mqttsEndpoint }`<br>Module→ `{ result, deviceCsr }` |
| `0xFE04` Status | Notify | `{ online, gpsFix, batteryPct, rssi }` |

> 与上一版相比 **移除了 Wi-Fi SSID/密码**，因为 Module 只走蜂窝。

### 3.2 绑定流程

```
App                              Module                Server
 │ 1. BLE scan (filter UUID FE5A)
 │─────────────────────────────────►
 │ 2. POST /api/modules/bind/intent {serialNo}
 │ ◄──── { bindToken, nonce, serverEp, mqttsEp } ─────────│
 │
 │ 3. Write BindCommit (bindToken, endpoints)
 │─────────────────────────────────►
 │                                   │ 4. Module via 4G
 │                                   │ HTTPS POST /api/modules/bind/confirm
 │                                   │   { serialNo, bindToken, deviceCsr }
 │                                   │ ─────────────────►│
 │                                   │ ◄──{deviceCert,mqttCreds}──│
 │                                   │ 5. Notify Status: bound
 │ ◄─────────────────────────────────│
 │ 6. GET /api/modules/mine 确认归属
```

### 3.3 防重复绑定

- `TraxModule` 新增字段：`ownerUserId` (FK)、`boundAt`、`lastSeenAt`、`fwVersion`、`deviceCertSubject`。
- `POST /api/modules/bind/intent` 校验 `bound == false`，否则返回 `409 ALREADY_BOUND`。
- `bindToken` 有效期 **5 分钟**，单次使用。
- 解绑：
  - **持有者**：`DELETE /api/modules/{sn}/bind`
  - **客服后台**：`POST /api/admin/modules/{sn}/force-unbind`（写审计日志，记录客服 ID + 原因）
  - 两条路径都通过命令通道下发 `factory_reset`，Module ACK 后才把 `bound=false` 落库。

---

## 4. MQTT 命令 / 数据通道设计

### 4.1 Broker（阶段 1：自建 Mosquitto）

- 部署：阿里云 ECS（与 backend 同机器），Docker compose 起单实例。
- 端口：**8883 (MQTTS)**，禁用 1883 明文。
- 证书：Let's Encrypt（域名 `mqtts.trax.cycmotor.com`）。
- 客户端认证：**X.509 设备证书**（Module）、Username + Password（Server）。

### 4.2 Topic 设计

| Topic | 方向 | QoS | 保留 | 说明 |
|---|---|---|---|---|
| `trax/telemetry/{serialNo}` | Module → Server | 1 | ❌ | 数据上报（批量） |
| `trax/cmd/{serialNo}` | Server → Module | 1 | ✅ | 命令下发（保留最后一条以应对掉线后重连）|
| `trax/ack/{serialNo}` | Module → Server | 1 | ❌ | 命令执行回执 |
| `trax/status/{serialNo}` | Module → Server | 1 | ✅ | 上下线（LWT 遗嘱：`{online:false}`）|
| `trax/event/{serialNo}` | Module → Server | 1 | ❌ | 异常事件（低电、传感器故障）|

### 4.3 命令信封

```json
{
  "cmdId": "uuid-v4",
  "type": "start_track | stop_track | track_fix | factory_reset | reboot",
  "issuedAt": "2026-05-18T12:30:00Z",
  "issuedBy": { "userId": 123, "via": "app | admin" },
  "payload": { ... },
  "expiresAt": "2026-05-18T12:35:00Z"
}
```

ACK：
```json
{ "cmdId": "...", "result": "ok | rejected", "reason": "...", "executedAt": "..." }
```

### 4.4 命令字典

| type | payload | 说明 |
|---|---|---|
| `start_track` | `{ sessionId, sessionType, sampleHz?: 1, uploadIntervalSec?: 5 }` | sessionType ∈ `trail | lap | race`；sessionId 由后端预生成 |
| `stop_track` | `{ sessionId }` | Module 必须把缓冲清空再 ACK |
| `track_fix` | `{ sampleHz: 1\|2\|5, uploadIntervalSec: 1..60, gpsMode?: "balanced\|highaccuracy" }` | 运行时调参 |
| `factory_reset` | `{}` | 解绑 |
| `reboot` | `{}` | 远程重启 |

### 4.5 端到端延迟目标

| 场景 | 目标 |
|---|---|
| App 发送 `start_track` → Module 收到 | < 300 ms（蜂窝网良好） |
| Module 上报 sample → 其他骑手 App 看到 | **< 1 s**（满足 race 实时需求） |
| Module 离线 → 服务端 status 变 offline | < 30 s（MQTT keep-alive） |

---

## 5. Telemetry Schema（提交硬件团队）

### 5.1 单条 sample 字段表

| 字段 | 类型 | 必填 | 单位/取值 | 说明 |
|---|---|---|---|---|
| `serialNo` | string(32) | ✅ | — | Module 序列号 |
| `sessionId` | uint64 | ✅ | — | 由 `start_track` 下发；0 表示空闲心跳 |
| `seq` | uint32 | ✅ | — | session 内单调递增，丢包检测用 |
| `tsUtcMs` | int64 | ✅ | UTC 毫秒 | GNSS 时间，无 fix 时用本地 RTC |
| `lat` | double | ✅ | WGS-84 度 | 6 位小数 |
| `lng` | double | ✅ | WGS-84 度 | 6 位小数 |
| `altM` | float | ❌ | 米 | 椭球高 |
| `speedKph` | float | ✅ | km/h | GNSS doppler |
| `bearingDeg` | float | ❌ | 0–360 | 航向角 |
| `hdop` | float | ❌ | — | 水平精度因子 |
| `satCount` | uint8 | ❌ | — | 可见星数 |
| `fixType` | uint8 | ✅ | 0=no, 2=2D, 3=3D, 4=DGNSS, 5=RTK | |
| `accelMs2` | float[3] | ❌ | m/s² | IMU 三轴加速度（最近 100 ms 均值） |
| `gyroDps` | float[3] | ❌ | °/s | IMU 三轴陀螺仪 |
| `leanDeg` | float | ❌ | ° | 车身侧倾（IMU 解算后） |
| `motorRpm` | int32 | ❌ | rpm | controller 总线 |
| `motorPowerW` | int32 | ❌ | W | |
| `motorTempC` | float | ❌ | °C | |
| `battVoltageV` | float | ❌ | V | 主电池电压 |
| `battCurrentA` | float | ❌ | A | 放电正/回充负 |
| `battSocPct` | uint8 | ❌ | 0–100 | 主电池 SoC |
| `moduleBattPct` | uint8 | ✅ | 0–100 | Module 自身电量 |
| `rssiDbm` | int8 | ✅ | dBm | 蜂窝信号 |
| `flags` | uint16 | ✅ | bitmask | bit0=BACKFILL（补发）, bit1=LOW_BATT, bit2=NO_GNSS |

### 5.2 批量信封（MQTT payload）

```json
{
  "serialNo": "TRX-7A2B",
  "deviceTs": 1747573800000,
  "samples": [ {sample1}, {sample2}, ... ],
  "compression": "gzip | none"
}
```

- 单包建议 ≤ 64 KB，超过分包。
- `compression=gzip` 时整个 payload 是 gzip 后的二进制（topic 后缀加 `/gz`）。

### 5.3 数据库表（MySQL，与现有 backend 一致）

```sql
CREATE TABLE module_telemetry (
  id              BIGINT AUTO_INCREMENT PRIMARY KEY,
  module_id       BIGINT      NOT NULL,
  session_id      BIGINT      NULL,
  seq             INT         NULL,
  ts_utc_ms       BIGINT      NOT NULL,
  lat             DOUBLE      NOT NULL,
  lng             DOUBLE      NOT NULL,
  alt_m           FLOAT       NULL,
  speed_kph       FLOAT       NOT NULL,
  bearing_deg     FLOAT       NULL,
  hdop            FLOAT       NULL,
  sat_count       SMALLINT    NULL,
  fix_type        TINYINT     NOT NULL,
  lean_deg        FLOAT       NULL,
  motor_rpm       INT         NULL,
  motor_power_w   INT         NULL,
  batt_soc_pct    TINYINT     NULL,
  module_batt_pct TINYINT     NOT NULL,
  rssi_dbm        TINYINT     NOT NULL,
  flags           SMALLINT    NOT NULL DEFAULT 0,
  received_at     DATETIME(3) NOT NULL,
  UNIQUE KEY uk_session_seq (session_id, seq),
  KEY idx_module_ts (module_id, ts_utc_ms),
  KEY idx_session   (session_id, ts_utc_ms)
);
```

> 现有 `ModuleTelemetryDto` 字段（serialNo / lat / lng / speed / batteryPercent / signalStrength / timestamp）保留，作为旧字段映射到新表的子集。

---

## 6. 多人活动（laps / race）— 与现有功能等价

### 6.1 现状回顾
- App 已实现 host laps / host race，**用手机 GPS** 时所有骑手通过 `POST /api/rides/{id}/location` 上报。
- 服务端已聚合并下发，App 端 `_buildLiveRankingOverlay` 已展示实时排名。

### 6.2 切换到 module 后的关键改动

**目标**：上层 UI 与 race 逻辑 0 修改，只在数据采集层透明替换。

| 层 | 改动 |
|---|---|
| Module | 收到 `start_track {sessionType: race, sessionId}` 开始按 race 配置上报 |
| Server | 收到 telemetry 时，若该 sample 的 sessionId 属于某个 race / lap，扇出到 `race:{raceId}` / `laps:{groupId}` 频道 |
| App | 用 WebSocket 订阅频道（替代当前轮询）；不再关心数据从手机 GPS 还是 module 来 |

### 6.3 混合骑手场景（有的有 module，有的没有）

```
Module-A ─── MQTT ──► Server ──┐
Module-B ─── MQTT ──► Server ──┤
Phone-C  ── HTTP ───► Server ──┴──► race:42 频道 ──► 所有 App
```

- 服务端按 `riderId` 归一化，不暴露数据来源差异。
- App 端 race 页 / lap 页代码 **完全不感知** module 的存在。

### 6.4 实时推送内容（race / lap 频道）

```json
{
  "raceId": 42,
  "tsUtcMs": 1747573800123,
  "riders": [
    { "riderId": 1, "lat": 22.5, "lng": 114.1, "speedKph": 38.5, "completedLaps": 2, "lastLapMs": 64500 },
    { "riderId": 2, "lat": 22.51, "lng": 114.12, "speedKph": 41.0, "completedLaps": 2 },
    ...
  ]
}
```

- 仅含 **位置 + 速度 + 圈数**（与产品决策 #9 一致）。
- 频率：默认 1 Hz；race 进入冲刺阶段（最后 1 圈）可提升到 2 Hz。

---

## 7. Race / Lap Review（回放模式）

### 7.1 数据源
- Race / Lap 进行中，服务端将所有骑手的 telemetry 持久化到 `module_telemetry`（或 `phone_location_log` 表）。
- 结束后由后台任务生成单文件 `race_replay_{raceId}.json`（gzip 压缩，放 OSS）。

### 7.2 接口

| Method | Path | 返回 |
|---|---|---|
| GET | `/api/races/{raceId}/replay` | `{ duration, riders: [...], samplesUrl }` |
| GET | `samplesUrl` (OSS) | gzip JSON：按时间排序的全员 sample |

### 7.3 App 端
- 既有 review 页面（`screens/ride/review_*`）保持，数据源从 in-memory 切换为 `/api/races/{raceId}/replay`。
- 控制条：播放 / 暂停 / 1×/2×/4× 倍速。

---

## 8. 离线缓存与补发

### 8.1 Module 侧
- 本地 ring buffer：≥ **24 小时 × 1 Hz × 80 B ≈ 7 MB** flash。
- 网络判定：MQTT 连接断开（broker ping 3 次失败）→ 进入 offline 模式，继续采样不上传。
- 恢复策略：
  1. 重连成功后，先发"当前实时数据流"。
  2. 后台分批补传，每条 sample `flags |= BACKFILL`。
  3. 批大小建议 100 条 / 包，间隔 200 ms。
  4. 服务端按 `(session_id, seq)` 唯一键去重。

### 8.2 Server 侧
- 收到 `BACKFILL` 数据时：
  - **不触发**实时频道推送（避免回放到正在直播的活动里）。
  - 触发"轨迹完整性"事件，App 端在 Review 模式下重新拉取 replay 数据。

### 8.3 App 侧
- Trail 详情页若该 trail 在 24 h 内仍有补发数据进入，显示"已补齐 N 个采样点，下拉刷新"提示。

---

## 9. REST / MQTT / WS API 总览

### 9.1 REST（App ↔ Server）

| Method | Path | 说明 |
|---|---|---|
| POST | `/api/modules/bind/intent` | App 发起绑定，返回 `bindToken` |
| POST | `/api/modules/bind/confirm` | Module 完成绑定（首次连云） |
| DELETE | `/api/modules/{sn}/bind` | 持有者解绑 |
| POST | `/api/admin/modules/{sn}/force-unbind` | 客服强制解绑 |
| GET | `/api/modules/mine` | 当前用户已绑定列表 |
| GET | `/api/modules/{sn}` | Module 状态 / 版本 / 在线 / 电量 |
| POST | `/api/modules/{sn}/commands` | 下发命令；返回 `{cmdId, status:"queued"}` |
| GET | `/api/modules/{sn}/commands/{cmdId}` | 查命令执行状态 |
| POST | `/api/rides/start` | 创建 session，返回 `{sessionId, mode}` |
| POST | `/api/rides/{sessionId}/stop` | 结束 session |
| GET | `/api/rides/{sessionId}/track` | 拉历史轨迹（含补发后的完整数据） |
| GET | `/api/races/{raceId}/replay` | Race 回放数据 |

### 9.2 MQTT（Module ↔ Server）

| Topic | 方向 | QoS | 说明 |
|---|---|---|---|
| `trax/telemetry/{sn}` | M → S | 1 | 批量上报 |
| `trax/cmd/{sn}` | S → M | 1 retain | 命令下发 |
| `trax/ack/{sn}` | M → S | 1 | 命令回执 |
| `trax/status/{sn}` | M → S | 1 retain (LWT) | 在线状态 |
| `trax/event/{sn}` | M → S | 1 | 异常事件 |

### 9.3 WebSocket（App ↔ Server）

| Channel | 订阅者 | 推送内容 |
|---|---|---|
| `/ws/ride/{sessionId}` | 本人 App | 自己的 telemetry |
| `/ws/race/{raceId}` | 所有参赛者 App | 全员位置 + 速度 + 圈数 |
| `/ws/laps/{groupId}` | 所有 lap 参与者 | 同上 |
| `/ws/module/{sn}/status` | 持有者 App | 在线 / 电量 / 信号 |

---

## 10. 安全与认证

| 主体 | 凭据 | 续期 |
|---|---|---|
| App | JWT（现有） | 现有刷新机制 |
| Module | X.509 设备证书（出厂烧录 EC 私钥，CSR 由后端 CA 签发） | 证书 2 年有效；MQTT 连接用证书 |
| App → Server 命令 | JWT | — |
| Server → Module 命令 | MQTT publish 权限按 topic ACL 限制 | — |

防护要点：
- `bindToken` 服务端生成、单次使用，避免 BLE 嗅探重放。
- Module 序列号 + EC 私钥 = 唯一身份。
- 所有 telemetry 入库前校验 `sessionId` 属于 `module.ownerUserId` 当前 session。
- 客服强制解绑必须落审计日志（操作人、时间、原因）。

---

## 11. 与现有代码的差异（迁移清单）

| 现状 | 需变更 | 优先级 |
|---|---|---|
| `TraxModule` 字段不足 | 新增 `ownerUserId / boundAt / lastSeenAt / fwVersion / deviceCertSubject / online` | P0 |
| `ModuleTelemetryDto` 仅 7 字段 | 扩展为 §5.1 全字段（旧字段保留兼容） | P0 |
| `ModuleSimulatorService` 在用 | 保留作为开发 / 测试入口，prod 关闭（`@Profile("!prod")`） | P1 |
| `RaceService.startRace()` 已切 `without_module` | 改为按每个 rider 的 bike 自动判定；有 module 的下发 `start_track` MQTT 命令 | P0 |
| App 实时数据靠轮询 | 改 WebSocket 订阅 `/ws/race/{raceId}` | P1 |
| 无命令表 | 新增 `module_command` 表（cmdId、type、payload、status、issuedAt、ackedAt、attempts） | P0 |
| App 无 BLE 扫描 UI | 新增 "Add Module" 流程页（BLE scan → 选择 → 绑定向导） | P0 |
| 无 MQTT broker | 部署 Mosquitto，TLS 证书申请 | P0 |
| 无 Module CA | 后端新增 CA 服务，处理 CSR 签发 | P0 |
| 无客服后台 | 新增 admin UI 或先用临时 REST API | P2 |

---

## 12. 落地阶段计划

| 阶段 | 内容 | 交付物 |
|---|---|---|
| **M1（2 周）** | 后端：扩 `TraxModule` 字段 / 新增 `module_command` 表 / 部署 Mosquitto / Module CA 雏形 | DB migration + MQTT 连通 |
| **M2（2 周）** | Module 固件 PoC：BLE 配网 + MQTT 连接 + telemetry 上报基本字段 | 1 台样机能上报位置数据 |
| **M3（3 周）** | App 端：BLE 配网页 + WS 订阅替换 race 轮询 + Review 数据源切换 | App 可绑定 module，host race 可见 module 数据 |
| **M4（2 周）** | 补发功能 + 客服后台 + Module OTA | 离线场景可恢复 |
| **M5（持续）** | 量产前压测：100 台 module × 1 Hz 持续 1 小时 | 性能报告 |

---

## 13. 待硬件团队评审的开放问题

1. **GNSS 芯片选型**：是否支持 A-GNSS（u-blox MAX-M10 / Quectel L96 等）？
2. **采样率上限**：MCU 算力能否稳定到 5 Hz / 10 Hz？
3. **IMU 是否必选**：决定 telemetry 表中 `accelMs2 / gyroDps / leanDeg` 是否实际填充。
4. **Controller 总线协议**：CAN / UART / 自定义？决定 motor / battery 字段的可获得性。
5. **4G/5G 模组型号**：是否带内置 MQTT 协议栈（如 Quectel BG95），可减轻 MCU 负担。
6. **Flash 容量**：是否预留 ≥ 8 MB 给离线缓冲。

---

## 附录 A：现有 Repo 关键文件索引

- 后端 Module 模型：[backend/src/main/java/com/trax/model/TraxModule.java](backend/src/main/java/com/trax/model/TraxModule.java)
- 后端 Telemetry：[backend/src/main/java/com/trax/service/ModuleTelemetryService.java](backend/src/main/java/com/trax/service/ModuleTelemetryService.java)
- 后端 Telemetry DTO：[backend/src/main/java/com/trax/dto/ModuleTelemetryDto.java](backend/src/main/java/com/trax/dto/ModuleTelemetryDto.java)
- App Active Ride：[trax_app/lib/services/active_ride_service.dart](trax_app/lib/services/active_ride_service.dart)
- App Race Tracking（Google）：[trax_app/lib/screens/ride/race_tracking_page.dart](trax_app/lib/screens/ride/race_tracking_page.dart)
- App Race Tracking（AMap）：[trax_app/lib/screens/ride/amap/race_tracking_page_amap.dart](trax_app/lib/screens/ride/amap/race_tracking_page_amap.dart)
- 部署运维：[deploy_plan.txt](deploy_plan.txt)
