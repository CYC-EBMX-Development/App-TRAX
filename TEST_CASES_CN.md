# TRAX 测试用例清单（中文版）

> 范围：86 个自动化测试 — 41 后端 (JUnit 5 / Spring Boot Test) + 45 Flutter (`flutter_test`)
> 全部通过日期：2026-05-18

---

## 一、后端测试

### 1. `JwtUtilTest`（6 用例）`security/JwtUtilTest.java`

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 1.1 | 生成并解析合法 token | userId=42, username="alice" | `extractUserId`=42；`extractUsername`="alice"；`validateToken`=true |
| 1.2 | extractExpiration 在未来 | 当前时间生成的 token | `expiration > now` |
| 1.3 | 篡改 token 校验失败 | 合法 token 末尾追加 "x" | `validateToken` 抛 `JwtException` 或返回 false |
| 1.4 | 错误密钥构造的 JwtUtil 校验失败 | 用密钥 A 签发，密钥 B 校验 | 抛 `SignatureException` |
| 1.5 | 过期 token 校验失败 | `expirationMs=1` 立即过期 | 抛 `ExpiredJwtException` |
| 1.6 | 错误用户名 validateToken 返回 false | token(alice) + 校验 "bob" | 返回 false |

### 2. `GeoUtilsTest`（8 用例）`util/GeoUtilsTest.java`

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 2.1 | haversine 同点距离 | (31.0,121.0) → (31.0,121.0) | 0 km |
| 2.2 | haversine 已知短距 | (31.0,121.0) → (31.001,121.001) | ≈ 0.1485 km（±0.005） |
| 2.3 | 点到线段—投影在端点外 | 段(0,0)-(0,0.01)，点(0,0.02) | ≈ 1.113 km |
| 2.4 | 点到线段—投影在中点 | 段(0,0)-(0,0.02)，点(0.001,0.01) | ≈ 0.111 km |
| 2.5 | 单点折线 | 折线[(0,0)]，点(0,0.001) | 距离 ≈ 111 m |
| 2.6 | 点到折线 | 多点折线 | 返回最短段距离（米） |
| 2.7 | 投影—在第一段 | 简单折线 | `segmentIndex=0`, `t∈[0,1]` |
| 2.8 | 投影—超出末端 | 点远超末端 | `segmentIndex=lastIdx`, `t=1.0` |

### 3. `AvatarUrlsTest`（6 用例）`util/AvatarUrlsTest.java`

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 3.1 | null 原路径 | null | null |
| 3.2 | 空字符串 | "" | "" |
| 3.3 | 无版本号 → 追加 `?v=` | "/img/a.jpg", v=3 | "/img/a.jpg?v=3" |
| 3.4 | 已有 query → 用 `&v=` | "/img/a.jpg?x=1", v=2 | "/img/a.jpg?x=1&v=2" |
| 3.5 | 替换已有 v= | "/img/a.jpg?v=1", v=9 | "/img/a.jpg?v=9" |
| 3.6 | v=0 不修改 | "/img/a.jpg", v=0 | "/img/a.jpg" |

### 4. `PolylineDecoderTest`（2 用例）`util/PolylineDecoderTest.java`

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 4.1 | Google 官方示例 | `_p~iF~ps|U_ulLnnqC_mqNvxq``@` | 3 个点：(38.5,-120.2)/(40.7,-120.95)/(43.252,-126.453) |
| 4.2 | 空字符串 | "" | 空列表 |

### 5. `LapDetectorTest`（5 用例）`util/LapDetectorTest.java`

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 5.1 | 单圈检测 | 模拟矩形 1 圈 GPS 序列 | lapCount=1 |
| 5.2 | 双圈检测 | 矩形 2 圈 | lapCount=2 |
| 5.3 | 半圈不计数 | 仅走 50% | lapCount=0 |
| 5.4 | 反向不计数 | 反方向走整圈 | lapCount=0 |
| 5.5 | 阈值边界 | 重叠率刚好达阈值 | lapCount=1 |

### 6. `AuthServiceTest`（9 用例，Mockito）`service/AuthServiceTest.java`

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 6.1 | 注册—用户名已存在 | username="alice" 已存在 | 抛 `RuntimeException("Username already exists")` |
| 6.2 | 注册—邮箱已存在 | email="a@b.c" 已存在 | 抛 `RuntimeException("Email already exists")` |
| 6.3 | 注册—成功 | 新用户 | 调用 `passwordEncoder.encode` 和 `userRepository.save`，返回 LoginData |
| 6.4 | 登录—用户不存在 | username="ghost" | 抛 `RuntimeException("Account not found")` |
| 6.5 | 登录—密码错误 | 密码 mismatch | 抛 `RuntimeException("Incorrect password")` |
| 6.6 | 登录—成功签发 JWT | 正确凭证 | 返回 LoginData，含非空 token + user 字段 |
| 6.7 | 重置密码—用户不存在 | 未知 email | 抛异常 |
| 6.8 | 重置密码—成功 | 合法 email + 新密码 | `userRepository.save` 被调用，新密码已 encode |
| 6.9 | findById 透传 | id=1 | 返回 mock 的 User |

### 7. `AuthControllerTest`（5 用例，MockMvc + H2）`controller/AuthControllerTest.java`

> 由于 `GlobalExceptionHandler` 把 `RuntimeException` 转换为 HTTP 200 + `{flag:false, code:40000}`，错误路径仍断言 200。

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 7.1 | POST /api/auth/register 成功 | `{username, password, email}` 新用户 | HTTP 200; `$.flag=true`; `$.data.token` 非空 |
| 7.2 | POST /api/auth/register 重复用户名 | 已存在的 username | HTTP 200; `$.flag=false`; `$.message` 含 "already" |
| 7.3 | POST /api/auth/login 成功 | 正确凭证 | HTTP 200; `$.flag=true`; `$.data.user.username` 匹配 |
| 7.4 | POST /api/auth/login 密码错 | 错误密码 | HTTP 200; `$.flag=false`; `$.message` 含 "Incorrect password" |
| 7.5 | POST /api/auth/login 用户不存在 | 未知 username | HTTP 200; `$.flag=false`; `$.message` 含 "Account not found" |

---

## 二、Flutter 测试

### 8. `models/user_test.dart`（5 用例）

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 8.1 | User.fromJson 完整字段 | 含 id/username/email/avatar/bicycles 的 JSON | 全字段映射正确；bicycles.length=2 |
| 8.2 | User.fromJson 缺省字段 | `{id:1}` | username=""; email=""; bicycles=[] |
| 8.3 | toJson 往返 | 上述 user | toJson()→fromJson() 等价 |
| 8.4 | Bicycle.fromJson | 含 name/motor/battery | 字段映射正确 |
| 8.5 | Bicycle copyWith | 替换 name | 仅 name 改变，其他保留 |

### 9. `models/ride_point_test.dart`（3 用例）

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 9.1 | 完整字段 | lat/lng/elevation/speed/timestamp | 全字段相等 |
| 9.2 | int→double 强转 | `"latitude":31` | latitude == 31.0 |
| 9.3 | toJson 往返 | 上述点 | 等价 |

### 10. `models/ride_stats_test.dart`（3 用例）

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 10.1 | 完整 payload | distance/avgSpeed/laps[…] | 全字段映射；laps.length=2 |
| 10.2 | 缺省 | `{}` | distance=0; laps=[] |
| 10.3 | laps=null | `{laps:null}` | laps=[] |

### 11. `models/race_test.dart`（6 用例）

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 11.1 | 完整 Race | 含 participants/myRole=host | gameType="LAPS"; isLaps=true; isInProgress=true; isHost=true |
| 11.2 | 最小 payload defaults | `{id:1}` | name=""; maxParticipants=10; gameType="RACE"; isWaiting=true |
| 11.3 | 仅 `public` 字段 | `{public:false}` | isPublic=false |
| 11.4 | `public` 优先于 `isPublic` | `{isPublic:false, public:true}` | isPublic=true（按代码 `?? ` 顺序） |
| 11.5 | copyWith | 修改 status | 其余字段保留 |
| 11.6 | RaceParticipant | host/rider/observer | isHost / isRider / isObserver 标志正确 |

### 12. `models/trail_test.dart`（3 用例）

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 12.1 | 完整字段 | name/distance/points[] | 全字段映射；points.length=N |
| 12.2 | 缺省 | `{id:1}` | distance=0; points=[] |
| 12.3 | toJson 往返 | 上述 trail | 等价 |

### 13. `models/ebike_test.dart`（5 用例）

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 13.1 | 完整含 modelData | brand/model 等字段 | modelData!=null; isConnected=true |
| 13.2 | isConnected 回退 | 缺 `connected`，有 `isConnected:true` | isConnected=true |
| 13.3 | 缺省 createdAt | 不传 createdAt | createdAt≈now |
| 13.4 | copyWith | 改 name + motorCertified | 仅这两个字段改变 |
| 13.5 | toJson | 完整字段 | 序列化含 traxSerialNumber/motorCertified |

### 14. `models/ride_record_test.dart`（4 用例）

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 14.1 | 完整 payload | id/trailId/distance/laps 等 | 字段映射正确 |
| 14.2 | duration getter | start/end 间隔 5 分钟 | duration == 5 min |
| 14.3 | duration 缺时间戳 | 仅 startTime | duration == null |
| 14.4 | toJson 字段过滤 | 基本字段 | 含 id/distance/status |

### 15. `models/ride_lap_test.dart`（5 用例）

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 15.1 | 含 checkpointPasses | 完整 JSON | lapNumber=2; checkpointPasses.length=1 |
| 15.2 | 缺省 | `{}` | lapNumber=0; checkpointPasses=[] |
| 15.3 | formatted < 1 小时 | duration=65s | "1:05"；8s → "0:08" |
| 15.4 | formatted ≥ 1 小时 | duration=3725s | "1:02:05" |
| 15.5 | 负数 duration | -5 | "0:00" |

### 16. `network/app_response_test.dart`（4 用例）

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 16.1 | 成功响应 | `{flag:true, code:20000, data:{...}}` | isSuccess=true; data!=null |
| 16.2 | 错误响应 | `{flag:false, code:40000, message:"x"}` | isSuccess=false; message="x" |
| 16.3 | 缺 flag 字段 | `{code:20000}` | isSuccess=false |
| 16.4 | AppResponse.error 构造 | msg="oops" | flag=false; message="oops" |

### 17. `widgets/trax_button_test.dart`（4 用例）

| # | 用例 | 输入 | 预期输出 |
|---|------|------|---------|
| 17.1 | filled 渲染文本 + 触发 onPressed | tap "Go" | find.text("Go") 命中；tapped=1 |
| 17.2 | text 工厂传 child | 传 Icon(plus) | find.byKey("plus") 命中 |
| 17.3 | outlined onPressed=null 禁用 | 不传回调 | TextButton.onPressed == null |
| 17.4 | TraxReturnButton 显示返回箭头 | 渲染 | find.byIcon(arrow_back_ios_new) 命中 |

---

## 三、执行命令

```bash
# 后端
cd backend && JAVA_HOME=/opt/homebrew/opt/openjdk@21 mvn test

# Flutter
cd trax_app && flutter test
```

---

## 四、覆盖盲区（建议后续补充）

- 后端：`RideService` / `RaceService` / `TrailService` / `BicycleService` / `UserCheckpointService` 完整单测，以及 `Ride/Race/Trail/Bicycle` Controller 集成测试
- Flutter：`active_ride_service`（涉及 Geolocator/Dio，需 mockito 生成）、登录/主页 widget 测试、`integration_test` 端到端
