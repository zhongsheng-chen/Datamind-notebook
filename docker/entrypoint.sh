#!/bin/bash
set -e

# ==========================================
# 颜色定义
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==========================================
# 全局变量
# ==========================================
SCRIPT_NAME="$(basename "$0")"
START_TIME=$(date +%s)
EXIT_CODE=0
CLEANUP_FILES=()          # 需要清理的临时文件列表
CLEANUP_DIRS=()           # 需要清理的临时目录列表
CLEANUP_DONE=false        # 清理是否已完成
CHILD_PID=""              # 子进程 PID

# ==========================================
# 日志函数
# ==========================================

# 获取当前时间戳（格式：YYYY-MM-DD HH:MM:SS）
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(get_timestamp) $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(get_timestamp) $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(get_timestamp) $1"
}

log_debug() {
    if [ "${DEBUG}" = "true" ] || [ "${BUILD_TYPE}" = "development" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $(get_timestamp) $1"
    fi
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(get_timestamp) $1"
}

# ==========================================
# 显示帮助信息
# ==========================================
show_help() {
    echo -e "${CYAN}Usage:${NC}"
    echo "  docker run [OPTIONS] datamind-notebook [COMMAND] [ARGS...]"
    echo ""
    echo -e "${CYAN}Environment Variables:${NC}"
    echo "  NB_USER              Username (default: jovyan)"
    echo "  NB_UID               User ID (default: 1000)"
    echo "  NB_GID               Group ID (default: 1000)"
    echo "  JUPYTER_IP           IP to bind (default: 0.0.0.0)"
    echo "  JUPYTER_PORT         Port to listen on (default: 8888)"
    echo "  JUPYTER_DIR          Working directory (default: /home/jovyan/workspace)"
    echo "  JUPYTER_MODE         'notebook' or 'lab' (default: notebook)"
    echo "  JUPYTER_TOKEN        Access token (default: auto-generated)"
    echo "  JUPYTER_PASSWORD     Access password (default: none)"
    echo "  JUPYTER_EXTRA_ARGS   Additional Jupyter arguments"
    echo "  BUILD_TYPE           'production', 'development', 'testing'"
    echo "  DEBUG                Enable debug output (default: false)"
    echo "  ALLOW_ORIGIN         Allow CORS origin (default: none)"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  # Run Jupyter Notebook"
    echo "  docker run -p 8888:8888 datamind-notebook"
    echo ""
    echo "  # Run JupyterLab with custom token"
    echo "  docker run -p 8888:8888 -e JUPYTER_MODE=lab -e JUPYTER_TOKEN=secret datamind-notebook"
    echo ""
    echo "  # Run with custom user ID (fix permission issues)"
    echo "  docker run -p 8888:8888 -e NB_UID=\$(id -u) -e NB_GID=\$(id -g) -v \$(pwd):/home/jovyan/workspace datamind-notebook"
    echo ""
    echo "  # Execute custom command"
    echo "  docker run --rm datamind-notebook python --version"
    echo ""
    echo -e "${CYAN}More information:${NC}"
    echo "  https://github.com/your-repo/datamind-notebook"
    exit 0
}

# ==========================================
# 打印 Banner
# ==========================================
print_banner() {
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
    if [ -n "${VERSION}" ] || [ -n "${BUILD_TIME}" ] || [ -n "${GIT_COMMIT}" ] || [ -n "${BUILD_TYPE}" ]; then
        echo -e "${CYAN} 📦 Build Information${NC}"
        [ -n "${VERSION}" ] && echo -e "${CYAN}     Version    : ${GREEN}${VERSION}${CYAN}${NC}"
        [ -n "${BUILD_TIME}" ] && echo -e "${CYAN}     Build Time : ${YELLOW}${BUILD_TIME}${CYAN}${NC}"
        [ -n "${GIT_COMMIT}" ] && echo -e "${CYAN}     Git Commit : ${PURPLE}${GIT_COMMIT}${CYAN}${NC}"
        [ -n "${BUILD_TYPE}" ] && echo -e "${CYAN}     Build Type : ${BLUE}${BUILD_TYPE}${CYAN}${NC}"
    fi
    
    # 系统信息
    echo -e "${CYAN} 🖥️ System Information${NC}"
    echo -e "${CYAN}     Hostname  : ${GREEN}$(hostname)${CYAN}${NC}"
    echo -e "${CYAN}     User      : ${GREEN}${NB_USER:-jovyan}${CYAN}${NC}"
    echo -e "${CYAN}     Work Dir  : ${YELLOW}${JUPYTER_DIR:-/home/jovyan/workspace}${CYAN}${NC}"
    echo -e "${CYAN}     Started   : ${BLUE}$(date '+%Y-%m-%d %H:%M:%S')${CYAN}${NC}"
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
    export JUPYTER_DIR="${JUPYTER_DIR:-${HOME}/workspace}"
    export DEBUG="${DEBUG:-false}"
    export JUPYTER_MODE="${JUPYTER_MODE:-notebook}"
    
    # 确保 PATH 包含用户本地 bin 目录
    export PATH="${HOME}/.local/bin:${PATH}:/usr/local/bin"
    
    log_debug "Environment: NB_USER=${NB_USER}, NB_UID=${NB_UID}, NB_GID=${NB_GID}"
    log_debug "PATH: ${PATH}"
}

# ==========================================
# 检查并修复权限
# ==========================================
fix_permissions() {
    local target_dir="$1"
    if [ -d "${target_dir}" ]; then
        log_debug "Fixing permissions for: ${target_dir}"
        /usr/local/bin/fix-permissions "${target_dir}"
    else
        log_warn "Directory does not exist, skipping: ${target_dir}"
    fi
}

# ==========================================
# 确保目录存在并设置正确权限
# ==========================================
ensure_directory() {
    local dir="$1"
    local owner="${2:-${NB_USER}}"
    local group="${3:-${NB_GID}}"
    
    if [ ! -d "${dir}" ]; then
        log_debug "Creating directory: ${dir}"
        mkdir -p "${dir}"
    fi
    
    if [ "$(id -u)" = "0" ]; then
        chown -R ${owner}:${group} "${dir}"
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
            "${HOME}/.local/lib/python*/site-packages/jupyter.py"
        )
        
        local jupyter_found=""
        for pattern in "${jupyter_locations[@]}"; do
            # 使用通配符展开
            for path in $pattern; do
                if [ -x "${path}" ]; then
                    jupyter_found="${path}"
                    log_debug "Found jupyter at: ${path}"
                    break 2
                fi
            done
        done
        
        if [ -n "${jupyter_found}" ]; then
            export PATH="$(dirname "${jupyter_found}"):${PATH}"
            log_info "Added $(dirname "${jupyter_found}") to PATH"
        else
            log_error "jupyter not found in any standard location"
            log_info "Installed packages:"
            pip list --format=freeze | grep -E "jupyter|notebook|ipython|ipykernel" || true
            return 1
        fi
    fi
    
    # 显示版本信息
    log_info "Jupyter version information:"
    jupyter --version 2>&1 | sed 's/^/  /'
    
    return 0
}

# ==========================================
# 设置 Jupyter 配置
# ==========================================
setup_jupyter_config() {
    local config_dir="${HOME}/.jupyter"
    local runtime_dir="${HOME}/.local/share/jupyter/runtime"
    
    ensure_directory "${config_dir}"
    ensure_directory "${runtime_dir}"
    
    # 如果没有配置文件，创建一个基本的
    if [ ! -f "${config_dir}/jupyter_notebook_config.py" ]; then
        log_info "Creating default jupyter config..."
        cat > "${config_dir}/jupyter_notebook_config.py" << EOF
# Jupyter configuration file
c.ServerApp.ip = '${JUPYTER_IP}'
c.ServerApp.port = ${JUPYTER_PORT}
c.ServerApp.notebook_dir = '${JUPYTER_DIR}'
c.ServerApp.open_browser = False
c.ServerApp.allow_origin = '*'
c.ServerApp.trust_xheaders = True
c.ServerApp.terminado_settings = {'shell_command': ['/bin/bash']}
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
            if [ -f "${file}" ]; then
                log_debug "Removing temporary file: ${file}"
                rm -f "${file}"
            fi
        done
    fi
    
    # 清理临时目录
    if [ ${#CLEANUP_DIRS[@]} -gt 0 ]; then
        for dir in "${CLEANUP_DIRS[@]}"; do
            if [ -d "${dir}" ]; then
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
    
    if [ ${minutes} -gt 0 ]; then
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
# 主函数
# ==========================================
main() {
    # 检查是否需要显示帮助
    if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
        show_help
    fi
    
    # 设置信号处理
    trap 'handle_signal SIGINT 130' INT
    trap 'handle_signal SIGTERM 143' TERM
    trap 'handle_signal SIGHUP 129' HUP
    trap 'handle_exit' EXIT
    
    # 忽略 SIGPIPE
    trap '' PIPE
    
    # 打印 Banner
    print_banner
    
    # 设置环境变量
    setup_environment
    
    # 如果以 root 运行
    if [ "$(id -u)" = "0" ]; then
        log_info "Running as root, setting up user environment..."
        
        # 修复用户家目录权限
        if [ -d "${HOME}" ]; then
            log_info "Fixing home directory permissions..."
            fix_permissions "${HOME}"
        fi
        
        # 确保工作目录存在并修复权限
        log_info "Setting up working directory: ${JUPYTER_DIR}"
        ensure_directory "${JUPYTER_DIR}" "${NB_USER}" "${NB_GID}"
        fix_permissions "${JUPYTER_DIR}"
        
        # 设置 Jupyter 配置
        setup_jupyter_config
        
        log_info "Switching to user: ${NB_USER} (uid: ${NB_UID}, gid: ${NB_GID})"
        
        # 切换到普通用户执行
        exec su -l "${NB_USER}" -c "cd '${JUPYTER_DIR}' && exec $0 $@"
    fi
    
    # 以普通用户运行
    log_info "Running as: $(whoami) (uid: $(id -u), gid: $(id -g))"
    
    # 确保工作目录存在并可访问
    ensure_directory "${JUPYTER_DIR}"
    cd "${JUPYTER_DIR}"
    log_info "Working directory: $(pwd)"
    
    # 检查 jupyter
    if ! check_jupyter; then
        log_error "Jupyter check failed, exiting..."
        exit 1
    fi
    
    # 如果有自定义命令
    if [ $# -gt 0 ]; then
        log_info "Executing custom command: $@"
        exec "$@"
    fi
    
    # 构建 Jupyter 启动命令
    local jupyter_cmd="jupyter"
    local jupyter_args=()
    
    # 确定启动模式
    if [ "${JUPYTER_MODE}" = "lab" ]; then
        jupyter_cmd="jupyter lab"
        log_info "Starting in JupyterLab mode"
    else
        jupyter_cmd="jupyter notebook"
        log_info "Starting in Jupyter Notebook mode"
    fi
    
    # 添加基本参数
    jupyter_args+=("--ip=${JUPYTER_IP}")
    jupyter_args+=("--port=${JUPYTER_PORT}")
    jupyter_args+=("--no-browser")
    jupyter_args+=("--notebook-dir=${JUPYTER_DIR}")
    
    # 添加 token/密码配置
    if [ -n "${JUPYTER_TOKEN}" ]; then
        jupyter_args+=("--IdentityProvider.token=${JUPYTER_TOKEN}")
        log_info "Using provided JUPYTER_TOKEN"
    elif [ -n "${JUPYTER_PASSWORD}" ]; then
        jupyter_args+=("--IdentityProvider.password=${JUPYTER_PASSWORD}")
        log_info "Using provided JUPYTER_PASSWORD"
    fi
    
    # 允许跨域（开发环境）
    if [ "${BUILD_TYPE}" = "development" ] || [ "${ALLOW_ORIGIN}" = "*" ]; then
        jupyter_args+=("--ServerApp.allow_origin=*")
        jupyter_args+=("--debug")
        log_warn "Running in development mode with CORS disabled"
    fi
    
    # 添加额外的 Jupyter 参数
    if [ -n "${JUPYTER_EXTRA_ARGS}" ]; then
        for arg in ${JUPYTER_EXTRA_ARGS}; do
            jupyter_args+=("${arg}")
        done
    fi
    
    # 显示启动信息
    log_success "Starting Jupyter server..."
    echo ""
    echo " Jupyter Server Configuration:"
    echo "  • Mode: ${jupyter_cmd}"
    echo "  • IP: ${JUPYTER_IP}"
    echo "  • Port: ${JUPYTER_PORT}"
    echo "  • Directory: ${JUPYTER_DIR}"
    if [ -z "${JUPYTER_TOKEN}" ] && [ -z "${JUPYTER_PASSWORD}" ]; then
        echo "  • Token: Auto-generated (see below)"
    fi
    echo ""
    
    # 执行 Jupyter
    log_debug "Executing: ${jupyter_cmd} ${jupyter_args[*]}"
    exec ${jupyter_cmd} "${jupyter_args[@]}"
}

# ==========================================
# 执行主函数
# ==========================================
main "$@"