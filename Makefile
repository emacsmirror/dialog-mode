.POSIX:
.SUFFIXES: .el .elc

EMACS = emacs
RM = rm -f

compile: README dialog-mode.elc

check: dialog-mode-tests.elc
	$(EMACS) --batch --quick \
	    --directory . \
	    --load dialog-mode-tests.elc \
	    --funcall ert-run-tests-batch-and-exit

dialog-mode-tests.elc: dialog-mode.elc dialog-mode-tests.el

.el.elc:
	$(EMACS) --batch --quick \
	    --directory . \
	    --funcall batch-byte-compile $<

README: dialog-mode.el
	$(EMACS) --batch --quick \
	    --load lisp-mnt \
	    --eval "(with-temp-file \"$@\" \
	              (setq buffer-file-coding-system 'utf-8-unix) \
	              (insert (lm-commentary \"dialog-mode.el\")) \
	              (newline))"

todo:
	find . \
	    -type f \
	    -name '*.el' \
	    -exec grep -HIin ';[[:space:]]*\(fixme\|todo\)\b' {} + \
	|| true

clean:
	$(RM) README dialog-mode-tests.elc dialog-mode.elc
