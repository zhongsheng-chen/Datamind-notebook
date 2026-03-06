# datamind-notebook

克隆 Datamind 计算环境的 Jupyter Notebook 镜像，基于 Python 3.10-slim。

## ✨ 特性

- 🐍 Python 3.10 精简版基础镜像
- 📓 预装 Jupyter Notebook 和 JupyterLab
- 📦 常用数据科学库（numpy, pandas, matplotlib, scikit-learn 等）
- 🔧 智能入口脚本，支持多种命令和配置
- 💾 自动 Token 管理
- 🩺 健康检查支持

## 🚀 快速开始

### 1. 构建镜像
```bash
make build
# 或
docker build -t datamind-notebook:latest .
```


# Datamind-notebook

<div align="center">

**English** | [**中文**](#)

---

**English**: A Dockerized Jupyter environment for Datamind, providing secure and optimized Python runtime for retail loan decision services.

**中文**: 为 Datamind 一体化零售贷款决策服务量身定制的 Jupyter Notebook 镜像构建解决方案，提供安全、可配置、优化的 Python 运行环境。

![Version](https://img.shields.io/badge/version-production--latest-blue)
![Docker](https://img.shields.io/badge/docker-24.0+-blue)
![Python](https://img.shields.io/badge/python-3.10-green)
![Jupyter](https://img.shields.io/badge/jupyter-7.5+-orange)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

## 🎯 项目背景

Datamind-notebook 是 [**Datamind**](https://github.com/zhongsheng-chen/Datamind) 一体化零售贷款决策服务的核心组件之一，提供：

- 📊 **数据科学环境**：为信贷风险评估、客户画像分析提供 Jupyter 交互式开发环境
- 🔧 **模型开发平台**：支持机器学习模型开发、训练和验证
- 📈 **数据分析工具**：集成 Pandas、NumPy、Matplotlib 等数据科学生态工具
- 🚀 **生产级部署**：容器化部署，确保开发与生产环境一致性

通过 Datamind-notebook，数据科学家可以专注于业务逻辑和模型开发，无需关心环境配置和依赖管理。

## ✨ 核心特性

### 🎯 **专为 Datamind 定制**
- ✅ 预配置零售贷款决策所需的 Python 数据科学生态
- ✅ 与 Datamind 微服务架构无缝集成
- ✅ 支持信贷风控模型开发全流程

### 🛡️ **企业级安全**
- ✅ 非 root 用户运行，遵循最小权限原则
- ✅ 完整的权限管理 (`fix-permissions`)
- ✅ 可配置的用户 UID/GID，解决宿主机权限问题

### 🔧 **灵活可配**
- ✅ 多环境支持 (开发/测试/生产)
- ✅ 多镜像源选择 (清华/阿里/官方)
- ✅ 可扩展的 APT/Python 包安装
- ✅ 支持 Jupyter Notebook/Lab 双模式

### 🚀 **开箱即用**
- ✅ 47+ 个 Makefile 命令，一键构建运行
- ✅ 彩色日志输出，优雅的信号处理
- ✅ 自动清理机制，优化镜像体积
- ✅ 健康检查，保障服务可靠性


## ✨ 功能特性

### 🛡️ **安全性**
- ✅ 非 root 用户运行 (`jovyan`)
- ✅ 完整的权限管理 (`fix-permissions`)
- ✅ 可配置的用户 UID/GID
- ✅ 可选的密码/token 认证

### 🔧 **可配置性**
- ✅ 多环境支持 (development/testing/production)
- ✅ 灵活的构建参数
- ✅ 多种镜像源选择 (清华/阿里/官方/自定义)
- ✅ 可扩展的 APT 包安装
- ✅ 可选的开发工具

### 📦 **镜像优化**
- ✅ 基于 `python:3.10-slim` 轻量基础镜像
- ✅ 多阶段清理，减小体积
- ✅ 分层构建，优化缓存
- ✅ 健康检查支持
- ✅ 完整的标签信息

### 🚀 **易用性**
- ✅ 47+ 个 Makefile 命令
- ✅ 彩色日志输出
- ✅ 详细的帮助信息
- ✅ 优雅的信号处理
- ✅ 自动清理机制

## 🚀 快速开始

### 前置要求

- Docker 24.0+
- Make 4.0+
- Git 2.0+
- 4GB+ 可用内存

### 一分钟启动

```bash
# 克隆项目
git clone https://github.com/your-repo/datamind-notebook.git
cd datamind-notebook

# 构建镜像（使用清华源）
make build-tsinghua

# 运行容器
make run

# 访问 Jupyter
# 打开浏览器访问 http://localhost:8888
# 使用输出的 token 登录
```




# 1. 如果构建器已存在，直接使用
make builder-use

# 2. 构建多架构镜像（只构建到缓存）
make build-multi

# 3. 构建并推送多架构镜像
make build-multi-push

# 4. 本地测试（加载到本地）
make build-multi-local

# 5. 构建特定环境的多架构镜像
make build-multi-dev
make build-multi-prod
make build-multi-test



# 查看镜像支持的架构
docker buildx imagetools inspect $(FULL_IMAGE_NAME):latest