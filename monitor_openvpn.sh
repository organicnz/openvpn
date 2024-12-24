#!/bin/bash

# Set strict error handling
set -euo pipefail
IFS=$'\n\t'

# Constants
readonly LOG_DIR="/var/log/openvpn"
readonly MONITOR_LOG="${LOG_DIR}/monitor.log"
readonly STATUS_LOG="${LOG_DIR}/openvpn-status.log"
readonly MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB
readonly MAX_LOG_FILES=5
readonly CHECK_INTERVAL=60
readonly ALERT_THRESHOLD=3
readonly METRICS_FILE="${LOG_DIR}/metrics.json"

# Initialize logging
setup_logging() {
    mkdir -p "${LOG_DIR}"
    touch "${MONITOR_LOG}"
    chmod 640 "${MONITOR_LOG}"
}

# Logging function with timestamps
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" >> "${MONITOR_LOG}"
    if [[ ${level} == "ERROR" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" >&2
    fi
}

# Rotate logs if they exceed size limit
rotate_logs() {
    local log_file=$1
    local size
    
    if [[ -f ${log_file} ]]; then
        size=$(wc -c < "${log_file}")
        if (( size > MAX_LOG_SIZE )); then
            for i in $(seq $((MAX_LOG_FILES - 1)) -1 1); do
                if [[ -f ${log_file}.$i ]]; then
                    mv "${log_file}.$i" "${log_file}.$((i + 1))"
                fi
            done
            mv "${log_file}" "${log_file}.1"
            touch "${log_file}"
            chmod 640 "${log_file}"
            log "INFO" "Rotated log file: ${log_file}"
        fi
    fi
}

# Check OpenVPN process health
check_openvpn_process() {
    if ! pgrep -x "openvpn" > /dev/null; then
        log "ERROR" "OpenVPN process is not running"
        return 1
    fi
    log "INFO" "OpenVPN process is running"
    return 0
}

# Check OpenVPN port availability
check_ports() {
    local ports=("1194/udp" "1194/tcp" "3005/tcp" "3006/tcp" "3007/tcp" "3008/tcp" "3009/tcp")
    local failed=0
    
    for port in "${ports[@]}"; do
        IFS='/' read -r port_num proto <<< "${port}"
        if ! ss -ln${proto:0:1} | grep -q ":${port_num}"; then
            log "ERROR" "Port ${port} is not listening"
            ((failed++))
        else
            log "INFO" "Port ${port} is listening"
        fi
    done
    
    return ${failed}
}

# Check client connections
check_clients() {
    local connected=0
    local status_age
    
    if [[ -f ${STATUS_LOG} ]]; then
        status_age=$(($(date +%s) - $(date -r "${STATUS_LOG}" +%s)))
        if (( status_age > 120 )); then
            log "WARNING" "Status log is outdated (${status_age}s old)"
        fi
        
        connected=$(grep -c "^CLIENT_LIST" "${STATUS_LOG}" || echo "0")
        log "INFO" "Connected clients: ${connected}"
        
        # Update metrics
        echo "{\"timestamp\": \"$(date -u +%FT%TZ)\", \"clients\": ${connected}}" > "${METRICS_FILE}"
    else
        log "ERROR" "Status log not found: ${STATUS_LOG}"
        return 1
    fi
}

# Check system resources
check_resources() {
    local cpu_usage
    local mem_usage
    local disk_usage
    
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    mem_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    disk_usage=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
    
    log "INFO" "CPU Usage: ${cpu_usage}%"
    log "INFO" "Memory Usage: ${mem_usage}%"
    log "INFO" "Disk Usage: ${disk_usage}%"
    
    if (( $(echo "${cpu_usage} > 80" | bc -l) )); then
        log "WARNING" "High CPU usage: ${cpu_usage}%"
    fi
    if (( $(echo "${mem_usage} > 80" | bc -l) )); then
        log "WARNING" "High memory usage: ${mem_usage}%"
    fi
    if (( disk_usage > 80 )); then
        log "WARNING" "High disk usage: ${disk_usage}%"
    fi
}

# Main monitoring loop
main() {
    local failures=0
    
    setup_logging
    log "INFO" "Starting OpenVPN monitoring"
    
    while true; do
        rotate_logs "${MONITOR_LOG}"
        
        if ! check_openvpn_process; then
            ((failures++))
        fi
        
        if ! check_ports; then
            ((failures++))
        fi
        
        if ! check_clients; then
            ((failures++))
        fi
        
        check_resources
        
        if (( failures >= ALERT_THRESHOLD )); then
            log "ERROR" "Multiple failures detected, consider restarting OpenVPN"
            # Here you could add alerting (email, Slack, etc.)
        fi
        
        failures=0
        sleep "${CHECK_INTERVAL}"
    done
}

# Trap signals for clean shutdown
trap 'log "INFO" "Stopping OpenVPN monitoring"; exit 0' SIGTERM SIGINT

# Start monitoring
main 