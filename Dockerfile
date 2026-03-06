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

# 用户和权限配置
ARG NB_USER=jovyan
ARG NB_UID=1000
ARG NB_GID=1000

# 版本信息
ARG VERSION=latest
ARG BUILD_DATE
ARG GIT_COMMIT

# ==================== 环境变量 ====================
ENV TZ=Asia/Shanghai \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    JUPYTER_PORT=8888 \
    JUPYTER_IP=0.0.0.0 \
    JUPYTER_DIR=/home/${NB_USER}/workspace \
    NB_USER=${NB_USER} \
    NB_UID=${NB_UID} \
    NB_GID=${NB_GID} \
    BUILD_TYPE=${BUILD_TYPE} \
    BUILD_DATE=${BUILD_DATE} \
    VERSION=${VERSION} \
    GIT_COMMIT=${GIT_COMMIT} \
    PIP_INDEX_URL=${PIP_INDEX_URL} \
    PIP_TRUSTED_HOST=${PIP_TRUSTED_HOST} \
    PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL} \
    HOME=/home/${NB_USER}

# ==================== 创建用户和必要的目录 ====================
RUN groupadd -g ${NB_GID} ${NB_USER} && \
    useradd -m -s /bin/bash -u ${NB_UID} -g ${NB_GID} ${NB_USER} && \
    # 创建必要的目录结构
    mkdir -p /home/${NB_USER}/workspace && \
    mkdir -p /home/${NB_USER}/.jupyter && \
    mkdir -p /home/${NB_USER}/.local && \
    mkdir -p /home/${NB_USER}/.cache && \
    # 设置初始权限
    chown -R ${NB_USER}:${NB_USER} /home/${NB_USER}

# ==================== 复制 fix-permissions 脚本 ====================
COPY scripts/fix-permissions.sh /usr/local/bin/fix-permissions
RUN chmod +x /usr/local/bin/fix-permissions

# ==================== 设置工作目录 ====================
WORKDIR /home/${NB_USER}/workspace

# ==================== 安装系统依赖 ====================
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    # 添加权限管理工具
    sudo \
    acl \
    ${EXTRA_APT_PACKAGES} \
    && if [ "${INSTALL_DEV_TOOLS}" = "true" ]; then \
        apt-get install -y --no-install-recommends \
        vim \
        nano \
        htop \
        procps \
        tree; \
    fi \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ==================== 配置 pip 镜像源（针对所有用户） ====================
RUN echo "[global]" > /etc/pip.conf && \
    echo "index-url = ${PIP_INDEX_URL}" >> /etc/pip.conf && \
    echo "trusted-host = ${PIP_TRUSTED_HOST}" >> /etc/pip.conf && \
    if [ -n "${PIP_EXTRA_INDEX_URL}" ]; then \
        echo "extra-index-url = ${PIP_EXTRA_INDEX_URL}" >> /etc/pip.conf; \
    fi && \
    # 同时为用户创建配置
    mkdir -p /home/${NB_USER}/.config/pip && \
    cp /etc/pip.conf /home/${NB_USER}/.config/pip/pip.conf && \
    # 修复权限
    /usr/local/bin/fix-permissions /home/${NB_USER}/.config

# ==================== 复制依赖文件 ====================
COPY requirements.txt /tmp/requirements.txt
RUN chown ${NB_USER}:${NB_USER} /tmp/requirements.txt

# ==================== 安装 Python 依赖（使用非root用户执行安装） ====================
USER ${NB_USER}
WORKDIR /home/${NB_USER}/workspace

# 升级 pip 并安装基础包
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r /tmp/requirements.txt && \
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
        pre-commit \
        ipywidgets; \
    elif [ "${BUILD_TYPE}" = "testing" ]; then \
        pip install --no-cache-dir \
        pytest \
        pytest-cov \
        pytest-xdist; \
    fi && \
    # 清理 pip 缓存
    pip cache purge && \
    rm -rf /home/${NB_USER}/.cache/pip

# ==================== 清理构建依赖（需要root权限） ====================
USER root
RUN if [ "${CLEAN_BUILD_DEPS}" = "true" ] && [ "${BUILD_TYPE}" = "production" ]; then \
        apt-get purge -y build-essential && \
        apt-get autoremove -y; \
    fi && \
    # 清理临时文件
    rm -f /tmp/requirements.txt

# ==================== 复制配置文件并修复权限 ====================
# 复制 Jupyter 配置文件
COPY config/jupyter_notebook_config.py /home/${NB_USER}/.jupyter/

# 复制入口脚本
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 修复所有用户目录的权限
RUN /usr/local/bin/fix-permissions /home/${NB_USER}

# 添加 sudo 权限配置（可选，允许用户安装系统包）
# RUN echo "${NB_USER} ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt, /usr/bin/dpkg, /usr/local/bin/fix-permissions" >> /etc/sudoers.d/${NB_USER} && \
#     chmod 0440 /etc/sudoers.d/${NB_USER}

# ==================== 添加标签 ====================
LABEL build.type=${BUILD_TYPE} \
      build.git_commit=${GIT_COMMIT} \
      build.version=${VERSION} \
      pip.index_url=${PIP_INDEX_URL} \
      pip.trust_host=${PIP_TRUSTED_HOST} \
      pip.extra_index_url=${PIP_EXTRA_INDEX_URL} \
      user.name=${NB_USER} \
      user.uid=${NB_UID}

# ==================== 切换回普通用户 ====================
USER ${NB_USER}
WORKDIR /home/${NB_USER}/workspace

# 暴露 Jupyter 端口
EXPOSE 8888

# 设置健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8888/api || exit 1

# 设置入口点
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# 默认命令
CMD []