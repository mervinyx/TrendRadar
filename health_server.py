#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
健康检查服务器 - 用于满足 Zeabur 平台的 Web 服务期望
"""

import os
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health' or self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            status = {
                "status": "healthy",
                "service": "TrendRadar",
                "timestamp": datetime.now().isoformat(),
                "uptime": time.time() - start_time
            }
            
            self.wfile.write(str(status).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # 禁用默认日志输出
        pass


def start_health_server():
    """启动健康检查服务器"""
    port = int(os.environ.get('PORT', 8080))
    server = HTTPServer(('0.0.0.0', port), HealthHandler)
    print(f"🏥 健康检查服务器启动在端口 {port}")
    server.serve_forever()


# 记录启动时间
start_time = time.time()

if __name__ == "__main__":
    # 在后台线程启动健康检查服务器
    health_thread = threading.Thread(target=start_health_server, daemon=True)
    health_thread.start()
    
    # 导入并运行主程序
    from main import main
    
    # 如果是 cron 模式，启动定时任务
    run_mode = os.environ.get('RUN_MODE', 'cron')
    if run_mode == 'cron':
        print("🔄 启动定时任务模式...")
        # 这里应该启动 supercronic，但在 Zeabur 环境下我们需要保持进程运行
        while True:
            try:
                main()
                print(f"✅ 任务执行完成，等待下次执行...")
                # 解析 cron 表达式，这里简化为30分钟间隔
                time.sleep(30 * 60)  # 30分钟
            except Exception as e:
                print(f"❌ 任务执行出错: {e}")
                time.sleep(60)  # 出错后等待1分钟再重试
    else:
        # 单次执行模式
        main()
        # 保持健康检查服务器运行
        while True:
            time.sleep(60)