#!/bin/bash
# ==========================================
# datamind-notebook 构建脚本
# 支持多环境、多镜像源、缓存控制
# ==========================================

set -euo pipefail

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==================== 默认配置 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 镜像配置
IMAGE_NAME="datamind-notebook"
DOCKERFILE="${PROJECT_ROOT}/Dockerfile"

# 构建类型
BUILD_TYPE="production"  # development, testing, production

# 缓存控制
NO_CACHE=false
PULL=false
QUIET=false

# 镜像源配置
PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
PIP_TRUSTED_HOST="pypi.tuna.tsinghua.edu.cn"
PIP_EXTRA_INDEX_URL=""

# 额外包
EXTRA_APT_PACKAGES=""
INSTALL_DEV_TOOLS=false
CLEAN_BUILD_DEPS=true

# 版本信息
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME=$(date +%Y%m%d-%H%M%S)
VERSION=""

# 输出标签
TAGS=()

# ==================== 帮助信息 ====================
show_help() {
    cat << EOF
${BLUE}datamind-notebook 构建脚本${NC}

用法: $0 [选项]

${GREEN}基本选项:${NC}
  -t, --type TYPE         构建类型: development, testing, production (默认: production)
  -n, --no-cache          禁用 Docker 缓存
  -p, --pull              构建前拉取最新基础镜像
  -q, --quiet             安静模式（减少输出）
  -h, --help              显示帮助信息

${GREEN}镜像源选项:${NC}
  --index-url URL         PyPI 镜像源地址 (默认: 清华源)
  --trusted-host HOST     信任的主机 (默认: pypi.tuna.tsinghua.edu.cn)
  --extra-index-url URL   备用镜像源地址

${GREEN}功能选项:${NC}
  --with-apt PKGS         额外安装的系统包 (用引号括起来，如 "vim htop")
  --with-dev-tools        安装开发工具 (ipdb, pytest, black 等)
  --no-clean-deps         不清理构建依赖 (默认清理)

${GREEN}标签选项:${NC}
  --tag TAG               添加自定义标签 (可多次使用)
  --version VER           设置版本号 (默认: 自动生成)

${GREEN}示例:${NC}
  $0 --type development                    # 构建开发环境
  $0 --type production --no-cache          # 无缓存构建生产环境
  $0 --index-url https://pypi.douban.com/simple  # 使用豆瓣源
  $0 --with-apt "vim htop" --with-dev-tools      # 安装额外包和开发工具
  $0 --tag mycompany/v1 --tag stable             # 添加多个标签

EOF
}

# ==================== 日志函数 ====================
log_info() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${GREEN}[INFO]${NC} $*"
    fi
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*"
    fi
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# ==================== 参数解析 ====================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                BUILD_TYPE="$2"
                shift 2
                ;;
            -n|--no-cache)
                NO_CACHE=true
                shift
                ;;
            -p|--pull)
                PULL=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --index-url)
                PIP_INDEX_URL="$2"
                shift 2
                ;;
            --trusted-host)
                PIP_TRUSTED_HOST="$2"
                shift 2
                ;;
            --extra-index-url)
                PIP_EXTRA_INDEX_URL="$2"
                shift 2
                ;;
            --with-apt)
                EXTRA_APT_PACKAGES="$2"
                shift 2
                ;;
            --with-dev-tools)
                INSTALL_DEV_TOOLS=true
                shift
                ;;
            --no-clean-deps)
                CLEAN_BUILD_DEPS=false
                shift
                ;;
            --tag)
                TAGS+=("$2")
                shift 2
                ;;
            --version)
                VERSION="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 验证构建类型
    case "$BUILD_TYPE" in
        development|testing|production)
            ;;
        *)
            log_error "无效的构建类型: $BUILD_TYPE (必须是 development, testing, production)"
            exit 1
            ;;
    esac

    # 生成版本号（如果未指定）
    if [[ -z "$VERSION" ]]; then
        VERSION="${BUILD_TYPE}-${BUILD_TIME}-${GIT_COMMIT}"
    fi

    # 默认标签
    if [[ ${#TAGS[@]} -eq 0 ]]; then
        TAGS=(
            "${IMAGE_NAME}:${BUILD_TYPE}-${GIT_COMMIT}"
            "${IMAGE_NAME}:latest"
        )
    fi
}

# ==================== 显示配置 ====================
show_config() {
    log_info "构建配置:"
    log_info "  PROJECT_ROOT: ${PROJECT_ROOT}"
    log_info "  BUILD_TYPE: ${BUILD_TYPE}"
    log_info "  NO_CACHE: ${NO_CACHE}"
    log_info "  PULL: ${PULL}"
    log_info "  PIP_INDEX_URL: ${PIP_INDEX_URL}"
    log_info "  PIP_TRUSTED_HOST: ${PIP_TRUSTED_HOST}"
    log_info "  PIP_EXTRA_INDEX_URL: ${PIP_EXTRA_INDEX_URL}"
    log_info "  EXTRA_APT_PACKAGES: ${EXTRA_APT_PACKAGES}"
    log_info "  INSTALL_DEV_TOOLS: ${INSTALL_DEV_TOOLS}"
    log_info "  CLEAN_BUILD_DEPS: ${CLEAN_BUILD_DEPS}"
    log_info "  GIT_COMMIT: ${GIT_COMMIT}"
    log_info "  BUILD_TIME: ${BUILD_TIME}"
    log_info "  VERSION: ${VERSION}"
    log_info "  TAGS:"
    for tag in "${TAGS[@]}"; do
        log_info "    - ${tag}"
    done
}

# ==================== 构建函数 ====================
build_image() {
    log_info "开始构建镜像..."

    # 切换到项目根目录
    cd "$PROJECT_ROOT"

    # 构建 Docker 命令
    local cmd=("docker" "build")

    # 添加缓存控制
    if [[ "$NO_CACHE" == "true" ]]; then
        cmd+=("--no-cache")
    fi

    # 添加 pull 选项
    if [[ "$PULL" == "true" ]]; then
        cmd+=("--pull")
    fi

    # 添加安静模式
    if [[ "$QUIET" == "true" ]]; then
        cmd+=("-q")
    fi

    # 添加构建参数
    cmd+=(
        --build-arg "BUILD_TYPE=${BUILD_TYPE}"
        --build-arg "PIP_INDEX_URL=${PIP_INDEX_URL}"
        --build-arg "PIP_TRUSTED_HOST=${PIP_TRUSTED_HOST}"
        --build-arg "PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL}"
        --build-arg "EXTRA_APT_PACKAGES=${EXTRA_APT_PACKAGES}"
        --build-arg "INSTALL_DEV_TOOLS=${INSTALL_DEV_TOOLS}"
        --build-arg "CLEAN_BUILD_DEPS=${CLEAN_BUILD_DEPS}"
        --build-arg "VERSION=${VERSION}"
        --build-arg "BUILD_TIME=${BUILD_TIME}"
        --build-arg "GIT_COMMIT=${GIT_COMMIT}"
    )

    # 添加标签
    for tag in "${TAGS[@]}"; do
        cmd+=("-t" "$tag")
    done

    # 添加 Dockerfile 和上下文
    cmd+=("-f" "$DOCKERFILE" ".")

    # 显示完整命令（调试用）
    log_debug "执行命令: ${cmd[*]}"

    # 执行构建
    log_info "开始构建..."
    if "${cmd[@]}"; then
        log_success "构建成功！"
        log_info "可用标签:"
        for tag in "${TAGS[@]}"; do
            log_info "  ${tag}"
        done
    else
        log_error "构建失败！"
        exit 1
    fi
}

# ==================== 验证函数 ====================
verify_image() {
    log_info "验证镜像..."
    
    local test_tag="${TAGS[0]}"
    
    # 测试 Python 版本
    if docker run --rm "$test_tag" python --version > /dev/null 2>&1; then
        log_success "Python 验证通过"
    else
        log_warn "Python 验证失败"
    fi
    
    # 测试 Jupyter 安装
    if docker run --rm "$test_tag" pip show jupyter > /dev/null 2>&1; then
        log_success "Jupyter 验证通过"
    else
        log_warn "Jupyter 验证失败"
    fi
    
    # 测试依赖安装
    if [[ -f "${PROJECT_ROOT}/requirements.txt" ]]; then
        local pkg_count
        pkg_count=$(docker run --rm "$test_tag" pip list --format=freeze | wc -l)
        log_info "已安装包数量: ${pkg_count}"
    fi
}

# ==================== 清理函数 ====================
cleanup() {
    # 这里可以添加清理逻辑
    log_debug "清理临时文件..."
}

# ==================== 主函数 ====================
main() {
    # 解析参数
    parse_args "$@"
    
    # 显示配置
    show_config
    
    # 确认构建（可选）
    if [[ -z "${CI:-}" ]] && [[ "${QUIET}" != "true" ]]; then
        read -p "是否继续构建？ [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
            log_info "构建取消"
            exit 0
        fi
    fi
    
    # 构建镜像
    build_image
    
    # 验证镜像
    if [[ "${BUILD_TYPE}" != "development" ]] || [[ "${VERIFY:-false}" == "true" ]]; then
        verify_image
    fi
    
    log_success "所有操作完成！"
}

# ==================== 设置陷阱 ====================
trap cleanup EXIT INT TERM

# ==================== 执行主函数 ====================
main "$@"