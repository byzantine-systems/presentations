.PHONY: all build clean

all: build

build:
	@echo "Building via org-publish..."
	@emacs --batch --script publish.el \
		2>&1 | tee build-publish.log

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	@target="$${PRESENTATION:-.}"; cd "$$target" && rm -f *.pdf *.tex *.aux *.log *.nav *.out *.snm *.toc *.vrb
	@target="$${PRESENTATION:-.}"; cd "$$target" && rm -f *.bbl *.blg *-blx.bib *.bcf *.run.xml *.fls *.fdb_latexmk
	@target="$${PRESENTATION:-.}"; cd "$$target" && rm -f build.log build-publish.log debug.log
	@target="$${PRESENTATION:-.}"; cd "$$target" && rm -rf public/ auto/
	@echo "✓ Cleaned"
