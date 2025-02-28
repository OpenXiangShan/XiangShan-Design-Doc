DOC = xiangshan-design-doc

VERSION = $(shell git describe --always)

PREFACE_MD = docs/index.md
MAIN_MD = pandoc-main.md
SRCS = $(shell find docs -name '*.md')

SVG_FIGS := $(shell find docs -name '*.svg')
PDF_FIGS := $(patsubst %.svg,build/%.pdf,$(SVG_FIGS))

DEPS =
DEPS += $(wildcard utils/*.lua)
DEPS += utils/template.tex

PANDOC_FLAGS += --variable=version:"$(VERSION)"
PANDOC_FLAGS += --from=markdown+table_captions+multiline_tables+grid_tables+header_attributes-implicit_figures
PANDOC_FLAGS += --table-of-contents
PANDOC_FLAGS += --number-sections
PANDOC_FLAGS += --lua-filter=include-files.lua
PANDOC_FLAGS += --metadata=include-auto
PANDOC_FLAGS += --lua-filter=utils/pandoc_filters/replace_variables.lua
PANDOC_FLAGS += --lua-filter=utils/pandoc_filters/remove_md_links.lua
PANDOC_FLAGS += --filter pandoc-crossref
PANDOC_FLAGS += --metadata-file=variables.yml

PANDOC_LATEX_FLAGS += --top-level-division=part
PANDOC_LATEX_FLAGS += --pdf-engine=xelatex
PANDOC_LATEX_FLAGS += --lua-filter=utils/pandoc_filters/svg_to_pdf.lua
PANDOC_LATEX_FLAGS += --template=utils/template.tex
PANDOC_LATEX_FLAGS += --include-before-body=preface.tex

ifneq ($(TWOSIDE),)
	PANDOC_LATEX_FLAGS += --variable=twoside
	DOC := $(DOC)-twoside
endif

# PANDOC_HTML_FLAGS += --embed-resources
PANDOC_HTML_FLAGS += --shift-heading-level-by=1

default: pdf

pdf: $(DOC).pdf
html: $(DOC).html

clean:
	rm -f $(DOC).tex $(DOC).pdf *.aux *.log *.toc *.lof *.lot *.html
	rm -rf build

init:
	git submodule update --init

build/docs/%.pdf: docs/%.svg
	mkdir -p $(dir $@)
	rsvg-convert -f pdf -o $@ $<

preface.tex: $(PREFACE_MD)
	pandoc $< $(PANDOC_FLAGS) -o $@
	sed -i 's/@{}//g' $@

$(DOC).tex: preface.tex $(MAIN_MD) $(SRCS) $(DEPS)
	pandoc $(MAIN_MD) $(PANDOC_FLAGS) $(PANDOC_LATEX_FLAGS) -s -o $@
	sed -i 's/@{}//g' $@

$(DOC).html: $(MAIN_MD) $(SRCS) $(DEPS) $(SVG_FIGS)
	pandoc -s $(MAIN_MD) $(PANDOC_FLAGS) $(PANDOC_HTML_FLAGS) -o $@

$(DOC).pdf: $(DOC).tex $(PDF_FIGS)
	xelatex $<
	xelatex $<
	xelatex $<

.PHONY: default clean
.PHONY: pdf html
