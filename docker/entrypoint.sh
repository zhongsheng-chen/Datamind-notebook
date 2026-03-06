#!/bin/bash
set -e

# 显示版本信息
if [ -n "${VERSION}" ] || [ -n "${BUILD_TIME}" ] || [ -n "${GIT_COMMIT}" ]; then
    echo "=========================================="
    echo "Jupyter Docker Image"
    [ -n "${VERSION}" ] && echo "Version: ${VERSION}"
    [ -n "${BUILD_TIME}" ] && echo "Build Time: ${BUILD_TIME}"
    [ -n "${GIT_COMMIT}" ] && echo "Git Commit: ${GIT_COMMIT}"
    [ -n "${BUILD_TYPE}" ] && echo "Build Type: ${BUILD_TYPE}"
    echo "=========================================="
fi

# 设置用户相关的环境变量
NB_USER="${NB_USER:-jovyan}"
NB_UID="${NB_UID:-1000}"
NB_GID="${NB_GID:-1000}"
HOME="/home/${NB_USER}"

# 确保 PATH 包含用户本地 bin 目录
export PATH="${HOME}/.local/bin:${PATH}"

# 如果以 root 用户运行，则修复权限并切换到普通用户
if [ "$(id -u)" = "0" ]; then
    echo "Container started as root, setting up permissions..."
    
    # 修复关键目录的权限
    if [ -d "${HOME}" ]; then
        echo "Fixing permissions on home directory..."
        /usr/local/bin/fix-permissions "${HOME}"
    fi
    
    # 修复工作目录
    if [ -n "${JUPYTER_DIR}" ] && [ -d "${JUPYTER_DIR}" ]; then
        echo "Fixing permissions on JUPYTER_DIR: ${JUPYTER_DIR}"
        /usr/local/bin/fix-permissions "${JUPYTER_DIR}"
    fi
    
    # 确保工作目录存在
    if [ -n "${JUPYTER_DIR}" ] && [ ! -d "${JUPYTER_DIR}" ]; then
        echo "Creating JUPYTER_DIR: ${JUPYTER_DIR}"
        mkdir -p "${JUPYTER_DIR}"
        chown ${NB_USER}:${NB_GID} "${JUPYTER_DIR}"
    fi
    
    echo "Switching to user: ${NB_USER} (uid: ${NB_UID}, gid: ${NB_GID})"
    
    # 切换到普通用户执行，保留所有环境变量
    exec su -l "${NB_USER}" -c "cd ${JUPYTER_DIR:-${HOME}/workspace} && exec $0 $@"
fi

# 以下代码以普通用户身份运行
echo "Running as user: $(whoami) (uid: $(id -u), gid: $(id -g))"
echo "PATH: ${PATH}"

# 验证 jupyter 是否可用
if ! command -v jupyter &> /dev/null; then
    echo "⚠️  jupyter command not found in PATH"
    echo "   Checking common locations..."
    
    # 检查常见位置
    JUPYTER_LOCATIONS=(
        "${HOME}/.local/bin/jupyter"
        "/usr/local/bin/jupyter"
        "/usr/bin/jupyter"
    )
    
    JUPYTER_FOUND=""
    for loc in "${JUPYTER_LOCATIONS[@]}"; do
        if [ -x "${loc}" ]; then
            JUPYTER_FOUND="${loc}"
            echo "   ✓ Found at: ${loc}"
            break
        fi
    done
    
    if [ -n "${JUPYTER_FOUND}" ]; then
        # 将目录添加到 PATH
        export PATH="$(dirname "${JUPYTER_FOUND}"):${PATH}"
        echo "   ✓ Added to PATH: $(dirname "${JUPYTER_FOUND}")"
    else
        echo "❌ Error: jupyter not found in any standard location"
        echo "   Installed packages:"
        pip list --format=freeze | grep -E "jupyter|notebook|ipython|ipykernel" || echo "   No jupyter-related packages found"
        exit 1
    fi
fi

# 显示 jupyter 版本信息
echo "✓ Jupyter version: $(jupyter --version 2>/dev/null || echo 'unknown')"

# 确保工作目录存在并可访问
WORK_DIR="${JUPYTER_DIR:-${HOME}/workspace}"
if [ ! -d "${WORK_DIR}" ]; then
    echo "Creating working directory: ${WORK_DIR}"
    mkdir -p "${WORK_DIR}"
fi
cd "${WORK_DIR}"
echo "Working directory: $(pwd)"

# 如果有自定义命令，执行它
if [ $# -gt 0 ]; then
    echo "Executing custom command: $@"
    exec "$@"
fi

# 默认启动 Jupyter Notebook
echo "=========================================="
echo "Starting Jupyter Notebook with:"
echo "  IP: ${JUPYTER_IP:-0.0.0.0}"
echo "  Port: ${JUPYTER_PORT:-8888}"
echo "  Directory: ${WORK_DIR}"
echo "  User: $(whoami)"
echo "=========================================="

# 构建 Jupyter 启动命令
JUPYTER_CMD="jupyter notebook"
JUPYTER_CMD="${JUPYTER_CMD} --ip=${JUPYTER_IP:-0.0.0.0}"
JUPYTER_CMD="${JUPYTER_CMD} --port=${JUPYTER_PORT:-8888}"
JUPYTER_CMD="${JUPYTER_CMD} --no-browser"
JUPYTER_CMD="${JUPYTER_CMD} --notebook-dir=${WORK_DIR}"

# 如果是 development 模式，添加 debug
if [ "${BUILD_TYPE}" = "development" ]; then
    JUPYTER_CMD="${JUPYTER_CMD} --debug"
    echo "Running in development mode with debug output"
fi

# 执行 Jupyter
echo "Executing: ${JUPYTER_CMD}"
echo "=========================================="
exec ${JUPYTER_CMD}