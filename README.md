# Datamind-Notebook 镜像构建工具

[![Docker Build](https://img.shields.io/badge/docker-build-blue.svg)](https://docs.docker.com/build/)
[![Multi-Arch](https://img.shields.io/badge/multi--arch-amd64%20%7C%20arm64-green.svg)](https://www.docker.com/blog/multi-arch-images/)
[![BuildKit](https://img.shields.io/badge/BuildKit-enabled-brightgreen.svg)](https://docs.docker.com/build/buildkit/)

## 📖 简介

这是专为一体化零售贷款决策服务[Datamind](https://github.com/zhongsheng-chen/Datamind)的 Python 运行环境构建 jupyer notebook 镜像的工具。它提供了完整的镜像构建、多架构支持、版本管理、镜像发布等功能，帮助您轻松管理 Jupyter 开发环境。

### ✨ 特性

- **多环境构建**：支持 development、testing、production 三种构建类型
- **智能版本管理**：自动识别 Git tag、commit，生成规范的版本号
- **多架构支持**：同时支持 linux/amd64 和 linux/arm64
- **镜像源选择**：支持清华源、阿里源、官方源，可自定义镜像源
- **构建缓存优化**：合理分离构建参数和元数据，充分利用 Docker 缓存
- **完整的镜像管理**：构建、运行、保存、加载、推送、拉取
- **友好的输出**：彩色输出，清晰显示构建信息和生成的标签

## 🚀 快速开始

### 前置要求

- Docker 19.03+（支持 BuildKit）
- Make
- Git（可选，用于版本管理）

### 基础用法

```bash
# 查看所有可用命令
make help

# 构建生产环境镜像
make build-prod

# 构建开发环境镜像
make build-dev

# 运行容器
make run

# 进入容器shell
make shell
```

## 📦 构建命令详解

### 基础构建

| 命令 | 说明 |
|------|------|
| `make build` | 使用当前配置构建（默认production） |
| `make build-dev` | 构建开发环境 |
| `make build-test` | 构建测试环境 |
| `make build-prod` | 构建生产环境 |

### 无缓存构建

| 命令 | 说明 |
|------|------|
| `make build-nocache` | 无缓存构建（默认production） |
| `make build-dev-nocache` | 无缓存构建开发环境 |
| `make build-test-nocache` | 无缓存构建测试环境 |
| `make build-prod-nocache` | 无缓存构建生产环境 |

### 镜像源选择

```bash
# 使用清华源（默认）
make build-tsinghua

# 使用阿里源
make build-aliyun

# 使用官方源
make build-official

# 使用自定义镜像源
make build-mirror URL=http://内网地址/simple HOST=内网主机
```

### 高级构建

```bash
# 安装额外APT包
make build-with-apt PKGS='vim htop'

# 安装开发工具
make build-dev-tools

# 使用私有源（需要token）
make build-with-token TOKEN=xxx
```

## 🏃 运行命令

| 命令 | 说明 |
|------|------|
| `make run` | 运行容器 |
| `make run-dev` | 运行开发容器（带调试） |
| `make run-lab` | 运行 JupyterLab |
| `make run-with-token TOKEN=xxx` | 使用指定token运行 |
| `make shell` | 进入容器shell |
| `make logs` | 查看容器日志 |
| `make stop` | 停止容器 |

### 后台运行

```bash
# 后台运行容器
make run-background

# 查看日志
make logs

# 停止容器
make stop
```

## 📦 镜像管理

| 命令 | 说明 |
|------|------|
| `make save` | 保存镜像到文件 |
| `make load FILE=xxx.tar.gz` | 从文件加载镜像 |
| `make push` | 推送镜像到仓库 |
| `make pull` | 拉取镜像 |
| `make version` | 显示版本信息 |
| `make inspect` | 查看镜像详细信息 |
| `make history` | 查看镜像构建历史 |

## 🏗️ 多架构构建

### 构建器管理

```bash
# 创建多架构构建器
make builder-create

# 使用多架构构建器
make builder-use

# 停止构建器
make builder-stop

# 删除构建器
make builder-rm
```

### 多架构镜像构建

```bash
# 构建多架构镜像（到缓存）
make build-multi

# 构建并推送多架构镜像
make build-multi-push

# 构建并推送多架构镜像，指定 REGISTRY 和 OWNER
make build-multi-push REGISTRY=docker.io OWNER=zhongshengchen

# 本地构建（当前平台）
make build-multi-local

# 构建特定环境的多架构镜像
make build-multi-dev
make build-multi-prod
make build-multi-test
```

### 多架构查看

```bash
# 查看当前版本多架构镜像信息
make inspect-multi

# 查看最新多架构镜像信息
make inspect-multi-latest

# 查看原始 Manifest
make inspect-multi-raw

# 查看所有构建器
make list-builders

# 查看构建器详细信息
make inspect-builder

# 查看构建器缓存使用情况
make inspect-builder-cache
```

## 🔧 配置说明

### 主要变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `REGISTRY` | docker.io | 镜像仓库地址 |
| `OWNER` | zhongsheng | 镜像所属者 |
| `IMAGE_NAME` | datamind-notebook | 镜像名称 |
| `BUILD_TYPE` | production | 构建类型 |
| `PLATFORMS` | linux/amd64,linux/arm64 | 多架构平台列表 |
| `PIP_INDEX_URL` | 清华源 | pip镜像源地址 |
| `NO_CACHE` | false | 是否禁用缓存 |
| `NEED_METADATA` | false | 是否生成元数据标签 |

### 版本号策略

版本号自动生成规则：

1. **有 Git 标签**：使用标签（如 `v1.2.3`）
2. **有 Git 描述**：使用描述（如 `v1.2.3-3-gabc123`）
3. **无标签**：使用 `dev-commit`（如 `dev-abc123`）

### 标签策略

生成的 Docker 标签：

- `latest`：最新版本
- `{BUILD_TYPE}`：环境类型（development/testing/production）
- `{VERSION}`：具体版本号
- `{VERSION}-{BUILD_TYPE}`：组合标签（当版本号不包含构建类型时）
- `stable`：生产环境特有标签
- `{BUILD_METADATA}`：元数据标签（可选，需设置 `NEED_METADATA=true`）

## 💡 使用示例

### 完整工作流程

```bash
# 1. 查看当前配置
make show-info

# 2. 构建开发环境镜像
make build-dev

# 3. 本地测试运行
make run-dev

# 4. 构建生产环境镜像
make build-prod

# 5. 推送到仓库
make push

# 6. 多架构构建并推送
make builder-create
make build-multi-prod

# 7. 查看多架构镜像信息
make inspect-multi
```

### 版本发布流程

```bash
# 1. 创建 Git 标签
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# 2. 构建并推送生产镜像
make build-prod
make push

# 3. 构建并推送多架构镜像
make build-multi-prod
```

### CI/CD 集成示例

```yaml
# .github/workflows/build.yml
name: Build and Push Docker Image

on:
  push:
    branches: [ main ]
    tags: [ 'v*' ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0  # 获取所有标签用于版本号

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Login to Docker Hub
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Build and push
        run: |
          make builder-create
          make build-multi-prod
```

### 查看子网占用情况
```bash
# 一键清理未使用的网络
docker network prune

# 查看所有网络占用情况
docker network ls | awk '{if(NR>1) print $1}' | xargs -I {} docker network inspect {} --format '网络: {{.Name}} 子网: {{range .IPAM.Config}}{{.Subnet}} {{end}}'
```

### 本地开发环境搭建

```bash
# 1. 克隆项目
git clone https://github.com/zhongsheng/datamind-notebook.git
cd datamind-notebook

# 2. 创建必要目录
mkdir -p notebooks config

# 3. 构建开发镜像
make build-dev

# 4. 运行开发容器
make run-dev

# 5. 访问 Jupyter
# 打开浏览器访问 http://localhost:8888
```

## 📝 注意事项

### 缓存优化

时间参数作为标签而非构建参数，避免影响缓存：

```bash
# 第一次构建（完整构建）
make build

# 第二次构建（使用缓存）
make build  # 会看到 "Using cache"
```

### 多架构构建限制

- `--load` 参数不支持多平台，使用 `build-multi-local` 进行本地测试
- 多架构镜像需要推送到仓库才能在其他平台使用

### 版本号建议

- 开发版本：使用 `dev-xxx` 格式
- 预发布版本：使用 `v1.0.0-rc.1` 格式
- 正式版本：使用 `v1.0.0` 格式

### 权限说明

```bash
# 推送镜像前需要登录
docker login

# 私有仓库需要配置认证
make build-with-token TOKEN=xxx
```

## 🔍 故障排查

### 构建失败

```bash
# 使用无缓存构建
make build-nocache

# 查看详细错误
make build 2>&1 | tee build.log

# 清理后重试
make clean-all
make build
```

### 多架构问题

```bash
# 检查构建器状态
make list-builders
make inspect-builder

# 重建构建器
make builder-rm
make builder-create

# 查看构建日志
make build-multi 2>&1 | tee multi-build.log
```

### 缓存问题

```bash
# 查看构建器缓存使用
make inspect-builder-cache

# 清理所有缓存
make clean-all

# 查看磁盘使用
docker system df
```

### 镜像拉取问题

```bash
# 检查镜像是否存在
make inspect-multi

# 手动拉取
docker pull $(make show-info | grep FULL_IMAGE_NAME | awk '{print $NF}'):latest
```

## 📊 性能优化

### 构建加速

```bash
# 使用国内镜像源
make build-tsinghua

# 使用 BuildKit（默认启用）
export DOCKER_BUILDKIT=1

# 并行构建
make -j 4 build-multi
```

### 缓存策略

```makefile
# 在 Dockerfile 中合理安排层顺序
COPY requirements.txt .
RUN pip install -r requirements.txt  # 依赖层，变化较少
COPY . .  # 源代码层，变化频繁
```

## 🤝 贡献指南

### 提交 Issue

- 使用清晰的标题
- 描述问题复现步骤
- 提供相关日志和配置

### 提交 Pull Request

1. Fork 项目
2. 创建特性分支
3. 提交更改
4. 运行测试
5. 创建 Pull Request


## 📧 联系方式

- 作者：Zhongsheng Chen
- 邮箱：zhongsheng.chen@outlook.com
- GitHub：[@zhongsheng](https://github.com/zhongsheng-chen)
- 项目地址：https://github.com/zhongsheng-chen/datamind-notebook

## 🙏 致谢

感谢Jupyter Team 开源项目Jupyter-Stacks！

## 📚 相关资源

- [Docker Buildx 文档](https://docs.docker.com/buildx/working-with-buildx/)
- [Jupyter Docker Stacks](https://jupyter-docker-stacks.readthedocs.io/)
- [Makefile 教程](https://makefiletutorial.com/)



**Enjoy building with Datamind!** 🎉

如果这个工具对您有帮助，请给个 ⭐️ Star 支持一下！