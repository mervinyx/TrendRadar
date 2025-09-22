#!/bin/bash
set -e

# 检查配置文件
if [ ! -f "/app/config/config.yaml" ] || [ ! -f "/app/config/frequency_words.txt" ]; then
    echo "❌ 配置文件缺失"
    exit 1
fi

# 保存环境变量
env >> /etc/environment

case "${RUN_MODE:-cron}" in
"once")
    echo "🔄 单次执行"
    exec /usr/local/bin/python main.py
    ;;
"cron")
    # 生成 crontab
    echo "${CRON_SCHEDULE:-*/30 * * * *} cd /app && /usr/local/bin/python main.py" > /tmp/crontab
    
    echo "📅 生成的crontab内容:"
    cat /tmp/crontab

    if ! /usr/local/bin/supercronic -test /tmp/crontab; then
        echo "❌ crontab格式验证失败"
        exit 1
    fi

    # 将 supercronic 放到后台执行
    echo "⏰ 启动 supercronic (后台运行)"
    /usr/local/bin/supercronic -passthrough-logs /tmp/crontab &
    SUPERCRONIC_PID=$!

    cleanup() {
        set +e
        if [ -n "${IMMEDIATE_PID:-}" ] && kill -0 "${IMMEDIATE_PID}" 2>/dev/null; then
            kill "${IMMEDIATE_PID}" 2>/dev/null || true
        fi
        if [ -n "${HTTP_PID:-}" ] && kill -0 "${HTTP_PID}" 2>/dev/null; then
            kill "${HTTP_PID}" 2>/dev/null || true
        fi
        if [ -n "${SUPERCRONIC_PID:-}" ] && kill -0 "${SUPERCRONIC_PID}" 2>/dev/null; then
            kill "${SUPERCRONIC_PID}" 2>/dev/null || true
        fi
        wait
    }
    trap cleanup EXIT INT TERM

    start_http_server() {
        echo "🌐 启动内置 Web 服务器以提供报告访问和响应健康检查..."
        (cd /app/output && python3 -m http.server "${PORT:-8080}") &
        HTTP_PID=$!
    }

    start_http_server

    # 立即执行一次（如果配置了）——在 HTTP 服务启动后触发，确保端口可用
    if [ "${IMMEDIATE_RUN:-false}" = "true" ]; then
        echo "▶️ 立即执行一次 (后台运行)"
        /usr/local/bin/python /app/main.py &
        IMMEDIATE_PID=$!
    fi

    # 等待后台任务，避免产生僵尸进程
    if [ -n "${IMMEDIATE_PID:-}" ]; then
        set +e
        wait "${IMMEDIATE_PID}"
        IMMEDIATE_STATUS=$?
        set -e
        if [ "${IMMEDIATE_STATUS}" -ne 0 ]; then
            echo "⚠️ 立即执行任务异常退出 (状态码: ${IMMEDIATE_STATUS})，继续等待 HTTP 服务。"
        fi
    fi

    while true; do
        set +e
        wait "${HTTP_PID}"
        HTTP_STATUS=$?
        set -e
        if [ "${HTTP_STATUS}" -eq 0 ]; then
            echo "ℹ️ HTTP 服务已正常退出。"
            break
        fi
        echo "❌ HTTP 服务异常退出 (状态码: ${HTTP_STATUS})，正在尝试重启..."
        start_http_server
    done
    ;;
*)
    exec "$@"
    ;;
esac
