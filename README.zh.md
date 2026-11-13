# 香山开源处理器设计文档

香山开源处理器的设计文档

## 翻译

欢迎大家参与翻译工作，帮助我们一起完善文档！

本项目文档的原始语言为中文，英文翻译正在进行中。

## 构建

我们使用 Pandoc 和 MkDocs 来构建此文档。

### Pandoc

Pandoc 用于构建 PDF 和单页 HTML 格式的文档。

安装 Docker 后，可使用 [docs-utils](https://github.com/OpenXiangShan/docs-utils) 构建环境：

```bash
docker run --rm -it -v "$(pwd):/work" ghcr.io/openxiangshan/docs-utils:latest
```

在容器内，或本机已安装 Pandoc/TeX 依赖时，可以执行以下构建命令：

```bash
# 构建 PDF
make pdf

# 构建用于打印的 PDF
make pdf TWOSIDE=1

# 构建 HTML
make html

# 执行默认构建（PDF）
make
```

### MkDocs

MkDocs 用来构建部署于互联网的静态网站。

```bash
# 创建并激活 Python 虚拟环境（推荐）
python3 -m venv .venv
source .venv/bin/activate

# 安装依赖
pip install -r requirements.txt

# 预览网站
mkdocs serve -f mkdocs-zh.yml

# 构建网站
mkdocs build -f mkdocs-zh.yml
```

## 模板更新

提交 `.copier-answers.yml` 以记录模板来源和版本。定时工作流会为模板更新创建 draft PR，也可以在工作区干净时手动更新：

```bash
copier update --vcs-ref=master --defaults --conflict rej
```

## 许可协议

这份文档采用知识共享署名 4.0 协议授权。 `tools/` 下的文件遵循其中记录的独立许可和声明。

版权所有 © 香山团队·北京开源芯片研究院
