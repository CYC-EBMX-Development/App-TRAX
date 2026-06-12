#!/usr/bin/env bash
# Shared release naming helper.
#
# Rules:
# - Base name: trax-test-YYMMDD-N where N is at least 2 digits (01..99, 100+)
# - APK/IPA share the same N for the same code snapshot
# - If code snapshot changes on the same day, allocate the next N
#
# Usage:
#   source ./scripts/release_naming.sh
#   trax_release_resolve_base "$APP_ROOT"
#   echo "$TRAX_RELEASE_NAME_BASE"
#
# Important: this file is sourced by other scripts, so it must not change
# shell options (set -e/-u/-o pipefail) in the caller's shell.

trax_release_date_stamp() {
  TZ=Asia/Shanghai date +%y%m%d
}

trax_release_prefix() {
  local date_stamp
  date_stamp="$(trax_release_date_stamp)"
  echo "trax-test-${date_stamp}"
}

trax_release_seq_str() {
  local seq_int
  seq_int="$1"
  if (( seq_int < 100 )); then
    printf "%02d" "$seq_int"
  else
    printf "%d" "$seq_int"
  fi
}

trax_release_snapshot_id() {
  local app_root
  app_root="$1"

  if ! git -C "$app_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Fallback for non-git dirs.
    echo "nogit:$(date +%s)"
    return 0
  fi

  local head tracked_hash untracked_hash
  head="$(git -C "$app_root" rev-parse HEAD 2>/dev/null || echo nohead)"
  tracked_hash="$(git -C "$app_root" diff --binary HEAD -- . | shasum | awk '{print $1}')"

  # Include content hash for untracked files so local code edits are reflected.
  local -a untracked_files
  untracked_files=()
  while IFS= read -r line; do
    untracked_files+=("$line")
  done < <(git -C "$app_root" ls-files --others --exclude-standard)
  if (( ${#untracked_files[@]} == 0 )); then
    untracked_hash="none"
  else
    untracked_hash="$({
      for f in "${untracked_files[@]}"; do
        if [[ -f "$app_root/$f" ]]; then
          shasum "$app_root/$f"
        else
          printf '%s  %s\n' "missing" "$f"
        fi
      done
    } | shasum | awk '{print $1}')"
  fi

  echo "${head}:${tracked_hash}:${untracked_hash}"
}

trax_release_remote_max() {
  local prefix
  prefix="$1"
  local max_remote
  max_remote=0

  if [[ -n "${SSH_USER:-}" && -n "${SERVER_IP:-}" ]] && command -v ssh >/dev/null 2>&1; then
    max_remote="$(ssh -o ConnectTimeout=10 "${SSH_USER}@${SERVER_IP}" \
      "ls /var/www/trax-download/ 2>/dev/null | grep -oE '^${prefix}-[0-9]+\\.apk$' | sed -E 's/.*-([0-9]+)\\.apk/\\1/' | sort -n | tail -1" \
      2>/dev/null || true)"
    max_remote="${max_remote:-0}"
  fi

  echo "$max_remote"
}

trax_release_local_max() {
  local app_root prefix
  app_root="$1"
  prefix="$2"

  local max_local
  max_local=0
  local f base n
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    base="$(basename "$f")"
    n="$(echo "$base" | sed -E 's/.*-([0-9]+)\.(apk|ipa)$/\1/')"
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    if (( 10#$n > max_local )); then
      max_local=$((10#$n))
    fi
  done < <(find "$app_root/build/dist" -maxdepth 1 -type f \
    \( -name "${prefix}-*.apk" -o -name "${prefix}-*.ipa" \) 2>/dev/null)
  echo "$max_local"
}

trax_release_resolve_base() {
  local app_root
  app_root="$1"

  mkdir -p "$app_root/build/dist"

  local date_stamp prefix snapshot map_file seq found
  date_stamp="$(trax_release_date_stamp)"
  prefix="trax-test-${date_stamp}"
  snapshot="$(trax_release_snapshot_id "$app_root")"
  map_file="$app_root/build/dist/.release-map-${date_stamp}.tsv"
  touch "$map_file"

  found="$(awk -F '\t' -v s="$snapshot" '$1==s {print $2; exit}' "$map_file" || true)"
  if [[ -n "$found" ]]; then
    seq="$found"
  else
    local max_local max_remote max_map max_all
    max_local="$(trax_release_local_max "$app_root" "$prefix")"
    max_remote="$(trax_release_remote_max "$prefix")"
    # Also consider seqs already allocated in today's map file so two fast-fire
    # releases with different snapshots cannot both pick the same seq (and one
    # overwrite the other's apk/ipa). Without this, only files on disk/server
    # are consulted, so a second resolve_base run before the first build's
    # artifacts have landed will collide.
    max_map="$(awk -F '\t' '{print $2+0}' "$map_file" 2>/dev/null | sort -n | tail -1)"
    max_map="${max_map:-0}"
    local m1 m2
    m1=$(( 10#${max_local:-0} > 10#${max_remote:-0} ? 10#${max_local:-0} : 10#${max_remote:-0} ))
    m2=$(( m1 > 10#${max_map:-0} ? m1 : 10#${max_map:-0} ))
    max_all="$m2"
    seq="$((max_all + 1))"
    printf '%s\t%s\n' "$snapshot" "$seq" >> "$map_file"
  fi

  local seq_str
  seq_str="$(trax_release_seq_str "$seq")"

  TRAX_RELEASE_DATE_STAMP="$date_stamp"
  TRAX_RELEASE_PREFIX="$prefix"
  TRAX_RELEASE_SEQ_INT="$seq"
  TRAX_RELEASE_SEQ_STR="$seq_str"
  TRAX_RELEASE_NAME_BASE="${prefix}-${seq_str}"
}
