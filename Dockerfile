FROM python:3.10-slim

LABEL maintainer="Zhongsheng Chen <zhongsheng.chen@outlook.com>"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

###################################
#             构建参数 
###################################
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

# Nodejs 配置
ARG INSTALL_NODEJS=false
ARG NODEJS_VERSION=20

# 权限控制配置
ARG GRANT_SUDO=no

# 是否精简镜像（额外清理）
ARG MINIMIZE_IMAGE=true

###################################
#            环境变量 
###################################
ENV TZ=Asia/Shanghai \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1 \
    PIP_PREFER_BINARY=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    JUPYTER_IP=0.0.0.0 \
    JUPYTER_PORT=8888 \
    JUPYTER_NOTEBOOK_DIR=/home/${NB_USER}/workspace \
    JUPYTER_LOG_LEVEL=INFO \
    JUPYTER_LOG_DIR=/var/log/jupyter \
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
    PIP_CACHE_DIR=/home/${NB_USER}/.cache/pip \
    HOME=/home/${NB_USER} \
    GRANT_SUDO=${GRANT_SUDO} \
    PATH=/home/${NB_USER}/.local/bin:/usr/local/bin:$PATH

###################################
#        创建用户和必要的目录
###################################
RUN groupadd -g ${NB_GID} ${NB_USER} && \
    useradd -m -s /bin/bash -u ${NB_UID} -g ${NB_GID} ${NB_USER} && \
    # 创建必要的目录结构
    mkdir -p /home/${NB_USER}/workspace && \
    mkdir -p /home/${NB_USER}/.jupyter && \
    mkdir -p /home/${NB_USER}/.local && \
    mkdir -p /home/${NB_USER}/.cache/pip && \
    mkdir -p /var/log/jupyter && \
    # 设置初始权限
    chown -R ${NB_USER}:${NB_USER} /home/${NB_USER}

# 复制 fix-permissions 脚本
COPY scripts/fix-permissions.sh /usr/local/bin/fix-permissions
RUN chmod +x /usr/local/bin/fix-permissions

###################################
#           安装系统依赖 
###################################
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        git \
        gosu \
        sudo \
        bash \
        bash-completion \
        unzip \
        less \
        nano-tiny \
        tzdata \
        xclip \
        procps \
        libgomp1 \
        ca-certificates \
        ${EXTRA_APT_PACKAGES} \
    && if [ "${INSTALL_DEV_TOOLS}" = "true" ]; then \
        apt-get install -y --no-install-recommends \
            vim \
            htop \
            tree; \
    fi \
    && ln -snf /usr/share/zoneinfo/${TZ:-Asia/Shanghai} /etc/localtime \
    && echo ${TZ:-Asia/Shanghai} > /etc/timezone \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/nano-tiny /usr/bin/nano 2>/dev/null || true

###################################
#    配置 pip 镜像源（针对所有用户）
###################################
RUN echo "[global]" > /etc/pip.conf && \
    echo "index-url = ${PIP_INDEX_URL}" >> /etc/pip.conf && \
    echo "trusted-host = ${PIP_TRUSTED_HOST}" >> /etc/pip.conf && \
    if [ -n "${PIP_EXTRA_INDEX_URL}" ]; then \
        echo "extra-index-url = ${PIP_EXTRA_INDEX_URL}" >> /etc/pip.conf; \
    fi

###################################
#          配置 sudo 权限
###################################
RUN mkdir -p /etc/sudoers.d && \
    echo "# Sudo rules for Jupyter user - controlled by GRANT_SUDO" > /etc/sudoers.d/jupyter && \
    echo "# This file will be dynamically configured by entrypoint script" >> /etc/sudoers.d/jupyter && \
    echo "Defaults env_keep += \"PYTHONPATH PYTHONUSERBASE\"" >> /etc/sudoers.d/jupyter && \
    chmod 0440 /etc/sudoers.d/jupyter

###################################
#       安装 Python 依赖
###################################
USER ${NB_USER}

# 安装基础工具包
RUN --mount=type=cache,target=${PIP_CACHE_DIR},uid=${NB_UID},gid=${NB_GID} \
    pip install --upgrade pip setuptools wheel && \
    pip install --no-cache-dir \
        jupyterlab~=4.0 \
        notebook~=7.0 \
        ipykernel~=6.0

# 复制并安装项目依赖
COPY requirements.txt /tmp/requirements.txt
RUN --mount=type=cache,target=${PIP_CACHE_DIR},uid=${NB_UID},gid=${NB_GID} \
    pip install --no-cache-dir -r /tmp/requirements.txt

###################################
#       条件安装 Node.js
###################################
USER root

RUN if [ "${INSTALL_NODEJS}" = "true" ]; then \
        # 安装 Node.js
        curl -fsSL https://deb.nodesource.com/setup_${NODEJS_VERSION}.x | bash - && \
        apt-get update && \
        apt-get install -y --no-install-recommends nodejs && \
        # 清理 npm 缓存
        npm cache clean --force && \
        rm -rf /root/.npm /root/.node-gyp && \
        # 精简 npm
        npm config set fund false --global && \
        npm config set audit false --global && \
        # 删除 npm 文档
        rm -rf /usr/local/lib/node_modules/npm/{man,html,doc} 2>/dev/null || true && \
        # 清理 APT
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    fi

USER ${NB_USER}

# 如果安装了 Node.js，构建 JupyterLab
RUN if [ "${INSTALL_NODEJS}" = "true" ] && command -v node >/dev/null 2>&1; then \
        echo "Node.js found, building JupyterLab..." && \
        jupyter lab build; \
    else \
        echo "Node.js not found, skipping JupyterLab build"; \
    fi

###################################
#       安装开发/测试工具
###################################
RUN --mount=type=cache,target=${PIP_CACHE_DIR},uid=${NB_UID},gid=${NB_GID} \
    if [ "${BUILD_TYPE}" = "development" ]; then \
        echo "Installing development tools..." && \
        pip install --no-cache-dir \
            ipdb \
            pytest \
            pytest-cov \
            pytest-xdist \
            pytest-mock \
            black \
            flake8 \
            mypy \
            pre-commit \
            ipywidgets \
            jupyterlab-git \
            jupyterlab-lsp \
            python-lsp-server; \
    elif [ "${BUILD_TYPE}" = "testing" ]; then \
        echo "Installing testing tools..." && \
        pip install --no-cache-dir \
            pytest \
            pytest-cov \
            pytest-xdist \
            pytest-mock \
            pytest-asyncio; \
    fi && \
    # 验证关键包是否安装成功
    python -c "import jupyter; print('Jupyter core installed')" 2>/dev/null || true

###################################
#           精简镜像
###################################
USER root

RUN if [ "${MINIMIZE_IMAGE}" = "true" ]; then \
        # 清理 pip 缓存
        rm -rf /home/${NB_USER}/.cache/pip/* && \
        # 删除 Python 字节码文件
        find /home/${NB_USER}/.local -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true && \
        find /home/${NB_USER}/.local -name "*.pyc" -delete && \
        find /home/${NB_USER}/.local -name "*.pyo" -delete && \
        # 删除不必要的文档
        rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/* && \
        # 删除临时文件
        rm -rf /tmp/* /var/tmp/* && \
        # 如果不需要构建依赖，清理 build-essential
        if [ "${CLEAN_BUILD_DEPS}" = "true" ] && [ "${BUILD_TYPE}" = "production" ]; then \
            apt-get purge -y build-essential gcc g++ make && \
            apt-get autoremove -y; \
        fi; \
    fi && \
    # 清理包管理器缓存
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # 删除安装脚本
    rm -f /tmp/requirements.txt

###################################
#        复制文件并修复权限 
###################################
# 复制文件
COPY config/jupyter_notebook_config.py /home/${NB_USER}/.jupyter/
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/healthcheck.py /usr/local/bin/healthcheck.py

# 使用 fix-permissions 设置目录权限
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.py && \
    # 修复日志目录权限
    fix-permissions /var/log/jupyter && \
    # 修复用户主目录权限
    fix-permissions /home/${NB_USER} && \
    chmod -R u+rwX /home/${NB_USER}/.cache && \
    # 修复脚本权限
    fix-permissions /usr/local/bin/healthcheck.py

###################################
#            添加标签 
###################################
LABEL build.type=${BUILD_TYPE} \
      build.git_commit=${GIT_COMMIT} \
      build.version=${VERSION} \
      pip.index_url=${PIP_INDEX_URL} \
      pip.trust_host=${PIP_TRUSTED_HOST} \
      pip.extra_index_url=${PIP_EXTRA_INDEX_URL} \
      user.name=${NB_USER} \
      user.uid=${NB_UID}

###################################
#            健康检查 
###################################
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /usr/local/bin/healthcheck.py

###################################
#         切换回普通用户
###################################
USER ${NB_USER}
WORKDIR "${HOME}"

# 暴露 Jupyter 端口
EXPOSE 8888

# 设置入口点
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# 默认命令
CMD []