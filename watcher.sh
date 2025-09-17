#!/bin/bash
set -e

CONFIG_FILE="/config/fake115uploader.json"
processed_dirs=()  # 已处理的目录集合

# 如果配置文件不存在，用环境变量生成
if [ ! -f "$CONFIG_FILE" ]; then
    if [ -z "$COOKIE_115" ]; then
        echo "❌ 未检测到 COOKIE_115 环境变量，请在 docker-compose.yml 中设置"
        exit 1
    fi

    cat > "$CONFIG_FILE" <<EOF
{
    "cookies": "$COOKIE_115"
}
EOF
    echo "✅ 已生成配置文件 $CONFIG_FILE"
fi

# 日志记录函数
log_success() {
    local type="$1"     # file / dir
    local name="$2"     # 文件/文件夹名
    local log_file="/config/upload.log"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # 防止重复
    if tail -n 10 "$log_file" 2>/dev/null | grep -q "  $name"; then
        return
    fi

    {
        echo "===== 上传任务完成 $timestamp ====="
        if [ "$type" = "file" ]; then
            echo "成功上传文件："
            echo "  $name"
        else
            echo "成功上传文件夹："
            echo "  $name"
        fi
        echo ""
    } >> "$log_file"

    # 保留最近 7 天 + 最多 1000 行
    if [ -f "$log_file" ]; then
        local cutoff=$(date -d "7 days ago" "+%Y-%m-%d %H:%M:%S")
        awk -v cutoff="$cutoff" '
            /^===== 上传任务完成 / {
                ts = substr($0, 14, 19);
                if (ts >= cutoff) keep=1; else keep=0
            }
            keep {print}
        ' "$log_file" > "$log_file.tmp" && mv "$log_file.tmp" "$log_file"

        local lines=$(wc -l < "$log_file")
        if [ "$lines" -gt 1000 ]; then
            tail -n 1000 "$log_file" > "$log_file.tmp" && mv "$log_file.tmp" "$log_file"
        fi
    fi
}

# 通用上传函数
upload_path() {
    local target="$1"
    local is_dir="$2"   # 1=目录，0=文件
    local TMP_LOG=$(mktemp)

    if [ "$is_dir" -eq 1 ]; then
        echo "📂 开始递归上传文件夹: $target"
        CMD=(/usr/local/bin/fake115uploader -u -recursive -l "$CONFIG_FILE" -c "${CID:-0}" "$target")
    else
        echo "📤 检测到新文件: $target，开始上传..."
        CMD=(/usr/local/bin/fake115uploader -u -l "$CONFIG_FILE" -c "${CID:-0}" "$target")
    fi

    "${CMD[@]}" 2>&1 | stdbuf -oL awk '{print; fflush()}' | while IFS= read -r line; do
        echo "$line" >> "$TMP_LOG"

        if [[ "$line" =~ "%" ]] || [[ "$line" =~ "ETA" ]] || [[ "$line" =~ "KiB" ]] || [[ "$line" =~ "MiB" ]]; then
            continue
        fi

        echo "$line"
        if [[ "$line" =~ "普通模式上传文件" ]]; then
            echo "⏳ 普通上传中...（请稍候）"
        fi
    done

    # === 解析上传结果 ===
    succ_files=$(awk '/上传成功的文件/{flag=1; next} /上传失败的文件/{flag=0} flag' "$TMP_LOG")
    fail_files=$(awk '/上传失败的文件/{flag=1; next} /保存上传进度/{flag=0} flag' "$TMP_LOG")

    real_fail_count=0
    if [ -n "$fail_files" ]; then
        while IFS= read -r f; do
            if [ -n "$f" ] && ! echo "$succ_files" | grep -q "$f"; then
                real_fail_count=$((real_fail_count+1))
            fi
        done <<< "$fail_files"
    fi

    # === 判断逻辑 ===
    if [ "$real_fail_count" -eq 0 ]; then
        if [ "$is_dir" -eq 1 ]; then
            echo "✅ 文件夹上传完成: $target"
            if [ "${AUTO_DELETE:-false}" = "true" ]; then
                echo "🗑 删除本地文件夹: $target"
                log_success "dir" "$(basename "$target")"
                rm -rf "$target"
            else
                echo "⚠️ 保留本地文件夹（AUTO_DELETE 未启用）: $target"
                log_success "dir" "$(basename "$target")"
            fi
        else
            echo "✅ 上传成功: $target"
            if [ "${AUTO_DELETE:-false}" = "true" ]; then
                echo "🗑 删除本地文件: $target"
                log_success "file" "$(basename "$target")"
                rm -f "$target"
            else
                echo "⚠️ 保留本地文件（AUTO_DELETE 未启用）: $target"
                log_success "file" "$(basename "$target")"
            fi
        fi
    else
        if [ "$is_dir" -eq 1 ]; then
            echo "❌ 文件夹上传失败或部分失败: $target"
            echo "⚠️ 目录将保留以供检查"
        else
            echo "❌ 上传失败: $target"
        fi
    fi

    rm -f "$TMP_LOG"
}

# 检查目录是否稳定
wait_for_stable_and_upload() {
    local dir="$1"
    echo "📂 检测到新文件夹: $dir，等待拷贝完成..."

    local last_count=-1
    local last_size=-1
    while true; do
        sleep 5
        local count=$(find "$dir" -type f | wc -l)
        local size=$(du -sb "$dir" | awk '{print $1}')

        if [ "$count" -eq "$last_count" ] && [ "$size" -eq "$last_size" ]; then
            echo "✅ 检测到目录 $dir 已稳定"
            break
        fi
        last_count=$count
        last_size=$size
    done

    upload_path "$dir" 1
}

echo "📂 正在监控 /data 目录，有新文件或文件夹会自动上传到 115 (CID=${CID:-0})"

# 开始监控
inotifywait -m -r -e close_write,moved_to,create /data | while read -r dir action file; do
    FILEPATH="$dir$file"

    if [[ "$FILEPATH" == *".swp" ]] || [[ "$FILEPATH" == *".part" ]]; then
        continue
    fi

    if [ -d "$FILEPATH" ]; then
        processed_dirs+=("$FILEPATH")
        wait_for_stable_and_upload "$FILEPATH" &
        continue
    fi

    if [ -f "$FILEPATH" ]; then
        skip=false
        for d in "${processed_dirs[@]}"; do
            if [[ "$FILEPATH" == "$d"* ]]; then
                skip=true
                break
            fi
        done
        if [ "$skip" = true ]; then
            echo "⏭ 跳过文件(属于已上传目录): $FILEPATH"
            continue
        fi

        upload_path "$FILEPATH" 0
    fi
done
