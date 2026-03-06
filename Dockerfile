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

# 权限控制配置
ARG GRANT_SUDO=no

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
    HOME=/home/${NB_USER} \
    GRANT_SUDO=${GRANT_SUDO}

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
    gosu \
    ca-certificates \
    ${EXTRA_APT_PACKAGES} \
    && if [ "${INSTALL_DEV_TOOLS}" = "true" ]; then \
        apt-get install -y --no-install-recommends \
        vim \
        nano \
        htop \
        procps \
        tree; \
    fi \
    && rm -rf /var/lib/apt/lists/*

# ==================== 配置 pip 镜像源（针对所有用户） ====================
RUN echo "[global]" > /etc/pip.conf && \
    echo "index-url = ${PIP_INDEX_URL}" >> /etc/pip.conf && \
    echo "trusted-host = ${PIP_TRUSTED_HOST}" >> /etc/pip.conf && \
    if [ -n "${PIP_EXTRA_INDEX_URL}" ]; then \
        echo "extra-index-url = ${PIP_EXTRA_INDEX_URL}" >> /etc/pip.conf; \
    fi

# ==================== 配置 sudo 权限 ====================
RUN mkdir -p /etc/sudoers.d && \
    echo "# Sudo rules for Jupyter user - controlled by GRANT_SUDO" > /etc/sudoers.d/jupyter && \
    echo "# This file will be dynamically configured by entrypoint script" >> /etc/sudoers.d/jupyter && \
    echo "Defaults env_keep += \"PYTHONPATH PYTHONUSERBASE\"" >> /etc/sudoers.d/jupyter && \
    chmod 0440 /etc/sudoers.d/jupyter

# ==================== 复制依赖文件 ====================
COPY requirements.txt /tmp/requirements.txt

# ==================== 安装 Python 依赖（使用非root用户执行安装） ====================
USER ${NB_USER}

# 升级 pip 并安装基础包
RUN --mount=type=cache,target=/home/${NB_USER}/.cache/pip,uid=${NB_UID},gid=${NB_GID} \
    pip install --upgrade pip setuptools wheel && \
    pip install jupyterlab notebook && \
    pip install -r /tmp/requirements.txt && \
    if [ "${BUILD_TYPE}" = "development" ]; then \
        pip install \
        ipdb pytest pytest-cov black flake8 mypy pre-commit ipywidgets; \
    elif [ "${BUILD_TYPE}" = "testing" ]; then \
        pip install \
        pytest pytest-cov pytest-xdist; \
    fi

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

# 复制健康检查脚本
COPY scripts/healthcheck.py /usr/local/bin/healthcheck.py
RUN chmod +x /usr/local/bin/healthcheck.py

# 修复所有用户目录的权限
RUN fix-permissions /home/${NB_USER} \
 && fix-permissions /usr/local/bin/healthcheck.py

# ==================== 添加标签 ====================
LABEL build.type=${BUILD_TYPE} \
      build.git_commit=${GIT_COMMIT} \
      build.version=${VERSION} \
      pip.index_url=${PIP_INDEX_URL} \
      pip.trust_host=${PIP_TRUSTED_HOST} \
      pip.extra_index_url=${PIP_EXTRA_INDEX_URL} \
      user.name=${NB_USER} \
      user.uid=${NB_UID}

# ==================== 健康检查 ====================
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /usr/local/bin/healthcheck.py

# ==================== 切换回普通用户 ====================
USER ${NB_USER}
WORKDIR "${HOME}"

# 暴露 Jupyter 端口
EXPOSE 8888

# 设置入口点
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# 默认命令
CMD []