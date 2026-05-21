---
marp: true
theme: default
paginate: true
size: 16:9
header: 'TRAX App · 功能概览 / Feature Overview'
footer: '2026-05'
style: |
  section {
    font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
    font-size: 20px;
    padding: 50px 56px 56px;
  }
  h1 { color: #0E7C66; margin-top: 0; }
  h2 { color: #0E7C66; border-bottom: 2px solid #0E7C66; padding-bottom: 4px; margin-top: 0; }
  h3 { color: #1F4D40; }
  table { font-size: 16px; }
  code { background: #f3f3f3; padding: 1px 4px; border-radius: 3px; }

  /* ── 左文右图两栏布局 / Left-text + right-image layout ── */
  .layout {
    display: grid;
    grid-template-columns: minmax(0, 1.22fr) minmax(320px, 0.78fr);
    column-gap: 20px;
    align-items: stretch;
    height: calc(100% - 80px);  /* leave room for h2 */
  }
  /* 两图横排时，给右侧略多空间，避免截图过小 */
  .layout:has(.image-col.row) {
    grid-template-columns: minmax(0, 1.08fr) minmax(420px, 0.92fr);
    column-gap: 22px;
  }
  .text-col {
    min-width: 0;
    overflow: hidden;
  }
  .image-col {
    display: flex;
    flex-direction: column;
    gap: 12px;
    align-items: flex-start;
    justify-content: center;
    width: 100%;
    max-height: 500px;
  }
    /* 右栏图片：自动按预设尺寸等比缩小，不会溢出 / Auto-fit any image to the slot.
      ▶ 单图：<img src="images/xxx.png"/>            （撑满 500px）
     ▶ 多图（默认竖排）：连续放多个 <img>，自动平分高度
        <img src="images/a.png"/>
        <img src="images/b.png"/>
     ▶ 多图横排：在 .image-col 上加 row 类，并排显示
        <div class="image-col row">
          <img src="images/a.png"/>
          <img src="images/b.png"/>
        </div>
     ▶ 注意：用 ![](images/xxx.png) 时前后必须留空行，否则会被当成纯文本。 */
  .image-col img,
  .image-col p > img {
    max-width: 100%;
    min-height: 0;
    width: auto;
    height: auto;
    object-fit: contain;
    border-radius: 12px;
    display: block;
  }
  /* 默认（1 张图）：占满 500 高 */
  .image-col > img,
  .image-col > p > img {
    max-height: 500px;
  }
  /* 2 张图竖排：每张 ≤ 214 高（440 − 12 gap）/2 */
  .image-col:has(> img + img) > img,
  .image-col:has(> p + p) > p > img {
    max-height: 214px;
  }
  /* 3 张图竖排 */
  .image-col:has(> img + img + img) > img,
  .image-col:has(> p + p + p) > p > img {
    max-height: 138px;
  }
  /* 4 张图竖排 */
  .image-col:has(> img + img + img + img) > img,
  .image-col:has(> p + p + p + p) > p > img {
    max-height: 101px;
  }
  /* 横排模式 .image-col.row：图片并排，按自身宽高比缩放，绝不拉伸变形
     ▶ 2 张图时各张最宽 = (100% - 12px gap) / 2
     ▶ 3 张图时各张最宽 = (100% - 24px gap) / 3
     ▶ 高度统一限 440px；最终尺寸取宽/高两者中更紧的那一个 */
  .image-col.row {
    flex-direction: row;
    align-items: center;
    justify-content: flex-start;
  }
  .image-col.row > img,
  .image-col.row > p > img {
    flex: 0 1 auto;
    width: auto;
    height: auto;
    max-height: 440px;
    max-width: calc((100% - 12px) / 2);
    object-fit: contain;
  }
  .image-col.row:has(> img + img + img) > img,
  .image-col.row:has(> p + p + p) > p > img {
    max-width: calc((100% - 24px) / 3);
  }
  /* 截图占位框 / Screenshot placeholder.
     ▶ 用法 1：在 PowerPoint 里直接把图片拖进右栏覆盖此框。
     ▶ 用法 2：在 md 里替换为 <img src="images/your-screenshot.png"/> 即可（无需 style）。
  */
  .img-slot {
    width: 100%;
    height: 440px;
    border: 2px dashed #c0c8c5;
    border-radius: 14px;
    background:
      repeating-linear-gradient(
        45deg,
        #f7faf9 0 12px,
        #eef3f1 12px 24px
      );
    display: flex;
    align-items: center;
    justify-content: center;
    color: #7a8a85;
    font-size: 14px;
    text-align: center;
    padding: 12px;
  }
  .img-slot::before {
    content: '📷  贴图位\A Screenshot here';
    white-space: pre;
    line-height: 1.6;
  }

  .en { color: #4a4a4a; font-size: 0.88em; }
  .tag {
    display: inline-block; background: #E6F4EF; color: #0E7C66;
    padding: 2px 8px; border-radius: 10px; font-size: 13px; margin-right: 4px;
  }

  /* 章节封面页（h1 居中、不需要右侧贴图）/ Section cover */
  section.cover h1 { text-align: center; font-size: 56px; margin-top: 80px; }
  section.cover h2 { border: none; text-align: center; color: #1F4D40; }
  /* 封面页提炼信息：更醒目但不抢标题；中英文等权，行距更紧凑 */
  section.cover .tag {
    display: block;
    width: fit-content;
    margin: 0 0 6px 0;
    padding: 6px 12px;
    border-radius: 12px;
    font-size: 17px;
    font-weight: 520;
    letter-spacing: 0.1px;
    color: #0B6F5B;
    background: linear-gradient(180deg, #EAF8F3 0%, #DDF2EA 100%);
    border: 1px solid #B9DED1;
    box-shadow: 0 1px 0 rgba(14, 124, 102, 0.08);
    line-height: 1.2;
  }
---

<!-- _class: cover -->

# TRAX App 功能概览
## Feature Overview

- 平台 / Platform：Flutter (iOS + Android)
- 地图栈 / Maps：Google Maps + 高德 AMap（按 GPS 自动切换 / region-aware）
- 后端 / Backend：Spring Boot 3 · JDK 21 · WebSocket · Bluetooth · MQTTS
- 坐标系 / Coords：WGS-84 ↔ GCJ-02（AMap 自动转换 / auto-converted）

---

<!-- _class: cover -->

## 目录 / Agenda

1. **Garage** — 车库与车辆档案 / Garage & bike profile
2. **Trail** — 赛道库与采集 / Trail library & recording
3. **Ride** — 骑行模式 / Ride modes
4. **Session** — 历史会话与回放 / Session history & replay

---

<!-- _class: cover -->

# 1. Garage 车库

<span class="tag">车辆管理</span>
<span class="tag">Bike Management</span>

---

## Garage · 主列表 / Main List

<div class="layout">
<div class="text-col">

- **全部电单车 / Bike list**
  <span class="en">Lists all bikes owned by the user</span>
- **车辆概览 / Bike summary**
  <span class="en">Custom name · brand + model · thumbnail</span>
- **新增车辆 / Add bike**
    <span class="en">Add bike → TRAX module inquiry flow</span>
- **管理车辆 / Manage bike**
    <span class="en">Manage bike profile</span>

</div>
<div class="image-col">
<img src="images/garage-list.jpg"/>
</div>
</div>

---

## Garage · 新增车辆流程 / Add-Bike Flow

<div class="layout">
<div class="text-col">

- **TRAX 模块识别 / Module inquiry**
   <span class="en">Asks whether a TRAX smart module is installed</span>
- **可用设备扫描 / Available device scan (BLE)**
   <span class="en">Lists nearby pairable hardware</span>
- **车型选择器 / Model picker**
   <span class="en">Built-in brand library: BONNELL · E_Ride · RERODE · RISTRETTO · Sur-Ron · Talaria</span>
- **零部件 / 规格编辑 / Parts & spec editor**
   <span class="en">Motor · controller · battery · tyres can be hand-tuned</span>

</div>
<div class="image-col">
<img src="images/garage-AddBike.jpg"/>
</div>
</div>

---

## Garage · 车辆详情 / Bike Profile

<div class="layout">
<div class="text-col">

- **Module 连接状态 / Connection Status**
<span class="en">TRAX module connection status</span>

- **规格 / Specifications**
<span class="en">Motor · controller · battery, with "Certified" badge</span>

- **统计 / Statistics**
<span class="en">Total Rides · Total Distance · Last Ride</span>

- **管理 / Actions**
<span class="en">Ride history · Motor settings · Remove bike</span>

</div>
<div class="image-col">
<img src="images/bike profile.jpg"/>
</div>
</div>

---

<!-- _class: cover -->

# 2. Trail 赛道

<span class="tag">公共赛道库 · 赛道录制 · 赛道管理</span>
<span class="tag">Public library · Trail recording · Trail management</span>

---

## Trail · 列表页 / List

<div class="layout">
<div class="text-col">

- **赛道库 / Trail library**
  <span class="en">Public trails + your own private trails</span>
- **赛道卡片 / Trail card**
  <span class="en">Thumbnail · name · location · distance</span>
- **Next steps**
  <span class="en">Personal lib</span>
  <span class="en">Trails show on map</span>

</div>
<div class="image-col">
<img src="images/trail list.jpg"/>
</div>
</div>

---

## Trail · 录制 / Recording

<div class="layout">
<div class="text-col">

- **实时记录 / Ride recording**
  <span class="en">Live GPS polyline following your ride</span>
- **实时记录(Lap) / Ride recording(Lap)**
  <span class="en">Live GPS polyline following your ride, auto finish when the trail is a lap</span>
- **地图取点(Lap) / Pick points(Lap)**
  <span class="en">Pick points on the map to auto-organize a lap</span>

</div>
<div class="image-col">
<img src="images/trail recording.jpg"/>
</div>
</div>

---

## Trail · 详情 / Detail

<div class="layout">
<div class="text-col">

- **路径信息 / Trail info**
  <span class="en">Auto-fits the whole route with chaser dot</span>
  <span class="en">Custom start & finish markers</span>
- **个性化检查点 / Personal checkpoints**
  <span class="en">Up to 4 per-user checkpoints per trail</span>
- **Next steps**
  <span class="en">Ranking of the trail</span>
  <span class="en">Upcoming events</span>

</div>
<div class="image-col">
<img src="images/trail detail.jpg"/>
</div>
</div>

---

<!-- _class: cover -->

# 3. Ride 骑行

<span class="tag">六种模式 · 地图自适应 · 状态实时同步</span>
<span class="tag">Six modes · Region-aware maps · Realtime state sync</span>

---

## Ride · 六大模式 / Six Modes

<div class="layout">
<div class="text-col">

| # | 模式 / Mode | 说明 / Description                         | Single or Multiple|
|---|-------------|------------------------------------------|:------------:|
| 1 | Free Ride   | 自由骑 / Free ride with track & stats      |Single|
| 2 | Lap Timer   | 单人刷圈 / Solo lap practice               |Single|
| 3 | Host Laps   | 群组刷圈(按圈速) / Group lap timer challenge|Multiple|
| 4 | Host Race   | 群组比赛 / Group race challenge            |Multiple|
| 5 | Join Game   | 加入比赛 / Join an existing game           |Multiple|
| 6 | Watch Game  | 旁观直播 / Spectate live game              |Multiple|

</div>
<div class="image-col">
<img src="images/ride home.jpeg"/>
</div>
</div>

---

## Ride · Free Ride

<div class="layout">
<div class="text-col">

- **全屏地图 / Full-screen map**
  <span class="en">Full-screen map with heading marker</span>
- **实时统计 / Live stats**
  <span class="en">Routes · Duration · Distance · Avg/Max Speed</span>
- **控制条 / Controls**
  <span class="en">Start · Pause · Resume · Finish</span>

</div>
<div class="image-col">
<img src="images/Free ride.jpeg"/>
</div>
</div>

---

## Ride · Lap Timer

<div class="layout">
<div class="text-col">

- **路径选择 / Trail picker**
   <span class="en">Choose existing trail</span>
- **设置CP / CP configuration**
   <span class="en">Add up to 4 checkpoints on the spot</span>
- **计时页 / Timer page**
   - <span class="en">Timer starts when you cross the start point</span>
   - <span class="en">Lap splits when crossing each checkpoint </span>
   - <span class="en">Lap finish when cross the start point </span>
   - <span class="en">Game finishes when the expected laps finish</span>
- **活动汇总 / Event summary**

</div>
<div class="image-col row">
<img src="images/Lap timer.jpeg"/>
<img src="images/Lap timer page.jpeg"/>
</div>
</div>

---

## Ride · Host Race / Host Laps

<div class="layout">
<div class="text-col">

- **创建比赛 / Create Laps/Race**
  - 关联 trail（必选）/ Trail (required)
  - 公开 vs 仅邀请 / Public vs invite-only
  - 圈数 / Lap count
  - 计划开始时间 / Scheduled start time
- **邀请码 / Invitation code**
  <span class="en">Invite code generated for sharing</span>

</div>
<div class="image-col row">
<img src="images/host laps.jpeg"/>
<img src="images/host race.jpeg"/>
</div>
</div>

---

## Ride · Join Game

<div class="layout">
<div class="text-col">

- **赛事列表 / Event list**
  <span class="en">Joinable public races/laps</span>
- **邀请码加入 / Invitation code**
  <span class="en">Invitation code for private games</span>
- **赛事详情 / Event detail**
  <span class="en">Trail preview, game type, participants, status</span>
- **参赛或观看 / Join or Watch**
  <span class="en">You can either join the game or watch the game</span>

</div>
<div class="image-col">
<img src="images/Join game.jpeg"/>
</div>
</div>

---

## Ride · Race Tracking 比赛中

<div class="layout">
<div class="text-col">

- **地图实时显示 / Map live show**
  <span class="en">Live map shows self + every opponent</span>
- **聚焦骑手 / Focus**
  <span class="en">Hide/show any participants</span>
- **实时排名 / Live ranking**
  <span class="en">Live ranking based on the position of each participant</span>

</div>
<div class="image-col">
<img src="images/race tracking.jpg"/>
</div>
</div>

---

## Ride · Laps Tracking 比赛中

<div class="layout">
<div class="text-col">

- **地图实时显示 / Map live show**
  <span class="en">Live map shows self + every opponent</span>
- **聚焦骑手 / Focus**
  <span class="en">Hide/show any participants</span>
- **实时排名 / Live ranking**
  <span class="en">Live ranking based on the best lap time of each participant</span>
- **圈数信息 / Laps info**
  <span class="en">My personal lap timer</span>

</div>
<div class="image-col">
<img src="images/laps tracking.jpg"/>
</div>
</div>

---

## Ride · Watch Game 观赛

<div class="layout">
<div class="text-col">

- **纯观众模式 / Spectator mode**
  <span class="en">Watch live positions & rankings of an ongoing game</span>

</div>
<div class="image-col">
<img src="images/Watch game.jpg"/>
</div>
</div>

---

## Ride · Race Replay 赛后回放

<div class="layout">
<div class="text-col">

- **时间轴 / Scrubber**
  <span class="en">Timeline scrubber: seek + variable speed</span>
- **赛后回放 / Replay**
  <span class="en">Replay the full game</span>

</div>
<div class="image-col">
<img src="images/replay.jpg"/>
</div>
</div>

---

<!-- _class: cover -->

# 4. Session 会话

<span class="tag">个人骑行历史 · 多类型筛选 · 详情与回放</span>
<span class="tag">Personal ride history · Multi-type filter · Detail & replay</span>

---

## Session · 列表 / List

<div class="layout">
<div class="text-col">

- **骑行记录 / ride list**
  <span class="en">All rides of the current user</span>
  <span class="en">Filter chips</span>

</div>
<div class="image-col">
<img src="images/session.jpg"/>
</div>
</div>

---

## Session · Free ride Detail

<div class="layout">
<div class="text-col">

- **地图轨迹 / Map polyline**
  <span class="en">Red polyline with start & finish point</span>
- **数据卡 / Stats**：
  <span class="en">Riding info</span>
- **回放与删除 / Replay & delete**
  <span class="en">Replay the full activity</span>

</div>
<div class="image-col">
<img src="images/free ride session.jpg"/>
</div>
</div>

---

## Session · Lap Timer Detail

<div class="layout">
<div class="text-col">

- **地图轨迹 / Map polyline**
  <span class="en">Red polyline with start & finish point</span>
- **数据卡 / Stats**：
  <span class="en">Riding info</span>
- **圈数片段 / Lap splits**：
  <span class="en">Information of each lap with all checkpoints</span>
  <span class="en">Best lap time</span>
- **回放与删除 / Replay & delete**
  <span class="en">Replay the full activity</span>

</div>
<div class="image-col">
<img src="images/lap timer session.jpg"/>
</div>
</div>

---

## Session · Race Detail

<div class="layout">
<div class="text-col">

- **场地 / Trail**
  <span class="en">Trail of the event</span>
- **比赛信息 / Race info**：
  <span class="en">Information of the event</span>
- **冠军榜 / Leaderboard**：
  <span class="en">Final ranking of the whole event</span>
  <span class="en">Final time & gap of each participant</span>
- **圈数榜 / Lap board**：
  <span class="en">Position & Time of each lap for all participants</span>
  <span class="en">Final time & gap of each participant</span>
- **回放与删除 / Replay & delete**
  <span class="en">Replay the full activity</span>

</div>
<div class="image-col">
<img src="images/race session.jpg"/>
</div>
</div>

---

## Session · Laps Detail

<div class="layout">
<div class="text-col">

- **场地 / Trail**
  <span class="en">Trail of the event</span>
- **比赛信息 / Race info**：
  <span class="en">Information of the event</span>
- **冠军榜 / Leaderboard**：
  <span class="en">Final ranking of the whole event</span>
  <span class="en">Best time & diff of each participant</span>
- **圈数片段 / My Laps**：
  <span class="en">Information of each lap with all checkpoints</span>
  <span class="en">Best lap time</span>
- **回放与删除 / Replay & delete**
  <span class="en">Replay the full activity</span>

</div>
<div class="image-col">
<img src="images/laps session.jpg"/>
</div>
</div>

---

## 后续处理 / Next Steps

<div class="layout">
<div class="text-col">

- Connect with trax express module
- Test the signal effect of module
- Professional statistics of bike using module data
- More fun ways to play
- UI/UX design
- Bugfix

---

<!-- _class: cover -->

# Thanks · 谢谢观看

**TRAX** — Garage · Trail · Ride · Session

构建一站式电单车骑行 · 训练 · 竞速体验
<span class="en">An all-in-one e-bike ride · training · racing experience</span>
