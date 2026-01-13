.POSIX:
.SUFFIXES: .el .elc

EMACS = emacs
RM = rm
RM_FLAGS = -rf
TEXI2ANY = texi2any
TEXI2ANY_HTMLFLAGS = --no-headers --no-split
TEXI2ANY_INFOFLAGS = --no-split
TEXI2ANY_PDFFLAGS = --Xopt=--quiet --Xopt=--tidy

readme_deps = \
	doc/README.texi \
	doc/example-configuration.texi \
	doc/features.texi \
	doc/installation.texi

manual_deps = \
	doc/doclicense.texi \
	doc/example-configuration.texi \
	doc/features.texi \
	doc/installation.texi \
	doc/dialog-mode.texi \
	doc/version.texi

all: README dialog-mode.elc dialog-mode.info

.el.elc:
	$(EMACS) --batch --quick \
	    --directory . \
	    --funcall batch-byte-compile $<

README: $(readme_deps)
	$(TEXI2ANY) \
	    --set-customization-variable ASCII_PUNCTUATION=1 \
	    --plaintext \
	    --output=$@ \
	    doc/README.texi

check: dialog-mode-tests.elc
	$(EMACS) --batch --quick \
	    --directory . \
	    --load dialog-mode-tests.elc \
	    --funcall ert-run-tests-batch-and-exit

clean:
	$(RM) $(RM_FLAGS) \
	    dialog-mode-tests.elc \
	    dialog-mode.elc \
	    dialog-mode.html \
	    dialog-mode.info \
	    dialog-mode.pdf \
	    dialog-mode.t2d

doc/version.texi: dialog-mode.el
	$(EMACS) --batch --quick \
	    --load lisp-mnt \
	    --eval "(with-temp-file \"$@\" \
	              (setq buffer-file-coding-system 'utf-8-unix) \
	              (insert (format \"@set VERSION %s\n\" \
	                              (lm-version \"dialog-mode.el\"))))"

dialog-mode-tests.elc: dialog-mode.elc

dialog-mode.html: $(manual_deps)
	$(TEXI2ANY) $(TEXI2ANY_HTMLFLAGS) \
	    --html \
	    --output=$@ \
	    doc/dialog-mode.texi

dialog-mode.info: $(manual_deps)
	$(TEXI2ANY) $(TEXI2ANY_INFOFLAGS) \
	    --output=$@ \
	    doc/dialog-mode.texi

dialog-mode.pdf: $(manual_deps)
	$(TEXI2ANY) $(TEXI2ANY_PDFFLAGS) \
	    --pdf \
	    --output=$@ \
	    doc/dialog-mode.texi

todo:
	find . \
	    -type f \
	    -name '*.el' \
	    -exec grep -HIin ';[[:space:]]*\(fixme\|todo\)\b' {} + \
	|| true
