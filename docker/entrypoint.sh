#!/bin/bash
# ==========================================
# entrypoint.sh
# ==========================================

set -euo pipefail
IFS=$'\n\t'

# ==================== 配置部分 ====================
readonly SCRIPT_NAME="entrypoint.sh"
readonly VERSION="1.0.0"
readonly CONFIG_DIR="/root/.jupyter"
readonly DEFAULT_PORT=8888
readonly DEFAULT_IP="0.0.0.0"
readonly DEFAULT_DIR="/workspace"

# 取构建信息
BUILD_TYPE="${BUILD_TYPE:-production}"
PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PIP_TRUSTED_HOST="${PIP_TRUSTED_HOST:-pypi.tuna.tsinghua.edu.cn}"
PIP_EXTRA_INDEX_URL="${PIP_EXTRA_INDEX_URL:-}"
INSTALL_DEV_TOOLS="${INSTALL_DEV_TOOLS:-false}"

# 版本信息
readonly IMAGE_VERSION="${VERSION:-latest}"
readonly IMAGE_BUILD_TIME="${BUILD_TIME:-unknown}"
readonly IMAGE_GIT_COMMIT="${GIT_COMMIT:-unknown}"

# ==================== 日志函数 ====================
log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_warn() { echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
log_debug() { if [[ "${DEBUG:-false}" == "true" ]]; then echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $*"; fi; }

# ==================== Banner 函数 ====================
print_banner() {
    echo ""
    cat << "EOF"
|  _ \  __ _| |_ __ _ _ __ ___ (_)_ __   __| |
| | | |/ _` | __/ _` | '_ ` _ \| | '_ \ / _` |
| |_| | (_| | || (_| | | | | | | | | | | (_| |
|____/ \__,_|\__\__,_|_| |_| |_|_|_| |_|\__,_|
EOF
    echo ""
    echo "版本: ${IMAGE_VERSION} | 构建类型: ${BUILD_TYPE} | Python: $(python --version 2>&1 | cut -d' ' -f2)"
    echo "镜像源: ${PIP_INDEX_URL}"
    echo "------------------------------------------------------------"
    echo ""
}

# ==================== 初始化函数 ====================
init_directories() {
    log_debug "初始化目录结构"
    
    local workspace_dir="/workspace"
    
    # 确保工作目录存在
    if [[ ! -d "${workspace_dir}" ]]; then
        mkdir -p "${workspace_dir}" || {
            log_error "无法创建工作目录: ${workspace_dir}"
            return 1
        }
        log_info "创建工作目录: ${workspace_dir}"
    fi
    
    # 检查工作目录权限
    if [[ ! -w "${workspace_dir}" ]]; then
        log_error "工作目录不可写: ${workspace_dir}"
        log_error "提示: 如果使用 -v 挂载，请确保目录有写入权限"
        return 1
    fi
    
    # 创建 Jupyter 配置目录
    if [[ ! -d "${CONFIG_DIR}" ]]; then
        mkdir -p "${CONFIG_DIR}"
        log_debug "创建配置目录: ${CONFIG_DIR}"
    fi
}

# ==================== Token 管理 ====================
generate_token() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 24
    else
        cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 48 | head -n 1 2>/dev/null || echo "datamind-$(date +%s)"
    fi
}

get_or_create_token() {
    local token_file="${CONFIG_DIR}/token.txt"
    local token=""
    
    if [[ -n "${JUPYTER_TOKEN:-}" ]]; then
        token="${JUPYTER_TOKEN}"
        log_debug "使用环境变量中的 token"
    elif [[ -f "${token_file}" ]]; then
        token=$(cat "${token_file}")
        log_debug "从文件读取 token"
    else
        token=$(generate_token)
        echo "${token}" > "${token_file}"
        chmod 600 "${token_file}"
        # 不在这里输出日志，只返回 token
    fi
    
    echo "${token}"
}

# ==================== 命令处理 ====================
show_help() {
    cat << EOF
用法: docker run datamind-notebook [命令] [参数]

命令:
  (无)               启动 Jupyter Notebook
  shell|bash|sh      启动 shell
  python|py          启动 Python REPL
  pip                执行 pip 命令
  jupyter            执行 jupyter 命令
  lab                启动 JupyterLab
  info               显示镜像信息
  version            显示版本信息
  help               显示此帮助

环境变量:
  JUPYTER_PORT      Jupyter 端口 (默认: 8888)
  JUPYTER_IP        监听 IP (默认: 0.0.0.0)
  JUPYTER_DIR       工作目录 (默认: /workspace)
  JUPYTER_TOKEN     访问令牌 (可选)
  HOST_IP           主机 IP (用于远程访问提示)
  DEBUG             调试模式

示例:
  docker run -p 8888:8888 -v \$(pwd):/workspace datamind-notebook
  docker run datamind-notebook python --version
  docker run -e JUPYTER_TOKEN=mysecret datamind-notebook
EOF
}

handle_command() {
    if [[ $# -eq 0 ]]; then
        return 1
    fi
    
    local cmd="$1"
    shift
    
    case "${cmd}" in
        shell|bash|sh)
            exec /bin/bash "$@"
            ;;
        python|py)
            exec python "$@"
            ;;
        pip)
            exec pip "$@"
            ;;
        jupyter)
            exec jupyter "$@"
            ;;
        lab)
            exec jupyter lab \
                --ip="${JUPYTER_IP:-${DEFAULT_IP}}" \
                --port="${JUPYTER_PORT:-${DEFAULT_PORT}}" \
                --notebook-dir="${JUPYTER_DIR:-${DEFAULT_DIR}}" \
                --no-browser \
                --allow-root
            ;;
        info)
            echo "镜像版本: ${IMAGE_VERSION}"
            echo "构建时间: ${IMAGE_BUILD_TIME}"
            echo "Git提交: ${IMAGE_GIT_COMMIT}"
            echo "构建类型: ${BUILD_TYPE}"
            echo "Python: $(python --version 2>&1 | cut -d' ' -f2)"
            echo "pip镜像源: ${PIP_INDEX_URL}"
            exit 0
            ;;
        version|--version|-v)
            echo "datamind-notebook ${IMAGE_VERSION}"
            exit 0
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        *)
            exec "${cmd}" "$@"
            ;;
    esac
}

# ==================== 启动函数 ====================
start_jupyter() {
    local token="$1"
    local port="${JUPYTER_PORT:-${DEFAULT_PORT}}"
    local ip="${JUPYTER_IP:-${DEFAULT_IP}}"
    local dir="${JUPYTER_DIR:-${DEFAULT_DIR}}"
    
    # 先输出访问信息，再启动 Jupyter
    echo ""
    echo "========================================"
    echo "Jupyter 访问信息"
    echo "========================================"
    echo "本地访问: http://localhost:${port}"
    echo "访问令牌: ${token}"
    echo "完整地址: http://localhost:${port}/?token=${token}"
    echo ""
    echo "工作目录: ${dir}"
    if mount | grep -q "/workspace"; then
        echo "挂载卷: $(mount | grep "/workspace" | head -1 | awk '{print $1}')"
    fi
    echo "========================================"
    echo ""
    
    log_info "启动 Jupyter Notebook..."
    
    local cmd=(
        "jupyter" "notebook"
        "--ip=${ip}"
        "--port=${port}"
        "--notebook-dir=${dir}"
        "--no-browser"
        "--allow-root"
        "--NotebookApp.token=${token}"
    )
    
    if [[ -f "${CONFIG_DIR}/jupyter_notebook_config.py" ]]; then
        cmd+=("--config=${CONFIG_DIR}/jupyter_notebook_config.py")
    fi
    
    exec "${cmd[@]}"
}

# ==================== 主函数 ====================
main() {
    print_banner
    
    # 处理命令
    if [[ $# -gt 0 ]]; then
        case "$1" in
            help|--help|-h)
                show_help
                exit 0
                ;;
            version|--version|-v)
                echo "datamind-notebook ${IMAGE_VERSION}"
                exit 0
                ;;
            info)
                # info 命令已经在 handle_command 中处理
                if handle_command "$@"; then
                    exit $?
                fi
                ;;
            *)
                if handle_command "$@"; then
                    exit $?
                fi
                ;;
        esac
    fi
    
    # 初始化环境（不输出日志，除非 DEBUG）
    if [[ "${DEBUG:-false}" == "true" ]]; then
        init_directories || exit 1
    else
        init_directories > /dev/null 2>&1 || exit 1
    fi
    
    # 获取 token（不输出日志）
    local token
    token=$(get_or_create_token)
    
    # 启动 Jupyter（包含访问信息显示）
    start_jupyter "${token}"
}

# ==================== 信号处理 ====================
trap 'echo "[INFO] 收到终止信号，正在关闭..."; exit 0' SIGTERM SIGINT SIGQUIT

# ==================== 脚本入口 ====================
main "$@"