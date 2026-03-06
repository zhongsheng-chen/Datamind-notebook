# ==========================================
# Makefile
# ==========================================

.PHONY: help build build-dev build-test build-prod \
        build-nocache build-dev-nocache build-test-nocache build-prod-nocache \
        build-tsinghua build-aliyun build-official build-mirror \
        build-with-apt build-clean-deps build-dev-tools \
        run run-dev run-lab run-with-token shell logs stop \
        clean clean-all test show-info save load push pull \
        version inspect history \
        builder-create builder-use builder-stop builder-rm \
        build-multi build-multi-push build-multi-dev build-multi-prod build-multi-test

# ==================== 默认变量 ====================
DEFAULT_REGISTRY  := docker.io
DEFAULT_OWNER := zhongsheng
DEFAULT_IMAGE_NAME := datamind-notebook

REGISTRY  ?= $(DEFAULT_REGISTRY)
OWNER ?= $(DEFAULT_OWNER)
IMAGE_NAME ?= $(DEFAULT_IMAGE_NAME)

FULL_IMAGE_NAME = $(REGISTRY)/$(OWNER)/$(IMAGE_NAME)
PORT = 8888
HOST_PORT ?= 8888
VOLUME = $(PWD)/notebooks:/home/jovyan/workspace
CONFIG_VOLUME = $(PWD)/config:/home/jovyan/.jupyter

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

# 是否生成元数据标签
NEED_METADATA ?= false

# 多架构支持
PLATFORMS ?= linux/amd64,linux/arm64
DEFAULT_PLATFORM ?= linux/amd64
BUILDX_BUILDER ?= datamind-builder

# 版本信息
GIT_COMMIT = $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_TAG = $(shell git describe --tags --exact-match 2>/dev/null || echo "")
GIT_DESCRIBE = $(shell git describe --tags --always 2>/dev/null || echo "dev-$(GIT_COMMIT)")
TIMESTAMP = $(shell date +%Y%m%d%H%M%S)
BUILD_TIME = $(shell date +"%Y-%m-%d %H:%M:%S")
BUILD_DATETIME = $(shell date +"%Y-%m-%dT%H:%M:%S%z")
BUILD_DATE = $(shell date +"%Y-%m-%d")
VERSION ?= $(if $(GIT_TAG),$(GIT_TAG),$(GIT_DESCRIBE))
BUILD_METADATA = $(BUILD_TYPE).$(TIMESTAMP).$(GIT_COMMIT)

# 颜色输出
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
BLUE = \033[0;34m
PURPLE = \033[0;35m
CYAN = \033[0;36m
NC = \033[0m

# 启用 Docker BuildKit
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# ==================== 构建参数 ====================
# 可缓存的构建参数（不含时间变量）
BUILD_ARGS_CACHEABLE = \
	--build-arg BUILD_TYPE=$(BUILD_TYPE) \
	--build-arg PIP_INDEX_URL=$(PIP_INDEX_URL) \
	--build-arg PIP_TRUSTED_HOST=$(PIP_TRUSTED_HOST) \
	--build-arg PIP_EXTRA_INDEX_URL="$(PIP_EXTRA_INDEX_URL)" \
	--build-arg EXTRA_APT_PACKAGES="$(EXTRA_APT_PACKAGES)" \
	--build-arg INSTALL_DEV_TOOLS=$(INSTALL_DEV_TOOLS) \
	--build-arg CLEAN_BUILD_DEPS=$(CLEAN_BUILD_DEPS) \
	--build-arg VERSION="$(VERSION)" \
	--build-arg GIT_COMMIT=$(GIT_COMMIT) \
	--build-arg BUILD_DATE="$(BUILD_DATE)"

# 标签参数（不影响缓存）
LABEL_ARGS = \
	--label build.time="$(BUILD_TIME)" \
	--label build.datetime="$(BUILD_DATETIME)" \
	--label timestamp="$(TIMESTAMP)"

# 标签
TAGS = -t $(IMAGE_NAME):latest \
       -t $(IMAGE_NAME):$(BUILD_TYPE) \
       -t $(IMAGE_NAME):$(VERSION)

# 当 VERSION 不包含 BUILD_TYPE 时，添加组合标签
ifneq ($(findstring $(BUILD_TYPE),$(VERSION)),$(BUILD_TYPE))
    TAGS += -t $(IMAGE_NAME):$(VERSION)-$(BUILD_TYPE)
endif

# 生产环境添加 stable 标签
ifeq ($(BUILD_TYPE), production)
    TAGS += -t $(IMAGE_NAME):stable
endif

# 只在需要追溯时保留元数据标签
ifeq ($(NEED_METADATA), true)
    TAGS += -t $(IMAGE_NAME):$(BUILD_METADATA)
endif

# 缓存控制
ifeq ($(NO_CACHE), true)
	CACHE_OPTION = --no-cache
else
	CACHE_OPTION = 
endif

# ==================== 帮助信息 ====================
help:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)datamind-notebook 构建命令$(NC)"
	@echo "$(CYAN)==========================================================$(NC)"
	@echo ""
	@echo "$(YELLOW)基础构建:$(NC)"
	@echo "  make build                            - 使用当前配置构建（默认production）"
	@echo "  make build-dev                        - 构建开发环境"
	@echo "  make build-test                       - 构建测试环境"
	@echo "  make build-prod                       - 构建生产环境"
	@echo ""
	@echo "$(YELLOW)无缓存构建:$(NC)"
	@echo "  make build-nocache                    - 无缓存构建（默认production）"
	@echo "  make build-dev-nocache                - 无缓存构建开发环境"
	@echo "  make build-test-nocache               - 无缓存构建测试环境"
	@echo "  make build-prod-nocache               - 无缓存构建生产环境"
	@echo ""
	@echo "$(YELLOW)镜像源选择:$(NC)"
	@echo "  make build-tsinghua                   - 使用清华源"
	@echo "  make build-tsinghua-nocache           - 无缓存构建使用清华源"
	@echo "  make build-aliyun                     - 使用阿里源"
	@echo "  make build-aliyun-nocache             - 无缓存构建使用阿里源"
	@echo "  make build-official                   - 使用官方源"
	@echo "  make build-official-nocache           - 无缓存构建使用官方源"
	@echo "  make build-mirror URL=xxx HOST=xxx    - 使用自定义镜像源"
	@echo "  make build-mirror-nocache             - 无缓存构建使用自定义镜像源"
	@echo ""
	@echo "$(YELLOW)高级构建:$(NC)"
	@echo "  make build-with-apt PKGS='pkg1 pkg2'  - 安装额外APT包"
	@echo "  make build-with-apt-nocache           - 无缓存构建安装额外APT包"
	@echo "  make build-clean-deps=false           - 保留构建依赖"
	@echo "  make build-dev-tools                  - 安装开发工具"
	@echo "  make build-dev-tools-nocache          - 无缓存构建安装开发工具"
	@echo "  make build-with-token TOKEN=xxx       - 构建时使用私有源（需要token）"
	@echo ""
	@echo "$(YELLOW)运行命令:$(NC)"
	@echo "  make run                              - 运行容器"
	@echo "  make run-dev                          - 运行开发容器（带调试）"
	@echo "  make run-lab                          - 运行 JupyterLab"
	@echo "  make run-with-token TOKEN=xxx         - 使用指定token运行"
	@echo "  make run-background                   - 后台运行容器"
	@echo "  make shell                            - 进入容器shell"
	@echo "  make logs                             - 查看容器日志"
	@echo "  make stop                             - 停止容器"
	@echo ""
	@echo "$(YELLOW)镜像管理:$(NC)"
	@echo "  make save                             - 保存镜像到文件"
	@echo "  make load FILE=xxx.tar.gz             - 从文件加载镜像"
	@echo "  make push                             - 推送镜像到仓库"
	@echo "  make pull                             - 拉取镜像"
	@echo "  make version                          - 显示版本信息"
	@echo "  make inspect                          - 查看镜像详细信息"
	@echo "  make history                          - 查看镜像构建历史"
	@echo ""
	@echo "$(YELLOW)多架构构建:$(NC)"
	@echo "  make builder-create                   - 创建多架构构建器"
	@echo "  make builder-use                      - 使用多架构构建器"  
	@echo "  make builder-stop                     - 停止构建器"
	@echo "  make builder-rm                       - 删除构建器"
	@echo "  make build-multi                      - 构建多架构镜像（到缓存）"
	@echo "  make build-multi-push                 - 构建并推送多架构镜像"
	@echo "  make build-multi-local                - 本地构建（当前平台）"
	@echo "  make build-multi-dev                  - 构建多架构开发镜像并推送"
	@echo "  make build-multi-prod                 - 构建多架构生产镜像并推送"
	@echo "  make build-multi-test                 - 构建多架构测试镜像并推送"
	@echo ""
	@echo "$(YELLOW)多架构查看:$(NC)"
	@echo "  make inspect-multi                    - 查看当前版本多架构镜像信息"
	@echo "  make inspect-multi-latest             - 查看最新多架构镜像信息"
	@echo "  make inspect-multi-raw                - 查看多架构镜像原始 Manifest"
	@echo "  make list-builders                    - 查看所有构建器"
	@echo "  make inspect-builder                  - 查看当前构建器详细信息"
	@echo "  make inspect-builder-cache            - 查看构建器缓存使用情况"
	@echo ""
	@echo "$(YELLOW)测试和清理:$(NC)"
	@echo "  make test                             - 测试镜像"
	@echo "  make clean                            - 清理镜像"
	@echo "  make clean-all                        - 清理所有镜像和缓存"
	@echo ""
	@echo "$(YELLOW)信息显示:$(NC)"
	@echo "  make show-info                        - 显示当前配置"
	@echo "  make version                          - 显示镜像版本信息"
	@echo "$(CYAN)==========================================================$(NC)"

# ==================== 基础构建 ====================
build:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)构建配置:$(NC)"
	@echo "  $(YELLOW)BUILD_TYPE:$(NC) $(BUILD_TYPE)"
	@echo "  $(YELLOW)BUILD_DATE:$(NC) $(BUILD_DATE)"
	@echo "  $(YELLOW)PIP_INDEX_URL:$(NC) $(PIP_INDEX_URL)"
	@echo "  $(YELLOW)PIP_TRUSTED_HOST:$(NC) $(PIP_TRUSTED_HOST)"
	@echo "  $(YELLOW)NO_CACHE:$(NC) $(NO_CACHE)"
	@echo "  $(YELLOW)INSTALL_DEV_TOOLS:$(NC) $(INSTALL_DEV_TOOLS)"
	@echo "  $(YELLOW)CLEAN_BUILD_DEPS:$(NC) $(CLEAN_BUILD_DEPS)"
	@echo "  $(YELLOW)EXTRA_APT_PACKAGES:$(NC) $(EXTRA_APT_PACKAGES)"
	@echo "  $(YELLOW)VERSION:$(NC) $(VERSION)"
	@echo "  $(YELLOW)GIT_COMMIT:$(NC) $(GIT_COMMIT)"
	@echo "$(CYAN)==========================================================$(NC)"
	docker build $(CACHE_OPTION) \
		$(BUILD_ARGS_CACHEABLE) \
		$(LABEL_ARGS) \
		$(TAGS) \
		.
	@echo "$(GREEN)✓ 构建完成！$(NC)"
	@echo "  生成的标签:"
	@echo "    - $(IMAGE_NAME):latest"
	@echo "    - $(IMAGE_NAME):$(BUILD_TYPE)"
	@echo "    - $(IMAGE_NAME):$(VERSION)"
	@if [ "$(VERSION)" != "$(VERSION)-$(BUILD_TYPE)" ]; then \
		echo "    - $(IMAGE_NAME):$(VERSION)-$(BUILD_TYPE)"; \
	fi
	@if [ "$(BUILD_TYPE)" = "production" ]; then \
		echo "    - $(IMAGE_NAME):stable"; \
	fi

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

build-mirror:
	@if [ -z "$(URL)" ] || [ -z "$(HOST)" ]; then \
		echo "$(RED)错误: 需要指定 URL 和 HOST$(NC)"; \
		echo "用法: make build-mirror URL=http://内网地址/simple HOST=内网主机"; \
		exit 1; \
	fi
	$(MAKE) build PIP_INDEX_URL=$(URL) PIP_TRUSTED_HOST=$(HOST)

build-mirror-nocache:
	$(MAKE) build-mirror NO_CACHE=true

build-with-token:
	@if [ -z "$(TOKEN)" ]; then \
		echo "$(RED)错误: 需要指定 TOKEN$(NC)"; \
		echo "用法: make build-with-token TOKEN=xxx"; \
		exit 1; \
	fi
	$(MAKE) build PIP_EXTRA_INDEX_URL="https://__token__:$(TOKEN)@私有源地址/simple"

# ==================== 高级构建 ====================
build-with-apt:
	@if [ -z "$(PKGS)" ]; then \
		echo "$(RED)错误: 需要指定 PKGS$(NC)"; \
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
	@echo "$(GREEN)启动容器 (类型: $(BUILD_TYPE))...$(NC)"
	docker run -it --rm \
		-p $(HOST_PORT):$(PORT) \
		-v $(VOLUME) \
		-v $(CONFIG_VOLUME) \
		-e BUILD_TYPE=$(BUILD_TYPE) \
		--name $(IMAGE_NAME)-$(shell date +%s) \
		$(IMAGE_NAME):latest

run-dev:
	@echo "$(GREEN)启动开发容器 (调试模式)...$(NC)"
	docker run -it --rm \
		-p $(HOST_PORT):$(PORT) \
		-p 5678:5678 \
		-v $(VOLUME) \
		-v $(CONFIG_VOLUME) \
		-e BUILD_TYPE=development \
		-e DEBUG=true \
		--name $(IMAGE_NAME)-dev-$(shell date +%s) \
		$(IMAGE_NAME):latest

run-lab:
	@echo "$(GREEN)启动 JupyterLab...$(NC)"
	docker run -it --rm \
		-p $(HOST_PORT):$(PORT) \
		-v $(VOLUME) \
		-v $(CONFIG_VOLUME) \
		-e JUPYTER_MODE=lab \
		$(IMAGE_NAME):latest

run-with-token:
	@if [ -z "$(TOKEN)" ]; then \
		echo "$(RED)错误: 需要指定 TOKEN$(NC)"; \
		echo "用法: make run-with-token TOKEN=xxx"; \
		exit 1; \
	fi
	docker run -it --rm \
		-p $(HOST_PORT):$(PORT) \
		-v $(VOLUME) \
		-v $(CONFIG_VOLUME) \
		-e JUPYTER_TOKEN=$(TOKEN) \
		$(IMAGE_NAME):latest

run-background:
	@echo "$(GREEN)后台启动容器...$(NC)"
	docker run -d \
		-p $(HOST_PORT):$(PORT) \
		-v $(VOLUME) \
		-v $(CONFIG_VOLUME) \
		--restart unless-stopped \
		--name $(IMAGE_NAME)-service \
		$(IMAGE_NAME):latest

shell:
	@echo "$(GREEN)进入容器shell...$(NC)"
	docker run -it --rm \
		-v $(VOLUME) \
		-v $(CONFIG_VOLUME) \
		--entrypoint /bin/bash \
		$(IMAGE_NAME):latest

logs:
	@docker logs -f $(IMAGE_NAME)-service 2>/dev/null || \
	 echo "$(YELLOW)没有运行中的容器或指定容器名称$(NC)"

stop:
	@echo "$(YELLOW)停止容器...$(NC)"
	-docker stop $(IMAGE_NAME)-service 2>/dev/null || true
	@echo "$(GREEN)✓ 已停止$(NC)"

# ==================== 镜像管理 ====================
save:
	@echo "$(GREEN)保存镜像到文件...$(NC)"
	$(eval SAVE_FILE := $(IMAGE_NAME)-$(VERSION).tar.gz)
	$(eval IMAGE_SIZE := $(shell docker image inspect $(IMAGE_NAME):latest --format='{{.Size}}' | awk '{printf "%.2f MB", $$1/1024/1024}'))
	$(eval ORIGINAL_SIZE_BYTES := $(shell docker image inspect $(IMAGE_NAME):latest --format='{{.Size}}'))
	@echo "  $(YELLOW)镜像:$(NC) $(IMAGE_NAME):latest ($(IMAGE_SIZE))"
	@echo "  $(YELLOW)保存到:$(NC) $(SAVE_FILE)"
	@echo "  $(YELLOW)正在保存，请稍候...$(NC)"
	
	@# 检查 pv 是否安装，如果安装则显示进度，否则直接保存
	@if command -v pv >/dev/null 2>&1; then \
		docker save $(IMAGE_NAME):latest | pv -s $(ORIGINAL_SIZE_BYTES) | gzip > $(SAVE_FILE); \
	else \
		docker save $(IMAGE_NAME):latest | gzip > $(SAVE_FILE); \
	fi
	
	@# 获取文件信息
	$(eval FILE_SIZE := $(shell du -h $(SAVE_FILE) | cut -f1))
	$(eval FILE_SIZE_BYTES := $(shell stat -c%s $(SAVE_FILE) 2>/dev/null || stat -f%z $(SAVE_FILE) 2>/dev/null))
	$(eval COMPRESSION_RATIO := $(shell echo "scale=2; $(FILE_SIZE_BYTES)*100/$(ORIGINAL_SIZE_BYTES)" | bc 2>/dev/null || echo "N/A"))
	$(eval CREATE_TIME := $(shell date -r $(SAVE_FILE) +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date))
	
	@echo "$(GREEN)✓ 镜像保存成功！$(NC)"
	@echo "  $(YELLOW)文件名称:$(NC) $(SAVE_FILE)"
	@echo "  $(YELLOW)文件大小:$(NC) $(FILE_SIZE) ($(FILE_SIZE_BYTES) 字节)"
	@echo "  $(YELLOW)原始大小:$(NC) $(IMAGE_SIZE) ($(ORIGINAL_SIZE_BYTES) 字节)"
	@echo "  $(YELLOW)压缩率:$(NC) $(COMPRESSION_RATIO)%"
	@echo "  $(YELLOW)文件路径:$(NC) $(PWD)/$(SAVE_FILE)"
	@echo "  $(YELLOW)创建时间:$(NC) $(CREATE_TIME)"
	@echo ""
	@echo "  $(CYAN)加载此镜像:$(NC)"
	@echo "    make load FILE=$(SAVE_FILE)"
	@echo "    # 或直接使用 docker"
	@echo "    docker load < $(SAVE_FILE)"

load:
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)错误: 需要指定 FILE$(NC)"; \
		echo "用法: make load FILE=xxx.tar.gz"; \
		exit 1; \
	fi
	docker load < $(FILE)

push:
	@echo "$(GREEN)推送镜像到仓库...$(NC)"
	@echo "$(YELLOW)检测是否支持多架构...$(NC)"
	@if docker buildx inspect $(BUILDX_BUILDER) >/dev/null 2>&1; then \
		echo "$(GREEN)使用多架构推送...$(NC)"; \
		docker buildx use $(BUILDX_BUILDER); \
		docker buildx build \
			--platform $(PLATFORMS) \
			--push \
			$(CACHE_OPTION) \
			$(BUILD_ARGS_CACHEABLE) \
			$(LABEL_ARGS) \
			-t $(FULL_IMAGE_NAME):$(VERSION) \
			-t $(FULL_IMAGE_NAME):latest \
			-t $(FULL_IMAGE_NAME):$(BUILD_TYPE) \
			.; \
	else \
		echo "$(YELLOW)使用传统方式推送（仅 $(DEFAULT_PLATFORM)）...$(NC)"; \
		docker tag $(IMAGE_NAME):latest $(FULL_IMAGE_NAME):$(VERSION); \
		docker tag $(IMAGE_NAME):latest $(FULL_IMAGE_NAME):latest; \
		docker push $(FULL_IMAGE_NAME):$(VERSION); \
		docker push $(FULL_IMAGE_NAME):latest; \
	fi
	@echo "$(GREEN)✓ 已推送到 $(FULL_IMAGE_NAME)$(NC)"

pull:
	docker pull $(FULL_IMAGE_NAME):latest

version:
	@echo "$(CYAN)镜像版本信息:$(NC)"
	@docker run --rm $(IMAGE_NAME):latest sh -c 'echo "  VERSION: $$VERSION"; echo "  BUILD_TIME: $$BUILD_TIME"; echo "  GIT_COMMIT: $$GIT_COMMIT"; echo "  BUILD_TYPE: $$BUILD_TYPE"'

inspect:
	docker inspect $(IMAGE_NAME):latest | jq '.[0].Config.Labels' 2>/dev/null || \
	docker inspect $(IMAGE_NAME):latest

history:
	docker history $(IMAGE_NAME):latest

# ==================== 多架构镜像查看命令 ====================
inspect-multi:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)查看多架构镜像信息$(NC)"
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "  $(YELLOW)镜像:$(NC) $(FULL_IMAGE_NAME):$(VERSION)"
	@echo "$(CYAN)==========================================================$(NC)"
	@if docker buildx imagetools inspect $(FULL_IMAGE_NAME):$(VERSION) >/dev/null 2>&1; then \
		docker buildx imagetools inspect $(FULL_IMAGE_NAME):$(VERSION); \
	elif docker buildx imagetools inspect $(IMAGE_NAME):$(VERSION) >/dev/null 2>&1; then \
		docker buildx imagetools inspect $(IMAGE_NAME):$(VERSION); \
	else \
		echo "$(RED)错误: 未找到镜像 $(FULL_IMAGE_NAME):$(VERSION) 或 $(IMAGE_NAME):$(VERSION)$(NC)"; \
		echo "请先运行 'make build-multi' 或 'make build-multi-push' 构建镜像"; \
		exit 1; \
	fi

inspect-multi-latest:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)查看最新多架构镜像信息$(NC)"
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "  $(YELLOW)镜像:$(NC) $(FULL_IMAGE_NAME):latest"
	@echo "$(CYAN)==========================================================$(NC)"
	@if docker buildx imagetools inspect $(FULL_IMAGE_NAME):latest >/dev/null 2>&1; then \
		docker buildx imagetools inspect $(FULL_IMAGE_NAME):latest; \
	elif docker buildx imagetools inspect $(IMAGE_NAME):latest >/dev/null 2>&1; then \
		docker buildx imagetools inspect $(IMAGE_NAME):latest; \
	else \
		echo "$(RED)错误: 未找到镜像 $(FULL_IMAGE_NAME):latest 或 $(IMAGE_NAME):latest$(NC)"; \
		echo "请先运行 'make build-multi' 或 'make build-multi-push' 构建镜像"; \
		exit 1; \
	fi

inspect-multi-raw:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)查看多架构镜像原始 Manifest$(NC)"
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "  $(YELLOW)镜像:$(NC) $(FULL_IMAGE_NAME):$(VERSION)"
	@echo "$(CYAN)==========================================================$(NC)"
	@if docker buildx imagetools inspect $(FULL_IMAGE_NAME):$(VERSION) --raw >/dev/null 2>&1; then \
		docker buildx imagetools inspect $(FULL_IMAGE_NAME):$(VERSION) --raw | jq '.' 2>/dev/null || cat; \
	elif docker buildx imagetools inspect $(IMAGE_NAME):$(VERSION) --raw >/dev/null 2>&1; then \
		docker buildx imagetools inspect $(IMAGE_NAME):$(VERSION) --raw | jq '.' 2>/dev/null || cat; \
	else \
		echo "$(RED)错误: 未找到镜像 $(FULL_IMAGE_NAME):$(VERSION) 或 $(IMAGE_NAME):$(VERSION)$(NC)"; \
		echo "请先运行 'make build-multi' 或 'make build-multi-push' 构建镜像"; \
		exit 1; \
	fi

list-builders:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)查看所有构建器$(NC)"
	@echo "$(CYAN)==========================================================$(NC)"
	docker buildx ls

inspect-builder-cache:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)查看构建器缓存使用情况$(NC)"
	@echo "$(CYAN)==========================================================$(NC)"
	docker buildx du

inspect-builder:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)查看构建器详细信息$(NC)"
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "  $(YELLOW)构建器:$(NC) $(BUILDX_BUILDER)"
	@echo "$(CYAN)==========================================================$(NC)"
	docker buildx inspect $(BUILDX_BUILDER)

# ==================== 多架构构建 ====================
builder-create:
	@echo "$(GREEN)创建多架构构建器 $(BUILDX_BUILDER)...$(NC)"
	@if docker buildx inspect $(BUILDX_BUILDER) >/dev/null 2>&1; then \
		echo "$(YELLOW)构建器 $(BUILDX_BUILDER) 已存在，跳过创建$(NC)"; \
	else \
		docker buildx create --name $(BUILDX_BUILDER) --driver docker-container --bootstrap; \
		echo "$(GREEN)✓ 构建器创建完成$(NC)"; \
	fi
	@echo "使用 'make builder-use' 切换到该构建器"

builder-use:
	@echo "$(GREEN)切换到构建器 $(BUILDX_BUILDER)...$(NC)"
	docker buildx use $(BUILDX_BUILDER)
	@echo "$(GREEN)✓ 已切换到构建器 $(BUILDX_BUILDER)$(NC)"

builder-stop:
	@echo "$(YELLOW)停止构建器 $(BUILDX_BUILDER)...$(NC)"
	-docker buildx stop $(BUILDX_BUILDER)
	@echo "$(GREEN)✓ 构建器已停止$(NC)"

builder-rm:
	@echo "$(YELLOW)删除构建器 $(BUILDX_BUILDER)...$(NC)"
	-docker buildx rm $(BUILDX_BUILDER)
	@echo "$(GREEN)✓ 构建器已删除$(NC)"

build-multi:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)多架构镜像构建$(NC)"
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(YELLOW)构建配置:$(NC)"
	@echo "  $(YELLOW)BUILD_TYPE:$(NC) $(BUILD_TYPE)"
	@echo "  $(YELLOW)PLATFORMS:$(NC) $(PLATFORMS)"
	@echo "  $(YELLOW)VERSION:$(NC) $(VERSION)"
	@echo "  $(YELLOW)GIT_COMMIT:$(NC) $(GIT_COMMIT)"
	@echo "$(CYAN)==========================================================$(NC)"
	
	# 检查构建器是否存在
	@if ! docker buildx inspect $(BUILDX_BUILDER) >/dev/null 2>&1; then \
		echo "$(YELLOW)构建器 $(BUILDX_BUILDER) 不存在，正在创建...$(NC)"; \
		$(MAKE) builder-create; \
	else \
		echo "$(GREEN)使用现有构建器 $(BUILDX_BUILDER)$(NC)"; \
	fi
	
	# 确保使用正确的构建器
	docker buildx use $(BUILDX_BUILDER)
	
	# 构建多架构镜像（构建到构建器缓存，不加载到本地）
	@echo "$(YELLOW)注意: 多架构镜像只构建到构建器缓存，不会加载到本地$(NC)"
	@echo "$(YELLOW)如需加载到本地，请使用 'make build' 构建单架构镜像$(NC)"
	docker buildx build \
		--platform $(PLATFORMS) \
		$(CACHE_OPTION) \
		$(BUILD_ARGS_CACHEABLE) \
		$(LABEL_ARGS) \
		$(TAGS) \
		.
	@echo "$(GREEN)✓ 多架构构建完成！$(NC)"
	@echo "  支持的平台: $(PLATFORMS)"
	@echo "  镜像已构建到构建器缓存中"
	@echo "  使用 'make build-multi-push' 推送到仓库"

build-multi-push:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)多架构镜像构建并推送$(NC)"
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(YELLOW)构建配置:$(NC)"
	@echo "  $(YELLOW)BUILD_TYPE:$(NC) $(BUILD_TYPE)"
	@echo "  $(YELLOW)PLATFORMS:$(NC) $(PLATFORMS)"
	@echo "  $(YELLOW)VERSION:$(NC) $(VERSION)"
	@echo "  $(YELLOW)FULL_IMAGE_NAME:$(NC) $(FULL_IMAGE_NAME)"
	@echo "$(CYAN)==========================================================$(NC)"
	
	# 检查构建器是否存在
	@if ! docker buildx inspect $(BUILDX_BUILDER) >/dev/null 2>&1; then \
		echo "$(YELLOW)构建器 $(BUILDX_BUILDER) 不存在，正在创建...$(NC)"; \
		$(MAKE) builder-create; \
	else \
		echo "$(GREEN)使用现有构建器 $(BUILDX_BUILDER)$(NC)"; \
	fi
	
	# 确保使用正确的构建器
	docker buildx use $(BUILDX_BUILDER)
	
	# 构建并推送多架构镜像
	docker buildx build \
		--platform $(PLATFORMS) \
		--push \
		$(CACHE_OPTION) \
		$(BUILD_ARGS_CACHEABLE) \
		$(LABEL_ARGS) \
		-t $(FULL_IMAGE_NAME):$(VERSION) \
		-t $(FULL_IMAGE_NAME):latest \
		-t $(FULL_IMAGE_NAME):$(BUILD_TYPE) \
		.
	@echo "$(GREEN)✓ 多架构镜像已推送！$(NC)"
	@echo "  镜像地址: $(FULL_IMAGE_NAME):$(VERSION)"
	@echo "  支持的平台: $(PLATFORMS)"

build-multi-local:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)多架构构建器 - 本地构建（当前平台）$(NC)"
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(YELLOW)构建配置:$(NC)"
	@echo "  $(YELLOW)BUILD_TYPE:$(NC) $(BUILD_TYPE)"
	@echo "  $(YELLOW)PLATFORM:$(NC) $(DEFAULT_PLATFORM)"
	@echo "  $(YELLOW)VERSION:$(NC) $(VERSION)"
	@echo "  $(YELLOW)GIT_COMMIT:$(NC) $(GIT_COMMIT)"
	@echo "$(CYAN)==========================================================$(NC)"
	
	# 检查构建器是否存在
	@if ! docker buildx inspect $(BUILDX_BUILDER) >/dev/null 2>&1; then \
		echo "$(YELLOW)构建器 $(BUILDX_BUILDER) 不存在，正在创建...$(NC)"; \
		$(MAKE) builder-create; \
	else \
		echo "$(GREEN)使用现有构建器 $(BUILDX_BUILDER)$(NC)"; \
	fi
	
	# 确保使用正确的构建器
	docker buildx use $(BUILDX_BUILDER)
	
	# 构建单平台镜像并加载到本地
	docker buildx build \
		--platform $(DEFAULT_PLATFORM) \
		--load \
		$(CACHE_OPTION) \
		$(BUILD_ARGS_CACHEABLE) \
		$(LABEL_ARGS) \
		$(TAGS) \
		.
	@echo "$(GREEN)✓ 本地构建完成！$(NC)"
	@echo "  平台: $(DEFAULT_PLATFORM)"
	@echo "  生成的标签:"
	@echo "    - $(IMAGE_NAME):latest"
	@echo "    - $(IMAGE_NAME):$(BUILD_TYPE)"
	@echo "    - $(IMAGE_NAME):$(VERSION)"

build-multi-dev:
	$(MAKE) build-multi-push BUILD_TYPE=development INSTALL_DEV_TOOLS=true

build-multi-prod:
	$(MAKE) build-multi-push BUILD_TYPE=production INSTALL_DEV_TOOLS=false

build-multi-test:
	$(MAKE) build-multi-push BUILD_TYPE=testing INSTALL_DEV_TOOLS=false

# ==================== 测试命令 ====================
test:
	@echo "$(YELLOW)测试镜像...$(NC)"
	@echo "1. 检查 Python 版本:"
	docker run --rm $(IMAGE_NAME):latest python --version
	@echo ""
	@echo "2. 检查 Jupyter 安装:"
	docker run --rm $(IMAGE_NAME):latest pip list | grep -E "jupyter|notebook|lab"
	@echo ""
	@echo "3. 检查用户:"
	docker run --rm $(IMAGE_NAME):latest whoami
	@echo ""
	@echo "$(GREEN)✓ 所有测试通过！$(NC)"

# ==================== 清理命令 ====================
clean:
	@echo "$(YELLOW)清理镜像...$(NC)"
	-docker rmi $(IMAGE_NAME):latest 2>/dev/null || true
	-docker rmi $$(docker images $(IMAGE_NAME) -q) 2>/dev/null || true
	@echo "$(GREEN)✓ 清理完成$(NC)"

clean-all:
	@echo "$(YELLOW)清理所有镜像和缓存...$(NC)"
	-docker rmi -f $$(docker images $(IMAGE_NAME) -q) 2>/dev/null || true
	-docker builder prune -f
	-docker system prune -f
	@echo "$(GREEN)✓ 清理完成$(NC)"

# ==================== 信息显示 ====================
show-info:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)当前配置:$(NC)"
	@echo "  $(YELLOW)IMAGE_NAME:$(NC) $(IMAGE_NAME)"
	@echo "  $(YELLOW)FULL_IMAGE_NAME:$(NC) $(FULL_IMAGE_NAME)"
	@echo "  $(YELLOW)BUILD_TYPE:$(NC) $(BUILD_TYPE)"
	@echo "  $(YELLOW)BUILD_TIME:$(NC) $(BUILD_TIME)"
	@echo "  $(YELLOW)PIP_INDEX_URL:$(NC) $(PIP_INDEX_URL)"
	@echo "  $(YELLOW)PIP_TRUSTED_HOST:$(NC) $(PIP_TRUSTED_HOST)"
	@echo "  $(YELLOW)NO_CACHE:$(NC) $(NO_CACHE)"
	@echo "  $(YELLOW)INSTALL_DEV_TOOLS:$(NC) $(INSTALL_DEV_TOOLS)"
	@echo "  $(YELLOW)CLEAN_BUILD_DEPS:$(NC) $(CLEAN_BUILD_DEPS)"
	@echo "  $(YELLOW)EXTRA_APT_PACKAGES:$(NC) $(EXTRA_APT_PACKAGES)"
	@echo "  $(YELLOW)VERSION:$(NC) $(VERSION)"
	@echo "  $(YELLOW)GIT_COMMIT:$(NC) $(GIT_COMMIT)"
	@echo "  $(YELLOW)PLATFORMS:$(NC) $(PLATFORMS)"
	@echo "  $(YELLOW)PORT:$(NC) $(PORT)"
	@echo "  $(YELLOW)HOST_PORT:$(NC) $(HOST_PORT)"
	@echo "$(CYAN)==========================================================$(NC)"