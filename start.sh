#!/bin/bash
# ------------------------------------------
# Start script for myapp.jar
# Supports optional URL parameter, defaults to URL_A
# Runs in background, separates daemon and Java logs
# ------------------------------------------

APP_NAME=myapp.jar
APP_DIR=/home/appuser/projects/myapp

JAVA_LOG_FILE=$APP_DIR/nohup_java.log       # Java 日志
DAEMON_LOG_FILE=$APP_DIR/nohup_daemon.log   # 守护脚本日志

PID_FILE="$APP_DIR/daemon.pid"      # 守护脚本 PID
JAVA_PID_FILE="$APP_DIR/java.pid"   # Java 应用 PID
STATE_FILE="$APP_DIR/app.state"     # 单状态文件
TEST_URL="127.0.0.1:8182"  # 启动后检测服务健康的接口

URL_A="127.0.0.1:8180"
URL_B="127.0.0.1:8181"
TEST_URL="127.0.0.1:8821"           # 启动后健康检查接口

FAIL_THRESHOLD=3
COOL_DOWN=100   # 秒

# 使用传入的 URL 或默认 URL_A
START_URL=${1:-$URL_A}

# ===== 状态文件函数 =====
get_state() {
    local key=$1
    grep "^$key=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2
}

set_state() {
    local key=$1
    local value=$2
    if grep -q "^$key=" "$STATE_FILE" 2>/dev/null; then
        sed -i "s|^$key=.*|$key=$value|" "$STATE_FILE"
    else
        echo "$key=$value" >> "$STATE_FILE"
    fi
}

# ===== 启动/停止 myapp =====

start_app() {
    local url=$1
    echo "$(date): Starting $APP_NAME with YICUN_URL=$url" >> "$DAEMON_LOG_FILE"

    #nohup java -Dloader.path=$APP_DIR/lib \
    #    -DYICUN_DB_HOST=testdb \
    #    -DYICUN_URL=$url \
    #    -Dspring.profiles.active=qa \
    #    -jar $APP_DIR/$APP_NAME >> "$JAVA_LOG_FILE" 2>&1 &

    nohup python -m SimpleHTTPServer 8182 >/dev/null 2>&1 &

    echo $! > "$JAVA_PID_FILE"
    set_state "CURRENT_URL" "$url"
    set_state "FAIL_COUNT" "0"

    # 等待服务启动完成，通过 TEST_URL 检测端口
    for i in {1..10}; do
        local host=${TEST_URL%%:*}
        local port=${TEST_URL##*:}
        timeout 3 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "$(date): App started OK, TEST_URL $TEST_URL reachable" >> "$DAEMON_LOG_FILE"
            return
        fi
        sleep 2
    done

    echo "$(date): WARNING: App may not have started successfully (TEST_URL $TEST_URL unreachable)!" >> "$DAEMON_LOG_FILE"
}

stop_app() {
    if [ -f "$JAVA_PID_FILE" ]; then
        PID=$(cat "$JAVA_PID_FILE")
        if kill -0 $PID 2>/dev/null; then
            echo "$(date): Stopping $APP_NAME (PID=$PID)..." >> "$DAEMON_LOG_FILE"
            kill $PID
        fi
        rm -f "$JAVA_PID_FILE"
    fi
}

check_url() {
    local url=$1
    local host=${url%%:*}
    local port=${url##*:}
    timeout 3 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null
    return $?
}

init_start() {
    echo "$(date): First run detected. Init cleanup..." >> "$DAEMON_LOG_FILE"
    rm -f "$STATE_FILE" "$JAVA_PID_FILE"
    start_app "$START_URL"
}

# ===== 后台守护循环 =====
run_loop() {
    while true; do
        CURRENT_URL=$(get_state "CURRENT_URL" || echo "$URL_A")
        FAIL_COUNT=$(get_state "FAIL_COUNT" || echo 0)
        LAST_SWITCH=$(get_state "LAST_SWITCH" || echo 0)
        NOW=$(date +%s)

        if check_url "$CURRENT_URL"; then
            echo "$(date): $CURRENT_URL OK (fail_count reset)" >> "$DAEMON_LOG_FILE"
            set_state "FAIL_COUNT" "0"
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            set_state "FAIL_COUNT" "$FAIL_COUNT"
            echo "$(date): $CURRENT_URL FAIL ($FAIL_COUNT/$FAIL_THRESHOLD)" >> "$DAEMON_LOG_FILE"

            if [ $FAIL_COUNT -ge $FAIL_THRESHOLD ]; then
                if (( NOW - LAST_SWITCH < COOL_DOWN )); then
                    echo "$(date): Fail threshold reached but cooling down ($COOL_DOWN sec)" >> "$DAEMON_LOG_FILE"
                else
                    echo "$(date): Reached $FAIL_THRESHOLD fails, switching URL..." >> "$DAEMON_LOG_FILE"
                    stop_app

                    if [ "$CURRENT_URL" == "$URL_A" ]; then
                        NEW_URL=$URL_B
                    else
                        NEW_URL=$URL_A
                    fi

                    set_state "LAST_SWITCH" "$NOW"
                    start_app "$NEW_URL"
                fi
            fi
        fi

        sleep 10
    done
}

# ===== 脚本入口 =====
if [ ! -f "$STATE_FILE" ]; then
    init_start
fi

# 后台运行守护循环
run_loop >> "$DAEMON_LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
echo "start.sh launched in background, PID=$(cat "$PID_FILE")"