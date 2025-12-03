#!/bin/bash
# ------------------------------------------
# Shutdown script for myapp.jar and start.sh
# ------------------------------------------

APP_DIR=/home/appuser/projects/myapp
PID_FILE="$APP_DIR/daemon.pid"
JAVA_PID_FILE="$APP_DIR/java.pid"
STATE_FILE="$APP_DIR/app.state"
APP_NAME="myapp.jar"

# 停止守护脚本
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 $PID 2>/dev/null; then
        echo "Stopping start.sh (PID=$PID)..."
        kill $PID
    else
        echo "start.sh PID $PID not running."
    fi
    rm -f "$PID_FILE"
fi

# 停止 myapp.jar
if [ -f "$JAVA_PID_FILE" ]; then
    PID=$(cat "$JAVA_PID_FILE")
    if kill -0 $PID 2>/dev/null; then
        echo "Stopping $APP_NAME (PID=$PID)..."
        kill $PID
    else
        echo "$APP_NAME PID $PID not running."
    fi
    rm -f "$JAVA_PID_FILE"
fi

# 清理状态文件
rm -f "$STATE_FILE"

echo "Shutdown complete."