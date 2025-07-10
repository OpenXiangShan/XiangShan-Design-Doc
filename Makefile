# Makefile for building pdf and single html version of the documentation

# Documentation name
# The name of the output file will be <DOC>.pdf and <DOC>.html
DOC := xiangshan-design-doc

# Supporting languages
LANGS := zh

# Git version information
VERSION := $(shell git describe --always)

# Public dependencies
DEPS := $(wildcard utils/*.lua) utils/template.tex

# Pandoc flags
PANDOC_FLAGS += --variable=version:"$(VERSION)"
PANDOC_FLAGS += --from=markdown+table_captions+multiline_tables+grid_tables+header_attributes-implicit_figures
PANDOC_FLAGS += --table-of-contents
PANDOC_FLAGS += --number-sections
PANDOC_FLAGS += --lua-filter=include-files.lua
PANDOC_FLAGS += --metadata=include-auto
PANDOC_FLAGS += --lua-filter=utils/pandoc_filters/replace_variables.lua
PANDOC_FLAGS += --lua-filter=utils/pandoc_filters/remove_md_links.lua
PANDOC_FLAGS += --filter pandoc-crossref

# Pandoc LaTeX flags
PANDOC_LATEX_FLAGS += --top-level-division=part
PANDOC_LATEX_FLAGS += --pdf-engine=xelatex
PANDOC_LATEX_FLAGS += --lua-filter=utils/pandoc_filters/svg_to_pdf.lua
PANDOC_LATEX_FLAGS += --template=utils/template.tex

ifneq ($(TWOSIDE),)
	PANDOC_LATEX_FLAGS += --variable=twoside
	DOC := $(DOC)-twoside
endif

# Pandoc HTML flags
# PANDOC_HTML_FLAGS += --embed-resources
PANDOC_HTML_FLAGS += --shift-heading-level-by=1


# Default build target: all PDFs
default: pdf

# Batch targets
pdf: $(addprefix pdf-,$(LANGS))
html: $(addprefix html-,$(LANGS))

# Clean up
clean:
	rm -f $(DOC)-*.tex
	rm -f $(DOC)-*.pdf
	rm -f $(DOC)-*.html
	rm -f preface-,*.txt
	rm -f *.aux *.log *.toc *.lof *.lot
	rm -rf build

# Initialize submodules
init:
	git submodule update --init

# Multi-language template
define PER_LANG_RULES

MAIN_MD_$(1) := docs/pandoc-main-$(1).md
PREFACE_MD_$(1) := docs/$(1)/index.md
PREFACE_TEX_$(1) := preface-$(1).tex

SRCS_$(1) := $(shell find docs/$(1) -name '*.md')

SVG_FIGS_$(1) := $(shell find docs/$(1) -name '*.svg')
PDF_FIGS_$(1) := $$(patsubst %.svg,build/%.pdf,$$(SVG_FIGS_$(1)))

PANDOC_FLAGS_$(1) := $(PANDOC_FLAGS)
PANDOC_FLAGS_$(1) += --metadata-file=docs/variables-$(1).yml

PANDOC_LATEX_FLAGS_$(1) := $(PANDOC_LATEX_FLAGS)
PANDOC_LATEX_FLAGS_$(1) += --include-before-body=preface-$(1).tex

build/docs/$(1)/%.pdf: docs/$(1)/%.svg
	mkdir -p $$(@D)
	rsvg-convert -f pdf -o $$@ $$<

$$(PREFACE_TEX_$(1)): $$(PREFACE_MD_$(1))
	pandoc $$< $$(PANDOC_FLAGS_$(1)) -o $$@
	sed -i 's/@{}//g' $$@

$(DOC)-$(1).tex: $$(PREFACE_TEX_$(1)) $$(MAIN_MD_$(1)) $$(SRCS_$(1)) $$(DEPS)
	pandoc $$(MAIN_MD_$(1)) $$(PANDOC_FLAGS_$(1)) $$(PANDOC_LATEX_FLAGS_$(1)) -s -o $$@
	sed -i 's/@{}//g' $$@

$(DOC)-$(1).html: $$(MAIN_MD_$(1)) $$(SRCS_$(1)) $$(DEPS) $$(SVG_FIGS_$(1))
	pandoc -s $$(MAIN_MD_$(1)) $$(PANDOC_FLAGS_$(1)) $$(PANDOC_HTML_FLAGS) -o $$@

$(DOC)-$(1).pdf: $(DOC)-$(1).tex $$(PDF_FIGS_$(1))
	xelatex $$<
	xelatex $$<
	xelatex $$<

pdf-$(1): $(DOC)-$(1).pdf
html-$(1): $(DOC)-$(1).html

endef # PER_LANG_RULES

$(foreach lang,$(LANGS),$(eval $(call PER_LANG_RULES,$(lang))))

pdf-one:
	@$(MAKE) pdf-$(LANG)

html-one:
	@$(MAKE) html-$(LANG)

.PHONY: default clean init pdf html pdf-one html-one
.PHONY: $(addprefix pdf-,$(LANGS)) $(addprefix html-,$(LANGS))
