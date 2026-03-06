# ==========================================
# 构建 Jupyter 镜像
# ==========================================

FROM python:3.10-slim

LABEL maintainer="Zhongsheng Chen <zhongsheng.chen@outlook.com>"

# ==================== 构建参数 ====================
# 镜像源配置
ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
ARG PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn
ARG PIP_EXTRA_INDEX_URL=""

# 构建环境配置
ARG BUILD_TYPE=production  # development, testing, production
ARG EXTRA_APT_PACKAGES=""
ARG CLEAN_BUILD_DEPS=true
ARG INSTALL_DEV_TOOLS=false

# 版本信息
ARG VERSION=latest
ARG BUILD_TIME
ARG GIT_COMMIT

# ==================== 环境变量 ====================
ENV TZ=Asia/Shanghai \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    JUPYTER_PORT=8888 \
    JUPYTER_IP=0.0.0.0 \
    JUPYTER_DIR=/workspace \
    BUILD_TYPE=${BUILD_TYPE} \
    BUILD_TIME=${BUILD_TIME} \
    VERSION=${VERSION} \
    GIT_COMMIT=${GIT_COMMIT} \
    PIP_INDEX_URL=${PIP_INDEX_URL} \
    PIP_TRUSTED_HOST=${PIP_TRUSTED_HOST} \
    PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL}

WORKDIR /workspace

# ==================== 安装系统依赖 ====================
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    ${EXTRA_APT_PACKAGES} \
    && if [ "${INSTALL_DEV_TOOLS}" = "true" ]; then \
        apt-get install -y --no-install-recommends \
        vim \
        nano \
        htop \
        procps; \
    fi \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ==================== 配置 pip 镜像源 ====================
RUN pip config set global.index-url ${PIP_INDEX_URL} && \
    pip config set global.trusted-host ${PIP_TRUSTED_HOST} && \
    if [ -n "${PIP_EXTRA_INDEX_URL}" ]; then \
        pip config set global.extra-index-url ${PIP_EXTRA_INDEX_URL}; \
    fi

# 复制依赖文件
COPY requirements.txt .

# ==================== 安装 Python 依赖 ====================
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir jupyter jupyterlab && \
    # 根据环境安装额外包
    if [ "${BUILD_TYPE}" = "development" ]; then \
        pip install --no-cache-dir \
        ipdb \
        pytest \
        pytest-cov \
        black \
        flake8 \
        mypy \
        pre-commit; \
    elif [ "${BUILD_TYPE}" = "testing" ]; then \
        pip install --no-cache-dir \
        pytest \
        pytest-cov \
        pytest-xdist; \
    fi && \
    # 清理构建依赖（如果需要）
    if [ "${CLEAN_BUILD_DEPS}" = "true" ] && [ "${BUILD_TYPE}" = "production" ]; then \
        apt-get purge -y build-essential && \
        apt-get autoremove -y; \
    fi && \
    pip cache purge && \
    rm -rf /root/.cache/pip && \
    mkdir -p /root/.jupyter

# ==================== 添加标签 ====================
LABEL build.type=${BUILD_TYPE} \
      build.time=${BUILD_TIME} \
      build.git_commit=${GIT_COMMIT} \
      build.version=${VERSION} \
      pip.index_url=${PIP_INDEX_URL}

# 复制入口脚本
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 复制配置文件
COPY config/jupyter_notebook_config.py /root/.jupyter/

# 暴露 Jupyter 端口
EXPOSE 8888

# 设置健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8888/api || exit 1

# 设置入口点
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# 默认命令
CMD []