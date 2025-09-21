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

    # 立即执行一次（如果配置了）
    if [ "${IMMEDIATE_RUN:-false}" = "true" ]; then
        echo "▶️ 立即执行一次"
        /usr/local/bin/python main.py
    fi

    # 在前台启动一个简单的 http 服务器，用于响应健康检查和提供报告访问
    echo "🌐 启动内置 Web 服务器以提供报告访问和响应健康检查..."
    cd /app/output
    exec python3 -m http.server "${PORT:-8080}"
    ;;
*)
    exec "$@"
    ;;
esac