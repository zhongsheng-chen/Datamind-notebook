# ==========================================
# Makefile
# ==========================================

.PHONY: help build build-dev build-test build-prod \
        build-nocache build-dev-nocache build-test-nocache build-prod-nocache \
        build-tsinghua build-aliyun build-official \
        build-with-apt build-clean-deps build-dev-tools \
        run run-dev shell clean test show-info

# ==================== 默认变量 ====================
IMAGE_NAME = datamind-notebook
PORT = 8888
VOLUME = $(PWD):/workspace

# 构建类型 (development, testing, production)
BUILD_TYPE ?= production

# 缓存控制
NO_CACHE ?= false

# 镜像源配置
PIP_INDEX_URL ?= https://pypi.tuna.tsinghua.edu.cn/simple
PIP_TRUSTED_HOST ?= pypi.tuna.tsinghua.edu.cn
PIP_EXTRA_INDEX_URL ?= ""

# 额外APT包（默认空）
EXTRA_APT_PACKAGES ?= ""

# 是否安装开发工具
INSTALL_DEV_TOOLS ?= false

# 是否清理构建依赖
CLEAN_BUILD_DEPS ?= true

# 版本信息
GIT_COMMIT = $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME = $(shell date +%Y%m%d-%H%M%S)
VERSION = $(BUILD_TYPE)-$(BUILD_TIME)-$(GIT_COMMIT)

# ==================== 构建参数 ====================
BUILD_ARGS = \
	--build-arg BUILD_TYPE=$(BUILD_TYPE) \
	--build-arg PIP_INDEX_URL=$(PIP_INDEX_URL) \
	--build-arg PIP_TRUSTED_HOST=$(PIP_TRUSTED_HOST) \
	--build-arg PIP_EXTRA_INDEX_URL=$(PIP_EXTRA_INDEX_URL) \
	--build-arg EXTRA_APT_PACKAGES="$(EXTRA_APT_PACKAGES)" \
	--build-arg INSTALL_DEV_TOOLS=$(INSTALL_DEV_TOOLS) \
	--build-arg CLEAN_BUILD_DEPS=$(CLEAN_BUILD_DEPS) \
	--build-arg VERSION=$(VERSION) \
	--build-arg BUILD_TIME=$(BUILD_TIME) \
	--build-arg GIT_COMMIT=$(GIT_COMMIT)

# 缓存控制
ifeq ($(NO_CACHE), true)
	CACHE_OPTION = --no-cache
else
	CACHE_OPTION = 
endif

# ==================== 帮助信息 ====================
help:
	@echo "=========================================================="
	@echo "datamind-notebook 构建命令"
	@echo "=========================================================="
	@echo ""
	@echo "基础构建:"
	@echo "  make build                           - 使用当前配置构建（默认production）"
	@echo "  make build-dev                       - 构建开发环境"
	@echo "  make build-test                      - 构建测试环境"
	@echo "  make build-prod                      - 构建生产环境"
	@echo ""
	@echo "无缓存构建:"
	@echo "  make build-nocache                   - 无缓存构建（默认production）"
	@echo "  make build-dev-nocache               - 无缓存构建开发环境"
	@echo "  make build-test-nocache              - 无缓存构建测试环境"
	@echo "  make build-prod-nocache              - 无缓存构建生产环境"
	@echo ""
	@echo "镜像源选择:"
	@echo "  make build-tsinghua                  - 使用清华源"
	@echo "  make build-aliyun                    - 使用阿里源"
	@echo "  make build-official                  - 使用官方源"
	@echo "  make build-internal URL=xxx HOST=xxx - 使用内网源"
	@echo ""
	@echo "高级构建:"
	@echo "  make build-with-apt PKGS='pkg1 pkg2' - 安装额外APT包"
	@echo "  make build-clean-deps=false          - 保留构建依赖"
	@echo "  make build-dev-tools                 - 安装开发工具"
	@echo ""
	@echo "运行命令:"
	@echo "  make run                             - 运行容器"
	@echo "  make run-dev                         - 运行开发容器（带调试）"
	@echo "  make shell                           - 进入容器shell"
	@echo ""
	@echo "其他:"
	@echo "  make clean                           - 清理镜像"
	@echo "  make test                            - 测试镜像"
	@echo "  make show-info                       - 显示当前配置"
	@echo "=========================================================="

# ==================== 基础构建 ====================
build:
	@echo "=========================================================="
	@echo "构建配置:"
	@echo "  BUILD_TYPE: $(BUILD_TYPE)"
	@echo "  NO_CACHE: $(NO_CACHE)"
	@echo "  PIP_INDEX_URL: $(PIP_INDEX_URL)"
	@echo "  INSTALL_DEV_TOOLS: $(INSTALL_DEV_TOOLS)"
	@echo "  CLEAN_BUILD_DEPS: $(CLEAN_BUILD_DEPS)"
	@echo "  EXTRA_APT_PACKAGES: $(EXTRA_APT_PACKAGES)"
	@echo "  VERSION: $(VERSION)"
	@echo "=========================================================="
	docker build $(CACHE_OPTION) \
		$(BUILD_ARGS) \
		-t $(IMAGE_NAME):$(BUILD_TYPE)-$(GIT_COMMIT) \
		-t $(IMAGE_NAME):latest \
		.

# ==================== 无缓存构建 ====================
build-nocache:
	$(MAKE) build NO_CACHE=true

build-dev-nocache:
	$(MAKE) build-dev NO_CACHE=true

build-test-nocache:
	$(MAKE) build-test NO_CACHE=true

build-prod-nocache:
	$(MAKE) build-prod NO_CACHE=true

# ==================== 环境类型构建 ====================
build-dev:
	$(MAKE) build BUILD_TYPE=development INSTALL_DEV_TOOLS=true

build-test:
	$(MAKE) build BUILD_TYPE=testing INSTALL_DEV_TOOLS=false

build-prod:
	$(MAKE) build BUILD_TYPE=production INSTALL_DEV_TOOLS=false

# ==================== 镜像源选择 ====================
build-tsinghua:
	$(MAKE) build \
		PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
		PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn

build-tsinghua-nocache:
	$(MAKE) build-tsinghua NO_CACHE=true

build-aliyun:
	$(MAKE) build \
		PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/ \
		PIP_TRUSTED_HOST=mirrors.aliyun.com

build-aliyun-nocache:
	$(MAKE) build-aliyun NO_CACHE=true

build-official:
	$(MAKE) build \
		PIP_INDEX_URL=https://pypi.org/simple \
		PIP_TRUSTED_HOST=pypi.org

build-official-nocache:
	$(MAKE) build-official NO_CACHE=true

build-internal:
	@if [ -z "$(URL)" ] || [ -z "$(HOST)" ]; then \
		echo "错误: 需要指定 URL 和 HOST"; \
		echo "用法: make build-internal URL=http://内网地址/simple HOST=内网主机"; \
		exit 1; \
	fi
	$(MAKE) build PIP_INDEX_URL=$(URL) PIP_TRUSTED_HOST=$(HOST)

build-internal-nocache:
	$(MAKE) build-internal NO_CACHE=true

# ==================== 高级构建 ====================
build-with-apt:
	@if [ -z "$(PKGS)" ]; then \
		echo "错误: 需要指定 PKGS"; \
		echo "用法: make build-with-apt PKGS='vim htop'"; \
		exit 1; \
	fi
	$(MAKE) build EXTRA_APT_PACKAGES="$(PKGS)"

build-with-apt-nocache:
	$(MAKE) build-with-apt NO_CACHE=true

build-clean-deps:
	$(MAKE) build CLEAN_BUILD_DEPS=$(filter-out $@,$(MAKECMDGOALS))

build-dev-tools:
	$(MAKE) build INSTALL_DEV_TOOLS=true

build-dev-tools-nocache:
	$(MAKE) build-dev-tools NO_CACHE=true

# ==================== 运行命令 ====================
run:
	@echo "启动容器 (类型: $(BUILD_TYPE))..."
	docker run -it --rm \
		-p $(PORT):8888 \
		-v $(VOLUME) \
		-e BUILD_TYPE=$(BUILD_TYPE) \
		$(IMAGE_NAME):latest

run-dev:
	@echo "启动开发容器 (调试模式)..."
	docker run -it --rm \
		-p $(PORT):8888 \
		-p 5678:5678 \
		-v $(VOLUME) \
		-e BUILD_TYPE=development \
		-e DEBUG=true \
		$(IMAGE_NAME):latest

shell:
	docker run -it --rm \
		-v $(VOLUME) \
		--entrypoint /bin/bash \
		$(IMAGE_NAME):latest

# ==================== 其他命令 ====================
clean:
	@echo "清理镜像..."
	-docker rmi $(IMAGE_NAME):latest 2>/dev/null || true
	-docker rmi $$(docker images $(IMAGE_NAME) -q) 2>/dev/null || true

clean-all:
	@echo "清理所有镜像和缓存..."
	-docker rmi -f $$(docker images $(IMAGE_NAME) -q) 2>/dev/null || true
	-docker builder prune -f

test:
	@echo "测试镜像..."
	docker run --rm $(IMAGE_NAME):latest python --version
	docker run --rm $(IMAGE_NAME):latest pip list | grep jupyter
	@echo "测试通过！"

show-info:
	@echo "=========================================================="
	@echo "当前配置:"
	@echo "  IMAGE_NAME: $(IMAGE_NAME)"
	@echo "  BUILD_TYPE: $(BUILD_TYPE)"
	@echo "  NO_CACHE: $(NO_CACHE)"
	@echo "  PIP_INDEX_URL: $(PIP_INDEX_URL)"
	@echo "  INSTALL_DEV_TOOLS: $(INSTALL_DEV_TOOLS)"
	@echo "  CLEAN_BUILD_DEPS: $(CLEAN_BUILD_DEPS)"
	@echo "  EXTRA_APT_PACKAGES: $(EXTRA_APT_PACKAGES)"
	@echo "  GIT_COMMIT: $(GIT_COMMIT)"
	@echo "  BUILD_TIME: $(BUILD_TIME)"
	@echo "  VERSION: $(VERSION)"
	@echo "=========================================================="