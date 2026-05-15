#!/usr/bin/env bash
# TRAX Android 真机调试一键脚本（绕过 SM-A165F 上 USB streamed install 的 bug）
#
# 用法：
#   scripts/run_android.sh                  # 自动检测：如已建立 WiFi adb 则跑 flutter run
#   scripts/run_android.sh setup            # 用 USB 临时连一下，开启 WiFi adb（5555）
#   scripts/run_android.sh install          # 仅安装当前 build 的 app-debug.apk
#   scripts/run_android.sh run              # flutter run（默认 debug）
#   scripts/run_android.sh build-install    # flutter build apk + 安装
#   scripts/run_android.sh logcat           # tail App 日志
#
# 环境变量：
#   PHONE_IP=192.168.31.79  默认 WiFi IP（手机断网/换网后请覆盖此变量）
#   USB_SERIAL=R9AS8J5AQYW  USB 临时连接时的序列号
#   PKG=com.trax.trax_app

set -e

PHONE_IP="${PHONE_IP:-192.168.31.79}"
USB_SERIAL="${USB_SERIAL:-R9AS8J5AQYW}"
PKG="${PKG:-com.trax.trax_app}"
DEVICE="${PHONE_IP}:5555"
# 加载 ~/trax-deploy.env（含 AMAP_KEY 等敏感配置；不入 git）
if [[ -f "$HOME/trax-deploy.env" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/trax-deploy.env"
fi
# 真机/外网联调默认走生产后端；用 API_BASE_URL=... 环境变量可覆盖
API_BASE_URL="${API_BASE_URL:-http://43.99.48.204/api}"
AMAP_KEY="${AMAP_KEY:-}"

# 脚本目录 → 项目根
PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APK="${PROJ_DIR}/build/app/outputs/flutter-apk/app-debug.apk"

color() { printf "\033[1;36m[run_android]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[run_android]\033[0m %s\n" "$*"; }
err()   { printf "\033[1;31m[run_android]\033[0m %s\n" "$*" 1>&2; }

ensure_adb_alive() {
  if ! pgrep -f "adb fork-server" >/dev/null 2>&1; then
    adb start-server >/dev/null 2>&1 || true
  fi
}

wifi_connected() {
  ensure_adb_alive
  adb devices | awk -v d="$DEVICE" '$1==d && $2=="device"{found=1} END{exit !found}'
}

usb_device_state() {
  ensure_adb_alive
  adb devices | awk -v s="$USB_SERIAL" '$1==s{print $2; found=1} END{if(!found) print "missing"}'
}

connect_wifi() {
  ensure_adb_alive
  if wifi_connected; then return 0; fi
  color "尝试 WiFi 连接 ${DEVICE} ..."
  adb connect "${DEVICE}" >/dev/null 2>&1 || true
  sleep 1
  if wifi_connected; then
    color "WiFi adb 已连接：${DEVICE}"
    return 0
  fi
  warn "WiFi 连不上 ${DEVICE}，需要先用 USB 临时连一下激活 5555 端口"
  return 1
}

setup_wifi_via_usb() {
  ensure_adb_alive
  local state
  state="$(usb_device_state)"
  if [ "$state" = "missing" ]; then
    err "USB 看不到手机（serial=${USB_SERIAL}）。请用 Type-C 线直插 Mac，并解锁屏幕。"
    exit 1
  fi
  if [ "$state" = "offline" ]; then
    warn "USB 设备处于 offline，执行 adb reconnect offline 修复"
    adb reconnect offline >/dev/null 2>&1 || true
    sleep 3
    state="$(usb_device_state)"
  fi
  if [ "$state" = "unauthorized" ]; then
    err "USB 设备 unauthorized，请在手机上点 '允许 USB 调试'"
    exit 1
  fi
  if [ "$state" != "device" ]; then
    err "USB 设备状态异常：$state"
    exit 1
  fi

  # 读取手机 WiFi IP（用户可能换网了）
  local detected_ip
  detected_ip="$(adb -s "${USB_SERIAL}" shell ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)"
  if [ -n "$detected_ip" ] && [ "$detected_ip" != "$PHONE_IP" ]; then
    warn "手机当前 IP 是 ${detected_ip}，与默认 ${PHONE_IP} 不一致；这次使用 ${detected_ip}"
    PHONE_IP="$detected_ip"
    DEVICE="${PHONE_IP}:5555"
  fi

  color "切换 adbd 到 TCP 模式（5555）"
  adb -s "${USB_SERIAL}" tcpip 5555 >/dev/null
  sleep 3
  adb connect "${DEVICE}" >/dev/null
  sleep 1
  if wifi_connected; then
    color "WiFi adb 就绪：${DEVICE}"
    color "提示：现在可以拔掉 USB 线，后续命令通过 WiFi 完成。"
  else
    err "WiFi 仍未连接成功，请检查手机与 Mac 是否在同一 WiFi、手机有没有进入飞行模式"
    exit 1
  fi
}

ensure_wifi() {
  if connect_wifi; then return 0; fi
  setup_wifi_via_usb
}

install_apk() {
  ensure_wifi
  if [ ! -f "$APK" ]; then
    err "APK 不存在：$APK；请先执行 build-install 或 flutter build apk --debug"
    exit 1
  fi
  color "安装 APK → ${DEVICE}"
  if ! adb -s "${DEVICE}" install -r "$APK"; then
    warn "升级安装失败，可能是 versionCode 冲突；尝试卸载后重装"
    adb -s "${DEVICE}" uninstall "${PKG}" >/dev/null 2>&1 || true
    adb -s "${DEVICE}" install "$APK"
  fi
  color "启动 App"
  adb -s "${DEVICE}" shell monkey -p "${PKG}" -c android.intent.category.LAUNCHER 1 >/dev/null
}

build_and_install() {
  ensure_wifi
  "$PROJ_DIR/scripts/patch_amap_plugins.sh" || true
  color "flutter build apk --debug --dart-define=API_BASE_URL=${API_BASE_URL}"
  (cd "$PROJ_DIR" && flutter build apk --debug --dart-define=API_BASE_URL="${API_BASE_URL}" --dart-define=AMAP_KEY="${AMAP_KEY}" --dart-define=AMAP_ANDROID_SDK_KEY="${AMAP_ANDROID_SDK_KEY:-}" --dart-define=AMAP_IOS_SDK_KEY="${AMAP_IOS_SDK_KEY:-}")
  install_apk
}

flutter_run() {
  ensure_wifi
  "$PROJ_DIR/scripts/patch_amap_plugins.sh" || true
  color "flutter run -d ${DEVICE} --dart-define=API_BASE_URL=${API_BASE_URL}"
  cd "$PROJ_DIR" && exec flutter run -d "${DEVICE}" --dart-define=API_BASE_URL="${API_BASE_URL}" --dart-define=AMAP_KEY="${AMAP_KEY}" --dart-define=AMAP_ANDROID_SDK_KEY="${AMAP_ANDROID_SDK_KEY:-}" --dart-define=AMAP_IOS_SDK_KEY="${AMAP_IOS_SDK_KEY:-}"
}

logcat_app() {
  ensure_wifi
  local pid
  pid="$(adb -s "${DEVICE}" shell pidof "${PKG}" | tr -d '\r')"
  if [ -z "$pid" ]; then
    err "App 未在运行（pkg=${PKG}）"
    exit 1
  fi
  color "tail logcat（pid=${pid}），Ctrl+C 退出"
  exec adb -s "${DEVICE}" logcat --pid="$pid"
}

cmd="${1:-run}"
case "$cmd" in
  setup)         setup_wifi_via_usb ;;
  install)       install_apk ;;
  build-install) build_and_install ;;
  run)           flutter_run ;;
  logcat)        logcat_app ;;
  status)
    ensure_adb_alive
    echo "USB:   $(usb_device_state) (serial=$USB_SERIAL)"
    echo "WiFi:  $(wifi_connected && echo device || echo disconnected) (${DEVICE})"
    ;;
  *)
    err "未知命令：$cmd"
    echo "用法：$0 [setup|install|build-install|run|logcat|status]"
    exit 2
    ;;
esac
