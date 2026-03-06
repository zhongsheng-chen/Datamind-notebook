# ==========================================
# Makefile - Datamind Jupyter Notebook Builder
# ==========================================

.PHONY: help build build-dev build-test build-prod \
        build-nocache build-dev-nocache build-test-nocache build-prod-nocache \
        build-tsinghua build-aliyun build-official build-mirror \
        build-with-apt build-clean-deps build-dev-tools \
        run run-dev run-lab run-with-token shell logs stop \
        clean clean-all test show-info save load push pull \
        version inspect history

# ==================== 默认变量 ====================
IMAGE_NAME = datamind-notebook
REGISTRY ?= docker.io
NAMESPACE ?= $(USER)
FULL_IMAGE_NAME = $(REGISTRY)/$(NAMESPACE)/$(IMAGE_NAME)
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

# 版本信息
GIT_COMMIT = $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME = $(shell date +%Y-%m-%d\ %H:%M:%S)
VERSION = $(BUILD_TYPE)-$(shell date +%Y%m%d%H%M%S)-$(GIT_COMMIT)

# 颜色输出
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
BLUE = \033[0;34m
PURPLE = \033[0;35m
CYAN = \033[0;36m
NC = \033[0m

# ==================== 构建参数 ====================
BUILD_ARGS = \
	--build-arg BUILD_TYPE=$(BUILD_TYPE) \
	--build-arg PIP_INDEX_URL=$(PIP_INDEX_URL) \
	--build-arg PIP_TRUSTED_HOST=$(PIP_TRUSTED_HOST) \
	--build-arg PIP_EXTRA_INDEX_URL=$(PIP_EXTRA_INDEX_URL) \
	--build-arg EXTRA_APT_PACKAGES="$(EXTRA_APT_PACKAGES)" \
	--build-arg INSTALL_DEV_TOOLS=$(INSTALL_DEV_TOOLS) \
	--build-arg CLEAN_BUILD_DEPS=$(CLEAN_BUILD_DEPS) \
	--build-arg VERSION="$(VERSION)" \
	--build-arg BUILD_TIME="$(BUILD_TIME)" \
	--build-arg GIT_COMMIT=$(GIT_COMMIT)

# 标签
TAGS = -t $(IMAGE_NAME):$(BUILD_TYPE)-$(GIT_COMMIT) \
       -t $(IMAGE_NAME):$(BUILD_TYPE)-latest \
       -t $(IMAGE_NAME):latest

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
	@echo "  make build                           - 使用当前配置构建（默认production）"
	@echo "  make build-dev                       - 构建开发环境"
	@echo "  make build-test                      - 构建测试环境"
	@echo "  make build-prod                      - 构建生产环境"
	@echo ""
	@echo "$(YELLOW)无缓存构建:$(NC)"
	@echo "  make build-nocache                   - 无缓存构建（默认production）"
	@echo "  make build-dev-nocache               - 无缓存构建开发环境"
	@echo "  make build-test-nocache              - 无缓存构建测试环境"
	@echo "  make build-prod-nocache              - 无缓存构建生产环境"
	@echo ""
	@echo "$(YELLOW)镜像源选择:$(NC)"
	@echo "  make build-tsinghua                  - 使用清华源"
	@echo "  make build-aliyun                    - 使用阿里源"
	@echo "  make build-official                  - 使用官方源"
	@echo "  make build-mirror URL=xxx HOST=xxx   - 使用自定义镜像源"
	@echo ""
	@echo "$(YELLOW)高级构建:$(NC)"
	@echo "  make build-with-apt PKGS='pkg1 pkg2' - 安装额外APT包"
	@echo "  make build-clean-deps=false          - 保留构建依赖"
	@echo "  make build-dev-tools                  - 安装开发工具"
	@echo "  make build-with-token TOKEN=xxx       - 构建时使用私有源（需要token）"
	@echo ""
	@echo "$(YELLOW)运行命令:$(NC)"
	@echo "  make run                              - 运行容器"
	@echo "  make run-dev                          - 运行开发容器（带调试）"
	@echo "  make run-lab                          - 运行 JupyterLab"
	@echo "  make run-with-token TOKEN=xxx         - 使用指定token运行"
	@echo "  make shell                            - 进入容器shell"
	@echo "  make logs                             - 查看容器日志"
	@echo "  make stop                             - 停止容器"
	@echo ""
	@echo "$(YELLOW)镜像管理:$(NC)"
	@echo "  make save                             - 保存镜像到文件"
	@echo "  make load                             - 从文件加载镜像"
	@echo "  make push                             - 推送镜像到仓库"
	@echo "  make pull                             - 拉取镜像"
	@echo "  make version                          - 显示版本信息"
	@echo "  make inspect                          - 查看镜像详细信息"
	@echo "  make history                          - 查看镜像构建历史"
	@echo ""
	@echo "$(YELLOW)其他:$(NC)"
	@echo "  make clean                            - 清理镜像"
	@echo "  make clean-all                        - 清理所有镜像和缓存"
	@echo "  make test                             - 测试镜像"
	@echo "  make show-info                        - 显示当前配置"
	@echo "$(CYAN)==========================================================$(NC)"

# ==================== 基础构建 ====================
build:
	@echo "$(CYAN)==========================================================$(NC)"
	@echo "$(GREEN)构建配置:$(NC)"
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
	@echo "$(CYAN)==========================================================$(NC)"
	docker build $(CACHE_OPTION) \
		$(BUILD_ARGS) \
		$(TAGS) \
		.
	@echo "$(GREEN)✓ 构建完成！$(NC)"
	@echo "  镜像标签: $(IMAGE_NAME):$(BUILD_TYPE)-$(GIT_COMMIT), $(IMAGE_NAME):latest"

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
	docker save $(IMAGE_NAME):latest | gzip > $(IMAGE_NAME)-$(VERSION).tar.gz
	@echo "$(GREEN)✓ 已保存到 $(IMAGE_NAME)-$(VERSION).tar.gz$(NC)"

load:
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)错误: 需要指定 FILE$(NC)"; \
		echo "用法: make load FILE=xxx.tar.gz"; \
		exit 1; \
	fi
	docker load < $(FILE)

push:
	@echo "$(GREEN)推送镜像到仓库...$(NC)"
	docker tag $(IMAGE_NAME):latest $(FULL_IMAGE_NAME):$(VERSION)
	docker tag $(IMAGE_NAME):latest $(FULL_IMAGE_NAME):latest
	docker push $(FULL_IMAGE_NAME):$(VERSION)
	docker push $(FULL_IMAGE_NAME):latest
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
	@echo "  $(YELLOW)PORT:$(NC) $(PORT)"
	@echo "  $(YELLOW)HOST_PORT:$(NC) $(HOST_PORT)"
	@echo "$(CYAN)==========================================================$(NC)"