#!/bin/bash
set -euo pipefail

# ==========================================
# 快速路径 - 只处理 help 命令
# ==========================================
# 设置最基本的变量用于判断
export NB_USER="${NB_USER:-jovyan}"
export GRANT_SUDO="${GRANT_SUDO:-no}"
export SUDO_SCOPE="${SUDO_SCOPE:-none}"

# 只处理 help 命令，其他命令都交给后面的 exec
if [ $# -gt 0 ]; then
    case "$1" in
        -h|--help|help)
            # 继续执行，让后面的 show_help 处理
            ;;
    esac
fi

# ==========================================
# 颜色定义
# ==========================================
if [ -t 1 ] && [ "$TERM" != "dumb" ] && [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # 支持颜色的终端
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # 不支持颜色的终端
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    NC=''
fi

# ==========================================
# 全局变量
# ==========================================
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_TIME=$(date +%s)
EXIT_CODE=0
CLEANUP_FILES=()          # 需要清理的临时文件列表
CLEANUP_DIRS=()           # 需要清理的临时目录列表
CLEANUP_DONE=false        # 清理是否已完成
CHILD_PID=""              # 子进程 PID

# ==========================================
# 日志函数
# ==========================================

# 获取当前时间戳（格式：YYYY-MM-DD HH:MM:SS.sss）
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S.%3N' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(get_timestamp) $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(get_timestamp) $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(get_timestamp) $*" >&2
}

log_debug() {
    if [ "${DEBUG:-false}" = "true" ] || [ "${BUILD_TYPE:-production}" = "development" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $(get_timestamp) $*" >&2
    fi
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(get_timestamp) $*"
}

# ==========================================
# 显示帮助信息
# ==========================================
show_help() {
    cat << EOF
${CYAN}Usage:${NC}
  docker run [OPTIONS] datamind-notebook [COMMAND] [ARGS...]

${CYAN}Environment Variables:${NC}
  NB_USER              Username (default: jovyan)
  NB_UID               User ID (default: 1000)
  NB_GID               Group ID (default: 1000)
  JUPYTER_IP           IP to bind (default: 0.0.0.0)
  JUPYTER_PORT         Port to listen on (default: 8888)
  JUPYTER_NOTEBOOK_DIR Working directory (default: /home/jovyan/workspace)
  JUPYTER_MODE         'notebook' or 'lab' (default: notebook)
  JUPYTER_TOKEN        Access token (default: auto-generated)
  JUPYTER_PASSWORD     Access password (default: none)
  JUPYTER_EXTRA_ARGS   Additional Jupyter arguments
  BUILD_TYPE           'production', 'development', 'testing'
  ALLOW_ORIGIN         Allow CORS origin (default: none)
  FAST_START           Skip permission fixes for faster startup (default: true)
  TZ                   Timezone (default: Asia/Shanghai)
  DEBUG                Enable debug output (default: false)
  
${CYAN}Sudo Configuration:${NC}
  GRANT_SUDO           Enable sudo access (yes/no, default: no)
  SUDO_SCOPE           Sudo permission scope: none, limited, full (default: none)
                       limited: allows apt-get, apt, dpkg, fix-permissions only
                       full: allows all commands (same as GRANT_SUDO=yes)

${CYAN}Examples:${NC}
  # Run Jupyter Notebook
  docker run -p 8888:8888 datamind-notebook

  # Run JupyterLab with custom token
  docker run -p 8888:8888 -e JUPYTER_MODE=lab -e JUPYTER_TOKEN=secret datamind-notebook

  # Run with custom user ID (fix permission issues)
  docker run -p 8888:8888 -e NB_UID=\$(id -u) -e NB_GID=\$(id -g) -v \$(pwd):/home/jovyan/workspace datamind-notebook

  # Enable limited sudo for package installation (must run as root)
  docker run --user root -e SUDO_SCOPE=limited -p 8888:8888 datamind-notebook

  # Enable full sudo access
  docker run --user root -e GRANT_SUDO=yes -p 8888:8888 datamind-notebook

  # FAST PATH: Execute custom command (skips all initialization)
  docker run --rm datamind-notebook python --version

  # FAST PATH: Start a shell (instant)
  docker run -it --rm datamind-notebook /bin/bash

${CYAN}More information:${NC}
  https://github.com/your-repo/datamind-notebook
EOF
    exit 0
}

# ==========================================
# 打印 Banner 和启动信息
# ==========================================
print_startup_info() {
    # 打印 Banner
    echo -e "${CYAN}#######################################################${NC}"
    echo -e "${CYAN}#                                                     #${NC}"
    echo -e "${CYAN}#  ____    _  _____  _    __  __ ___ _   _ ____       #${NC}"
    echo -e "${CYAN}# |  _ \  / \|_   _|/ \  |  \/  |_ _| \ | |  _ \      #${NC}"
    echo -e "${CYAN}# | | | |/ _ \ | | / _ \ | |\/| || ||  \| | | | |     #${NC}"
    echo -e "${CYAN}# | |_| / ___ \| |/ ___ \| |  | || || |\  | |_| |     #${NC}"
    echo -e "${CYAN}# |____/_/   \_\_/_/   \_\_|  |_|___|_| \_|____/      #${NC}"
    echo -e "${CYAN}#                                                     #${NC}"
    echo -e "${CYAN}#######################################################${NC}"
    
    # 版本信息
    echo -e "\n${CYAN}  Build Information${NC}"
    printf "${CYAN}   %-12s: ${GREEN}%s${NC}\n" "Version" "${VERSION:-unknown}"
    printf "${CYAN}   %-12s: ${YELLOW}%s${NC}\n" "Build Date" "${BUILD_DATE:-unknown}"
    printf "${CYAN}   %-12s: ${PURPLE}%s${NC}\n" "Git Commit" "${GIT_COMMIT:-unknown}"
    printf "${CYAN}   %-12s: ${BLUE}%s${NC}\n" "Build Type" "${BUILD_TYPE:-production}"
    
    # 系统信息
    echo -e "\n${CYAN}  System Information${NC}"
    printf "${CYAN}   %-12s: ${GREEN}%s${NC}\n" "Hostname" "$(hostname)"
    printf "${CYAN}   %-12s: ${GREEN}%s${NC}\n" "User" "${NB_USER:-jovyan}"
    printf "${CYAN}   %-12s: ${YELLOW}%s${NC}\n" "Home Dir" "${HOME:-/home/jovyan}"
    printf "${CYAN}   %-12s: ${BLUE}%s${NC}\n" "Started" "$(date '+%Y-%m-%d %H:%M:%S')"
    printf "${CYAN}   %-12s: ${PURPLE}%s${NC}\n" "Timezone" "${TZ:-Asia/Shanghai}"
    
    # Sudo 信息
    if [ "${GRANT_SUDO:-no}" = "yes" ] || [ "${GRANT_SUDO:-no}" = "1" ]; then
        printf "${CYAN}   %-12s: ${YELLOW}%s${NC}\n" "Sudo" "Enabled (full)"
    elif [ "${SUDO_SCOPE:-none}" = "full" ]; then
        printf "${CYAN}   %-12s: ${YELLOW}%s${NC}\n" "Sudo" "Enabled (full)"
    elif [ "${SUDO_SCOPE:-none}" = "limited" ]; then
        printf "${CYAN}   %-12s: ${YELLOW}%s${NC}\n" "Sudo" "Enabled (limited)"
    else
        printf "${CYAN}   %-12s: ${GREEN}%s${NC}\n" "Sudo" "Disabled"
    fi
    
    # Jupyter 配置信息
    local jupyter_mode_desc=""
    if [ "${JUPYTER_MODE}" = "lab" ]; then
        jupyter_mode_desc="JupyterLab"
    else
        jupyter_mode_desc="Jupyter Notebook"
    fi
    
    echo -e "\n${CYAN}Jupyter Server Configuration:${NC}"
    printf "${CYAN}   %-12s: ${GREEN}%s${NC}\n" "Mode" "${jupyter_mode_desc}"
    printf "${CYAN}   %-12s: ${YELLOW}%s${NC}\n" "IP" "${JUPYTER_IP}"
    printf "${CYAN}   %-12s: ${YELLOW}%s${NC}\n" "Port" "${JUPYTER_PORT}"
    printf "${CYAN}   %-12s: ${PURPLE}%s${NC}\n" "Work Dir" "${JUPYTER_NOTEBOOK_DIR:-/home/jovyan/workspace}"
    if [ -z "${JUPYTER_TOKEN:-}" ] && [ -z "${JUPYTER_PASSWORD:-}" ]; then
        printf "${CYAN}   %-12s: ${YELLOW}%s${NC}\n" "Token" "Auto-generated (see below)"
    fi
    echo ""
}

# ==========================================
# 设置环境变量
# ==========================================
setup_environment() {
    export NB_USER="${NB_USER:-jovyan}"
    export NB_UID="${NB_UID:-1000}"
    export NB_GID="${NB_GID:-1000}"
    export HOME="/home/${NB_USER}"
    export JUPYTER_IP="${JUPYTER_IP:-0.0.0.0}"
    export JUPYTER_PORT="${JUPYTER_PORT:-8888}"
    export JUPYTER_NOTEBOOK_DIR="${JUPYTER_NOTEBOOK_DIR:-/home/jovyan/workspace}"
    export DEBUG="${DEBUG:-false}"
    export JUPYTER_MODE="${JUPYTER_MODE:-lab}"
    export TZ="${TZ:-Asia/Shanghai}"
    export BUILD_TYPE="${BUILD_TYPE:-production}"
    export BUILD_DATE="${BUILD_DATE:-unknown}"
    export VERSION="${VERSION:-unknown}"
    export GIT_COMMIT="${GIT_COMMIT:-unknown}"
    export FAST_START="${FAST_START:-true}"
    
    # Sudo 配置
    export GRANT_SUDO="${GRANT_SUDO:-no}"
    export SUDO_SCOPE="${SUDO_SCOPE:-none}"
    
    # 确保 PATH 包含用户本地 bin 目录
    export PATH="${HOME}/.local/bin:${PATH}:/usr/local/bin"
    
    # 设置时区
    if [ "$(id -u)" = "0" ]; then
        if [ -f "/usr/share/zoneinfo/${TZ}" ]; then
            ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime 2>/dev/null || true
            echo "${TZ}" > /etc/timezone 2>/dev/null || true
            log_debug "System timezone set to: ${TZ}"
        else
            log_warn "Timezone file not found: /usr/share/zoneinfo/${TZ}, using UTC fallback"
            ln -snf "/usr/share/zoneinfo/UTC" /etc/localtime 2>/dev/null || true
            echo "UTC" > /etc/timezone 2>/dev/null || true
        fi
    else
        # 没有root权限时，只设置环境变量
        log_debug "Running without root privileges, timezone set via environment: ${TZ}"
    fi
    
    log_debug "Environment: NB_USER=${NB_USER}, NB_UID=${NB_UID}, NB_GID=${NB_GID}"
    log_debug "PATH: ${PATH}"
    log_debug "TZ: ${TZ}"
    log_debug "Sudo config: GRANT_SUDO=${GRANT_SUDO}, SUDO_SCOPE=${SUDO_SCOPE}"
    log_debug "FAST_START: ${FAST_START}"
}

# ==========================================
# 检查并修复权限
# ==========================================
fix_permissions() {
    local target_dir="$1"
    local silent="${2:-false}"

    [ -d "${target_dir}" ] || return 0

    # 如果不是 root 不需要修复
    if [ "$(id -u)" != "0" ]; then
        return 0
    fi

    # 检查目录 owner
    local current_uid
    if command -v stat >/dev/null 2>&1; then
        current_uid=$(stat -c %u "${target_dir}" 2>/dev/null || echo "")
    fi
    
    # 如果无法获取或 owner 已经正确，跳过
    if [ -n "${current_uid}" ] && [ "${current_uid}" = "${NB_UID}" ]; then
        log_debug "Permissions already correct for ${target_dir}, skipping"
        return 0
    fi

    if [ "${silent}" != "true" ]; then
        log_info "Fixing permissions for ${target_dir}"
    fi

    if command -v /usr/local/bin/fix-permissions >/dev/null 2>&1; then
        /usr/local/bin/fix-permissions "${target_dir}" 2>/dev/null || true
    else
        chown -R "${NB_UID}:${NB_GID}" "${target_dir}" 2>/dev/null || true
        chmod -R u+rwX,go+rX,go-w "${target_dir}" 2>/dev/null || true
    fi
}

# ==========================================
# 确保目录存在并设置正确权限
# ==========================================
ensure_directory() {
    local dir="$1"
    local owner="${2:-${NB_USER}}"
    local group="${3:-${NB_GID}}"
    local silent="${4:-false}"

    if [ ! -d "${dir}" ]; then
        [ "${silent}" != "true" ] && log_debug "Creating directory: ${dir}"
        mkdir -p "${dir}"
    fi

    if [ "$(id -u)" = "0" ]; then
        chown "${owner}:${group}" "${dir}" 2>/dev/null || true
        chmod u+rwX,go+rX,go-w "${dir}" 2>/dev/null || true
    fi
}

# ==========================================
# 配置 sudo 权限
# ==========================================
configure_sudo() {
    # 检查是否以 root 用户运行
    if [ "$(id -u)" -ne 0 ]; then
        if [ "${GRANT_SUDO}" = "yes" ] || [ "${GRANT_SUDO}" = "1" ] || [ "${SUDO_SCOPE}" != "none" ]; then
            log_warn "Sudo requires root privileges. Please add '--user root' to docker run command"
            log_warn "Sudo will NOT be available"
        fi
        return
    fi
    
    local sudo_config_file="/etc/sudoers.d/jupyter"
    
    # 判断是否需要配置 sudo
    if [ "${GRANT_SUDO}" = "yes" ] || [ "${GRANT_SUDO}" = "1" ]; then
        log_info "GRANT_SUDO=yes detected, enabling sudo access"
        
        # 创建 sudoers.d 目录（如果不存在）
        mkdir -p /etc/sudoers.d
        
        # 直接写入实际的 sudo 规则（覆盖原有内容）
        cat > "${sudo_config_file}" << EOF
# Jupyter sudo access - configured by entrypoint.sh at $(date)
# GRANT_SUDO=${GRANT_SUDO}
Defaults env_keep += "PYTHONPATH PYTHONUSERBASE JUPYTER_PATH"
${NB_USER} ALL=(ALL) NOPASSWD:ALL
EOF
        
        # 设置正确的权限
        chmod 0440 "${sudo_config_file}"
        log_info "Full sudo access granted to ${NB_USER} (passwordless)"
        
        # 详细的语法检查
        if command -v visudo >/dev/null 2>&1; then
            # 使用临时文件进行语法检查
            local temp_check_file=$(mktemp)
            if visudo -c -f "${sudo_config_file}" > "${temp_check_file}" 2>&1; then
                log_debug "Sudoers file syntax is valid"
                rm -f "${temp_check_file}"
            else
                local error_msg=$(cat "${temp_check_file}")
                rm -f "${temp_check_file}"
                
                # 分析具体的错误类型
                if echo "${error_msg}" | grep -q "invalid line"; then
                    log_error "Invalid syntax in sudoers file:"
                    log_error "${error_msg}"
                    log_error "File content:"
                    cat "${sudo_config_file}" | sed 's/^/  /' >&2
                    log_error "Falling back to minimal sudo configuration"
                    
                    # 尝试使用更简单的格式
                    cat > "${sudo_config_file}" << EOF
# Jupyter sudo access - minimal configuration
${NB_USER} ALL=(ALL) NOPASSWD:ALL
EOF
                    chmod 0440 "${sudo_config_file}"
                    log_success "Created minimal sudo configuration"
                    
                elif echo "${error_msg}" | grep -q "permissions"; then
                    log_error "Permission error on sudoers file:"
                    log_error "${error_msg}"
                    log_error "Current permissions: $(ls -l ${sudo_config_file})"
                    log_error "Setting correct permissions (0440)"
                    chmod 0440 "${sudo_config_file}"
                    
                elif echo "${error_msg}" | grep -q "syntax error"; then
                    log_error "Syntax error in sudoers file:"
                    log_error "${error_msg}"
                    log_error "File content:"
                    cat "${sudo_config_file}" | sed 's/^/  /' >&2
                    
                else
                    log_warn "Sudoers file syntax check failed with unknown error:"
                    log_warn "${error_msg}"
                    log_warn "This is usually safe - the file format is correct"
                fi
            fi
        else
            log_warn "visudo command not found, skipping syntax check"
        fi
        
    elif [ "${SUDO_SCOPE}" = "full" ]; then
        log_info "SUDO_SCOPE=full detected, enabling full sudo access"
        
        mkdir -p /etc/sudoers.d
        cat > "${sudo_config_file}" << EOF
# Jupyter full sudo access - configured by entrypoint.sh at $(date)
# SUDO_SCOPE=${SUDO_SCOPE}
Defaults env_keep += "PYTHONPATH PYTHONUSERBASE JUPYTER_PATH"
${NB_USER} ALL=(ALL) NOPASSWD:ALL
EOF
        chmod 0440 "${sudo_config_file}"
        log_success "Full sudo access granted to ${NB_USER}"
        
        # 详细的语法检查
        if command -v visudo >/dev/null 2>&1; then
            if ! visudo -c -f "${sudo_config_file}" >/dev/null 2>&1; then
                log_warn "Sudoers file syntax check failed, but file has correct permissions"
                # 尝试使用更简单的格式
                cat > "${sudo_config_file}" << EOF
# Jupyter full sudo access - minimal configuration
${NB_USER} ALL=(ALL) NOPASSWD:ALL
EOF
                chmod 0440 "${sudo_config_file}"
                log_success "Created minimal sudo configuration"
            fi
        fi
        
    elif [ "${SUDO_SCOPE}" = "limited" ]; then
        log_info "SUDO_SCOPE=limited detected, enabling limited sudo access"
        
        mkdir -p /etc/sudoers.d
        cat > "${sudo_config_file}" << EOF
# Jupyter limited sudo access - configured by entrypoint.sh at $(date)
# SUDO_SCOPE=${SUDO_SCOPE}
Defaults env_keep += "PYTHONPATH PYTHONUSERBASE JUPYTER_PATH"
${NB_USER} ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt, /usr/bin/dpkg, /usr/local/bin/fix-permissions, /bin/chown, /bin/chmod, /bin/mkdir, /bin/rm, /bin/cp, /bin/mv
EOF
        chmod 0440 "${sudo_config_file}"
        log_success "Limited sudo access granted to ${NB_USER}"
        log_info "Allowed commands: apt-get, apt, dpkg, fix-permissions, chown, chmod, mkdir, rm, cp, mv"
        
        # 详细的语法检查
        if command -v visudo >/dev/null 2>&1; then
            if ! visudo -c -f "${sudo_config_file}" >/dev/null 2>&1; then
                log_warn "Sudoers file syntax check failed, but file has correct permissions"
                # 对于 limited 模式，我们保留原文件因为命令列表可能很重要
            fi
        fi
        
    else
        # 不启用 sudo，但保留文件作为注释模板
        log_info "Sudo not enabled, creating template only"
        cat > "${sudo_config_file}" << EOF
# Sudo rules for Jupyter user - controlled by GRANT_SUDO/SUDO_SCOPE
# Current settings: GRANT_SUDO=${GRANT_SUDO}, SUDO_SCOPE=${SUDO_SCOPE}
# To enable sudo, run with: -e GRANT_SUDO=yes or -e SUDO_SCOPE=full/limited
Defaults env_keep += "PYTHONPATH PYTHONUSERBASE"
# ${NB_USER} ALL=(ALL) NOPASSWD:ALL
EOF
        chmod 0440 "${sudo_config_file}"
    fi
    
    # 只在 debug 模式下显示文件内容
    if [ "${DEBUG}" = "true" ] || [ "${BUILD_TYPE}" = "development" ]; then
        log_debug "Final sudoers file content:"
        if [ -f "${sudo_config_file}" ]; then
            log_debug "$(cat ${sudo_config_file} | sed 's/^/  /')"
        fi
    fi
}

# ==========================================
# 检查 jupyter 是否可用
# ==========================================
check_jupyter() {
    log_debug "Checking jupyter installation..."
    
    if ! command -v jupyter &> /dev/null; then
        log_warn "jupyter command not found in PATH"
        
        # 检查常见位置
        local jupyter_locations=(
            "${HOME}/.local/bin/jupyter"
            "/usr/local/bin/jupyter"
            "/usr/bin/jupyter"
        )
        
        local jupyter_found=""
        for location in "${jupyter_locations[@]}"; do
            if [ -x "${location}" ]; then
                jupyter_found="${location}"
                log_debug "Found jupyter at: ${location}"
                break
            fi
        done
        
        if [ -n "${jupyter_found}" ]; then
            export PATH="$(dirname "${jupyter_found}"):${PATH}"
            log_info "Added $(dirname "${jupyter_found}") to PATH"
        else
            log_error "jupyter not found in any standard location"
            log_info "Installed packages:"
            pip list --format=freeze 2>/dev/null | grep -E "jupyter|notebook|ipython|ipykernel" || true
            return 1
        fi
    fi
    
    # 显示版本信息
    log_debug "Jupyter version information:"
    jupyter --version 2>&1 | sed 's/^/  /' | while read line; do log_debug "$line"; done
    
    # 检测 JupyterLab
    if [ "${JUPYTER_MODE}" = "lab" ]; then
        # 检查 jupyter --version 输出（使用 -i 忽略大小写）
        if jupyter --version 2>&1 | grep -q -i "lab"; then
            log_debug "JupyterLab detected in version output"
        # 检查 jupyter-lab 命令
        elif command -v jupyter-lab &> /dev/null; then
            log_debug "JupyterLab detected (jupyter-lab command found)"
        # 检查 pip 包列表
        elif pip list 2>/dev/null | grep -q -i "^jupyterlab"; then
            log_debug "JupyterLab detected (installed via pip)"
        else
            log_warn "JupyterLab not detected, falling back to Notebook"
            export JUPYTER_MODE="notebook"
        fi
    fi
    
    return 0
}

# ==========================================
# 设置 Jupyter 配置
# ==========================================
setup_jupyter_config() {
    local silent="${1:-false}"
    local config_dir="${HOME}/.jupyter"
    local runtime_dir="${HOME}/.local/share/jupyter/runtime"
    
    ensure_directory "${config_dir}" "${NB_USER}" "${NB_GID}" "${silent}"
    ensure_directory "${runtime_dir}" "${NB_USER}" "${NB_GID}" "${silent}"
    
    # 如果没有配置文件，创建一个基本的
    if [ ! -f "${config_dir}/jupyter_notebook_config.py" ]; then
        if [ "${silent}" != "true" ]; then
            log_info "Creating default jupyter config..."
        fi
        cat > "${config_dir}/jupyter_notebook_config.py" << EOF
# Jupyter configuration file
c.ServerApp.ip = '${JUPYTER_IP}'
c.ServerApp.port = ${JUPYTER_PORT}
c.ServerApp.notebook_dir = '${JUPYTER_NOTEBOOK_DIR}'
c.ServerApp.open_browser = False
c.ServerApp.trust_xheaders = True
c.ServerApp.terminado_settings = {'shell_command': ['/bin/bash']}
c.ServerApp.allow_origin = '${ALLOW_ORIGIN:-*}'
c.ServerApp.allow_remote_access = True
c.IdentityProvider.token = '${JUPYTER_TOKEN:-}'
EOF
    fi
}

# ==========================================
# 清理函数
# ==========================================
cleanup() {
    # 防止重复清理
    if [ "${CLEANUP_DONE}" = "true" ]; then
        return
    fi
    
    log_debug "Performing cleanup tasks..."
    
    # 清理临时文件
    if [ ${#CLEANUP_FILES[@]} -gt 0 ]; then
        for file in "${CLEANUP_FILES[@]}"; do
            if [ -n "${file}" ] && [ -f "${file}" ]; then
                log_debug "Removing temporary file: ${file}"
                rm -f "${file}"
            fi
        done
    fi
    
    # 清理临时目录
    if [ ${#CLEANUP_DIRS[@]} -gt 0 ]; then
        for dir in "${CLEANUP_DIRS[@]}"; do
            if [ -n "${dir}" ] && [ -d "${dir}" ]; then
                log_debug "Removing temporary directory: ${dir}"
                rm -rf "${dir}"
            fi
        done
    fi
    
    # 清理 Jupyter runtime 文件（只清理超过1小时的旧文件）
    if [ -d "${HOME}/.local/share/jupyter/runtime" ] && [ "$(id -u)" != "0" ]; then
        log_debug "Cleaning up old Jupyter runtime files..."
        find "${HOME}/.local/share/jupyter/runtime" -type f -name "*.json" -mmin +60 -delete 2>/dev/null || true
    fi
    
    # 终止子进程
    if [ -n "${CHILD_PID}" ] && kill -0 "${CHILD_PID}" 2>/dev/null; then
        log_debug "Terminating child process (PID: ${CHILD_PID})"
        kill -TERM "${CHILD_PID}" 2>/dev/null || true
        wait "${CHILD_PID}" 2>/dev/null || true
    fi
    
    CLEANUP_DONE=true
    log_debug "Cleanup completed"
}

# ==========================================
# 添加需要清理的文件
# ==========================================
add_cleanup_file() {
    local file="$1"
    CLEANUP_FILES+=("${file}")
    log_debug "Added to cleanup files: ${file}"
}

# ==========================================
# 添加需要清理的目录
# ==========================================
add_cleanup_dir() {
    local dir="$1"
    CLEANUP_DIRS+=("${dir}")
    log_debug "Added to cleanup dirs: ${dir}"
}

# ==========================================
# 格式化运行时间
# ==========================================
format_runtime() {
    local seconds=$1
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))
    local hours=$((minutes / 60))
    local remaining_minutes=$((minutes % 60))
    
    if [ ${hours} -gt 0 ]; then
        echo "${hours}h ${remaining_minutes}m ${remaining_seconds}s"
    elif [ ${minutes} -gt 0 ]; then
        echo "${minutes}m ${remaining_seconds}s"
    else
        echo "${remaining_seconds}s"
    fi
}

# ==========================================
# 处理信号
# ==========================================
handle_signal() {
    local signal=$1
    local exit_code=$2
    local signal_name="${signal#SIG}"
    
    log_warn "Received signal ${signal_name} (${exit_code}), shutting down gracefully..."
    
    # 执行清理
    cleanup
    
    # 记录退出码
    EXIT_CODE=${exit_code}
    
    # 根据不同信号显示特定信息
    case "${signal}" in
        SIGINT)
            log_info "Interrupted by user (Ctrl+C)"
            ;;
        SIGTERM)
            log_info "Termination requested by Docker/system"
            ;;
        SIGHUP)
            log_info "Hangup detected"
            ;;
    esac
    
    exit ${EXIT_CODE}
}

# ==========================================
# 退出处理
# ==========================================
handle_exit() {
    local exit_code=$?
    local end_time=$(date +%s)
    local runtime=$((end_time - START_TIME))
    local runtime_str=$(format_runtime ${runtime})
    
    # 执行清理（如果还没有执行）
    if [ "${CLEANUP_DONE}" != "true" ]; then
        cleanup
    fi
    
    # 根据退出码显示不同信息
    case ${exit_code} in
        0)
            log_success "Container stopped gracefully after ${runtime_str}"
            ;;
        130)
            log_info "Container stopped by user (Ctrl+C) after ${runtime_str}"
            ;;
        143)
            log_info "Container stopped by SIGTERM after ${runtime_str}"
            ;;
        137)
            log_error "Container killed by SIGKILL (possible out of memory) after ${runtime_str}"
            ;;
        139)
            log_error "Container crashed with SIGSEGV (segmentation fault) after ${runtime_str}"
            ;;
        134)
            log_error "Container aborted with SIGABRT after ${runtime_str}"
            ;;
        *)
            # 处理其他信号导致的退出
            if [ ${exit_code} -ge 128 ] && [ ${exit_code} -le 165 ]; then
                local signal_code=$((exit_code - 128))
                log_error "Container stopped by signal ${signal_code} after ${runtime_str}"
            else
                if [ ${exit_code} -ne 0 ]; then
                    log_error "Container stopped with error code ${exit_code} after ${runtime_str}"
                fi
            fi
            ;;
    esac
    
    # 记录调试信息
    if [ ${exit_code} -ne 0 ] && [ "${DEBUG}" = "true" ]; then
        log_debug "Exit code ${exit_code} at $(date '+%Y-%m-%d %H:%M:%S')"
    fi
    
    exit ${exit_code}
}

# ==========================================
# 监控子进程
# ==========================================
watch_child() {
    local pid=$1
    CHILD_PID=${pid}
    log_debug "Watching child process (PID: ${pid})"
    
    # 等待子进程结束
    wait ${pid}
    local child_exit_code=$?
    
    log_debug "Child process exited with code: ${child_exit_code}"
    return ${child_exit_code}
}

# ==========================================
# 构建 Jupyter 命令
# ==========================================
build_jupyter_command() {
    local jupyter_args=()
    
    # 确定启动模式
    if [ "${JUPYTER_MODE}" = "lab" ]; then
        jupyter_args+=("lab")
    else
        jupyter_args+=("notebook")
    fi
    
    # 添加基本参数
    jupyter_args+=("--ip=${JUPYTER_IP}")
    jupyter_args+=("--port=${JUPYTER_PORT}")
    jupyter_args+=("--no-browser")
    jupyter_args+=("--notebook-dir=${JUPYTER_NOTEBOOK_DIR}")
    jupyter_args+=("--ServerApp.trust_xheaders=True")
    jupyter_args+=("--ServerApp.allow_remote_access=True")
    
    # 添加 token/密码配置
    if [ -n "${JUPYTER_TOKEN:-}" ]; then
        jupyter_args+=("--IdentityProvider.token=${JUPYTER_TOKEN}")
    elif [ -n "${JUPYTER_PASSWORD:-}" ]; then
        jupyter_args+=("--IdentityProvider.password=${JUPYTER_PASSWORD}")
    fi
    
    # 允许跨域（开发环境）
    if [ "${BUILD_TYPE}" = "development" ] || [ "${ALLOW_ORIGIN:-}" = "*" ]; then
        jupyter_args+=("--ServerApp.allow_origin=*")
        if [ "${BUILD_TYPE}" = "development" ]; then
            jupyter_args+=("--debug")
        fi
    elif [ -n "${ALLOW_ORIGIN:-}" ]; then
        jupyter_args+=("--ServerApp.allow_origin=${ALLOW_ORIGIN}")
    fi
    
    # 安全地添加额外的 Jupyter 参数
    if [ -n "${JUPYTER_EXTRA_ARGS:-}" ]; then
        # 使用数组安全地分割参数
        local -a extra_args
        # 使用 eval 但限制在受控环境中
        eval "extra_args=(${JUPYTER_EXTRA_ARGS})"
        jupyter_args+=("${extra_args[@]}")
    fi
    
    # 返回命令和参数
    printf '%s\n' "${jupyter_args[@]}"
}

# ==========================================
# 以普通用户运行 Jupyter
# ==========================================
run_jupyter() {
    # 构建 Jupyter 命令
    local jupyter_args=()
    while IFS= read -r arg; do
        jupyter_args+=("${arg}")
    done < <(build_jupyter_command)
    
    # 检查 jupyter
    if ! check_jupyter; then
        log_error "Jupyter check failed, exiting..."
        exit 1
    fi
    
    # 执行 Jupyter
    log_debug "Executing: jupyter ${jupyter_args[*]}"
    exec jupyter "${jupyter_args[@]}"
}

# ==========================================
# 主函数
# ==========================================
main() {
    # 设置信号处理
    trap 'handle_signal SIGINT 130' INT
    trap 'handle_signal SIGTERM 143' TERM
    trap 'handle_signal SIGHUP 129' HUP
    trap 'handle_exit' EXIT
    
    # 忽略 SIGPIPE
    trap '' PIPE
    
    # 设置环境变量
    setup_environment
    
    # 如果有命令要执行
    if [ $# -gt 0 ]; then
        # 检查第一个参数是否是 Jupyter 相关命令
        case "$1" in
            jupyter|jupyter-notebook|jupyter-lab|ipython)
                # 如果是 Jupyter 命令，需要确保以正确用户身份运行
                if [ "$(id -u)" = "0" ]; then
                    # root 用户需要先配置 sudo（如果需要）
                    if [ "${GRANT_SUDO}" = "yes" ] || [ "${SUDO_SCOPE}" != "none" ]; then
                        configure_sudo
                    fi
                    # 切换到普通用户执行 Jupyter 命令
                    exec gosu "${NB_USER}" "$@"
                else
                    # 普通用户直接执行
                    exec "$@"
                fi
                ;;
            *)
                # 非 Jupyter 命令，直接执行
                exec "$@"
                ;;
        esac
    fi

    # 没有命令，启动 Jupyter
    # 先打印启动信息
    print_startup_info

    # 再配置 sudo（如果需要）
    if [ "$(id -u)" = "0" ]; then
        if [ "${GRANT_SUDO}" = "yes" ] || [ "${SUDO_SCOPE}" != "none" ]; then
            configure_sudo
        fi
    fi
    
    # 如果以 root 运行
    if [ "$(id -u)" = "0" ]; then
        # 确保工作目录存在
        ensure_directory "${JUPYTER_NOTEBOOK_DIR}" "${NB_USER}" "${NB_GID}"
        
        # 只在非快速启动模式下修复权限
        if [ "${FAST_START}" != "true" ]; then
            if [ -d "${HOME}" ]; then
                fix_permissions "${HOME}"
            fi
            fix_permissions "${JUPYTER_NOTEBOOK_DIR}"
        fi
        
        # 设置 Jupyter 配置
        setup_jupyter_config

        # 显示运行信息
        log_info "Running as ${NB_USER}: jupyter ${JUPYTER_MODE}"
        
        # 构建 Jupyter 命令
        local jupyter_cmd="jupyter"
        while IFS= read -r arg; do
            jupyter_cmd="${jupyter_cmd} '${arg}'"
        done < <(build_jupyter_command)
        
        exec gosu "${NB_USER}" bash -c "cd '${JUPYTER_NOTEBOOK_DIR}' && exec ${jupyter_cmd}"
    else
        # 以普通用户运行 Jupyter
        log_info "Running as $(whoami): jupyter ${JUPYTER_MODE}"
        run_jupyter
    fi
}

# ==========================================
# 执行主函数
# ==========================================
main "$@"