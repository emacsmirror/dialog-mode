;;; dialog-mode.el --- Major mode for editing Dialog files -*- lexical-binding: t; -*-

;; Copyright (C) 2023-2026 Morgan Willcock

;; Author: Morgan Willcock <morgan@ice9.digital>
;; Keywords: languages
;; Maintainer: Morgan Willcock <morgan@ice9.digital>
;; Package-Requires: ((emacs "28.1"))
;; URL: https://git.sr.ht/~mew/dialog-mode
;; Version: 1.0.0pre

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Support for editing Dialog scripts.

;; See the Dialog Mode manual for configuration examples and descriptions of
;; available editing features.

;;; Code:

(require 'align)
(require 'browse-url)
(require 'comint)
(require 'imenu)
(require 'project)
(require 'xref)
(eval-when-compile
  (require 'cl-lib)
  (require 'subr-x))

;;;; Faces

;;;###autoload
(defgroup dialog-faces nil
  "Faces used by Dialog Mode."
  :group 'dialog
  :prefix "dialog-")

(defface dialog-brace-face
  ;; `font-lock-bracket-face' appeared in Emacs 29.
  `((default ,(and (facep 'font-lock-bracket-face)
                   (list :inherit 'font-lock-bracket-face))))
  "Face to highlight Dialog braces.")

(defface dialog-bracket-face
  ;; `font-lock-bracket-face' appeared in Emacs 29.
  `((default ,(and (facep 'font-lock-bracket-face)
                   (list :inherit 'font-lock-bracket-face))))
  "Face to highlight Dialog brackets.")

(defface dialog-delimiter-face
  ;; `font-lock-delimiter-face' appeared in Emacs 29.
  `((default ,(and (facep 'font-lock-delimiter-face)
                   (list :inherit 'font-lock-delimiter-face))))
  "Face to highlight a Dialog delimiter.")

(defface dialog-dictionary-word-face
  '((default :inherit font-lock-type-face))
  "Face to highlight a Dialog dictionary word.")

(defface dialog-escape-sequence-face
  ;; `font-lock-escape-face' appeared in Emacs 29.
  `((default :inherit ,(if (facep 'font-lock-escape-face)
                           'font-lock-escape-face
                         'escape-glyph)))
  "Face to highlight a Dialog escape sequence.")

(defface dialog-object-name-face
  '((default :inherit font-lock-constant-face))
  "Face to highlight a Dialog object name.")

(defface dialog-operator-face
  ;; `font-lock-operator-face' appeared in Emacs 29.
  `((default ,(and (facep 'font-lock-operator-face)
                   (list :inherit 'font-lock-operator-face))))
  "Face to highlight a Dialog operator.")

(defface dialog-paren-face
  ;; `font-lock-bracket-face' appeared in Emacs 29.
  `((default ,(and (facep 'font-lock-bracket-face)
                   (list :inherit 'font-lock-bracket-face))))
  "Face to highlight Dialog parenthesis.")

(defface dialog-special-block-face
  '((default :inherit font-lock-keyword-face))
  "Face to highlight a Dialog special block.")

(defface dialog-topic-name-face
  '((default :inherit font-lock-preprocessor-face))
  "Face to highlight a Dialog topic name.")

(defface dialog-variable-name-face
  '((default :inherit font-lock-variable-name-face))
  "Face to highlight a Dialog variable name.")

(defface dialog-warning-face
  '((default :inherit font-lock-warning-face))
  "Face to highlight a Dialog warning.")

;;;; Customization

;;;###autoload
(defgroup dialog nil
  "Major mode for editing Dialog files."
  :tag "Dialog"
  :link '(custom-manual "(dialog-mode)Top")
  :group 'languages
  :prefix "dialog-")

;;;; Search patterns

(eval-and-compile
  (defmacro dialog-rx (&rest regexps)
    "Extended version of `rx' for translation of form REGEXPS."
    `(rx-let ((dictionary-word
               (seq ?@ (or
                        ;; Match parser: !strchr("\n\r\t ()[]{}~*|%/", ch)
                        (1+ (not (char whitespace
                                       ?\( ?\) ?\[ ?\] ?\{ ?\} ?~ ?* ?| ?% ?/)))
                        (seq ?\\ (char ?b ?d ?l ?n ?r ?s ?u)))))
              (escape-sequence
               (seq ?\\ (not control)))
              (object
               (seq ?# (1+ user-chars)))
              (outline
               (seq line-start (or rule-head-line
                                   topic
                                   (seq (>= 3 ?%)
                                        (1+ whitespace)
                                        (0+ not-newline)))))
              (rule-head-line
               (seq rule-head-start (1+ not-newline)))
              (rule-head-start
               (seq line-start (optional (or ?@ ?~)) ?\())
              (topic
               (seq line-start ?# (group (1+ user-chars))))
              (unescaped
               (seq (or line-start (not ?\\))
                    (0+ ?\\ ?\\)))
              (user-chars
               (or (char alphanumeric)
                   (char ?+ ?- ?< ?> ?_)))
              (variable
               (seq ?$ (1+ user-chars))))
       (rx ,@regexps))))

;;;; Font lock

;; Prevent the use of lexical binding for font-lock boundaries.
(defvar font-lock-beg)

(defun dialog--font-lock-extend-region-syntax-form ()
  "Move fontification boundaries to include a complete syntax form.

Only consider syntax which opens with \"(\" because this is currently
the only syntax which is highlighted and may span multiple lines.

Only extend the region backwards.  The `font-lock-multiline' property is
expected to be set across a syntactically valid form to handle changes
in the forwards direction."
  (save-excursion
    (beginning-of-line)
    (and-let* ((list-start (dialog--list-start)))
      (and (= (char-after list-start) ?\()
           (< list-start font-lock-beg)
           (setq font-lock-beg list-start)))))

(defconst dialog-font-lock-keywords-1
  `((,(dialog-rx topic) . 'dialog-topic-name-face))
  "Font lock keywords for level 1 highlighting in Dialog mode.

Highlights Dialog topics.")

(defun dialog--font-lock-prematch-special-character ()
  "Pre-match function for anchored font-lock match of a special character."
  (unless (or (dialog--in-comment-p)
              (zerop (dialog--paren-depth)))
    ;; Move backwards to the position before the original matcher match in order
    ;; to re-match it with the anchored-match.
    (forward-char -1)))

(defconst dialog-font-lock-keywords-2
  (append
   dialog-font-lock-keywords-1
   `((,(dialog-rx unescaped (group dictionary-word))
      (1 'dialog-dictionary-word-face))
     (,(dialog-rx escape-sequence)   . 'dialog-escape-sequence-face)
     (,(dialog-rx object)            . 'dialog-object-name-face)
     (,(dialog-rx variable)          . 'dialog-variable-name-face)
     ;; Prefix syntax before ( or { is an operator.
     (,(rx (group (syntax ?')) (or ?\( ?\{))
      (1 'dialog-operator-face))
     ;; $ or * not at the top-level is an operator.
     (,(rx (or ?$ ?*))
      ,(rx point (or ?$ ?*))
      (dialog--font-lock-prematch-special-character)
      nil
      (0 'dialog-operator-face))
     ;; | not at the top-level is a delimiter.
     (,(rx ?|)
      ,(rx point ?|)
      (dialog--font-lock-prematch-special-character)
      nil
      (0 'dialog-delimiter-face))
     ;; A special character anywhere else is an error.
     (,(rx (char ?# ?$ ?* ?@ ?\\ ?| ?~)) . 'dialog-warning-face)))
  "Font lock keywords for level 2 highlighting in Dialog mode.

Highlights escape sequences, special characters, and user defined names
for dictionary words, objects, and variables.")

(defun dialog--font-lock-prematch-block ()
  "Pre-match function for anchored font-lock match of block-defining syntax."
  (unless (dialog--in-comment-p)
    (if-let* ((symbol (dialog-statement-symbol
                       (save-excursion
                         (forward-char -1)
                         (dialog--parse-block-at-point)))))
        (let* ((parse-sexp-ignore-comments t)
               (start-pos (1- (point)))
               (end-pos (dialog--list-end start-pos)))
          (put-text-property start-pos (1+ end-pos) 'font-lock-multiline t)
          ;; Return a search limit that is immediately after the leading words
          ;; of the syntax.  All words up until the search limit are going to
          ;; get highlighted.  Move by sexp instead of by word for an easy way
          ;; to skip over comments.
          (pcase symbol
            ((or 'dialog-accumulate-t 'dialog-collect-t 'dialog-into-t)
             (save-excursion (forward-sexp) (point)))
            ('dialog-determine-t
             (save-excursion (forward-sexp 2) (point)))
            ('dialog-matching-t
             (save-excursion (forward-sexp 3) (point)))
            (_
             end-pos)))
      ;; Prevent searching beyond the current position.
      (forward-char -1)
      (1+ (point)))))

(defconst dialog-font-lock-keywords-3
  (append
   dialog-font-lock-keywords-2
   `((,(rx (or ?\{ ?\})) . 'dialog-brace-face)
     (,(rx (or ?\[ ?\])) . 'dialog-bracket-face)
     (,(rx ?\))          . 'dialog-paren-face)
     ;; Opening paren and leading words of block-defining syntax.
     (,(dialog-rx unescaped (group ?\())
      (1 'dialog-paren-face)
      (,(rx (1+ word))
       (dialog--font-lock-prematch-block)
       nil
       (0 'dialog-special-block-face)))))
  "Font lock keywords for level 3 highlighting in Dialog mode.

Highlights selected Dialog special syntax, braces, brackets,
parenthesis, escape sequences, special characters, and user defined
names for dictionary words, objects, and variables.")

(defvar dialog-font-lock-keywords dialog-font-lock-keywords-2
  "Default expressions to highlight in Dialog mode.")

;;;; Utility

(defun dialog--derived-buffer-name (buffer-name suffix &optional private)
  "Return the name BUFFER-NAME extended with SUFFIX.

SUFFIX will joined to BUFFER-NAME using a \"-\" character.  Naming
conventions for special and private buffers are preserved.  When PRIVATE
is non-nil the returned buffer name is guaranteed to begin with at least
one space character."
  (let ((new-name
         (if (string-match (rx string-start
                               (group (0+ whitespace) ?* (1+ not-newline)) ?*
                               string-end)
                           buffer-name)
             (concat (match-string-no-properties 1 buffer-name) "-" suffix "*")
           (concat buffer-name "-" suffix))))
    (if (and private (not (string-prefix-p " " new-name)))
        (concat " " new-name)
      new-name)))

(defun dialog--empty-line-p ()
  "Return a non-nil value when the current line is empty."
  (save-excursion
    (beginning-of-line)
    (looking-at-p (rx line-start (0+ whitespace) line-end))))

(defun dialog--forward-prefix-chars ()
  "Move forwards over characters with prefix syntax."
  (while (eq (car (syntax-after (point))) 6)
    (forward-char)))

(defun dialog--in-comment-p (&optional ppss)
  "Return a non-nil value when inside a comment.

Prefer existing parser state PPSS over calling `syntax-ppss'."
  (nth 4 (or ppss (syntax-ppss))))

(defun dialog--line-has-comment-p ()
  "Return a non-nil value when the current line has a comment on it."
  (save-excursion
    (end-of-line)
    (dialog--in-comment-p)))

(defun dialog--list-end (&optional start)
  "Return the end position of the list which opens at point.

If START is supplied, use it as the start position instead of using the
current position."
  (save-excursion
    (when start
      (goto-char start))
    (condition-case nil
        (let ((parse-sexp-ignore-comments t))
          (forward-sexp)
          (1- (point)))
      (scan-error))))

(defun dialog--list-start (&optional ppss)
  "Return the buffer position which opens the list around point.

Return nil if point is not within a list.  Prefer existing parser state
PPSS over calling `syntax-ppss'."
  (nth 1 (or ppss (syntax-ppss))))

(defun dialog--normalize-string (string)
  "Return a normalized version of STRING.

Comments are removed.  Contiguous white-space is collapsed to a single
space character."
  (thread-last
    string
    (replace-regexp-in-string (dialog-rx unescaped "%%" (0+ not-newline)) "")
    (replace-regexp-in-string (rx (1+ (or whitespace ?\C-j))) " ")))

(defun dialog--paren-depth (&optional ppss)
  "Return the current parentheses depth.

Prefer existing parser state PPSS over calling `syntax-ppss'."
  (car (or ppss (syntax-ppss))))

(defun dialog--start-of-comment-or-string (&optional ppss)
  "Return the starting position of the comment or string at point.

Return nil when point is outside of a comment or string.  Prefer
existing parser state PPSS over calling `syntax-ppss'."
  (nth 8 (or ppss (syntax-ppss))))

(defun dialog--project-directory ()
  "Return the current project directory or the current directory."
  (if-let* ((project (project-current)))
      (project-root project)
    default-directory))

(defun dialog--rule-uses-topic-p ()
  "Return a non-nil value when the rule at point references a topic."
  (save-excursion
    (end-of-line)
    (dialog-beginning-of-defun)
    ;; Search for an unescaped * in rule-head or body.
    (let ((bound (save-excursion
                   (dialog-end-of-defun)
                   (point))))
      (cl-loop while (re-search-forward (dialog-rx unescaped ?*) bound t)
               for ppss = (syntax-ppss)
               unless (eq (char-after) ?\()
               unless (dialog--in-comment-p ppss)
               when (cl-plusp (dialog--paren-depth ppss))
               return t))))

;;;; Block parser

(cl-defstruct (dialog-block
               (:constructor dialog-make-block)
               (:copier nil))
  "The `position' slot is the buffer position which begins the dialog
statement.

The `type' slot is a character which represents the opening character of
the statement (ignoring any prefix characters).  Valid values are \"{\",
\"[\", and \"(\"."
  (position nil :type (natnum 0 *))
  (type nil :type character))

(cl-defstruct (dialog-statement
               (:include dialog-block)
               (:constructor dialog-make-statement)
               (:copier nil))
  "The `symbol' slot is the symbol which represents the statement syntax
when resolved as a syntax token.

The `syntax' slot is a list which represents the parsed top-level inside
the statement."
  (symbol nil :type symbol)
  (syntax nil :type list))

(cl-defgeneric dialog--opens-block-p (block)
  "Return whether BLOCK increases the indentation level."
  (always block))

(cl-defmethod dialog--opens-block-p ((block dialog-statement))
  "Return whether BLOCK increases the indentation level."
  (memq (dialog-statement-symbol block)
        '(dialog-or-t
          dialog-if-t
          dialog-then-t
          dialog-elseif-t
          dialog-else-t
          dialog-select-t
          dialog-accumulate-t
          dialog-collect-t
          dialog-determine-t
          dialog-from-t)))

(cl-defgeneric dialog--closes-block-p (block)
  "Return whether BLOCK decreases the indentation level."
  (ignore block))

(cl-defmethod dialog--closes-block-p ((block dialog-statement))
  "Return whether BLOCK decreases the indentation level."
  (memq (dialog-statement-symbol block)
        '(dialog-or-t
          dialog-then-t
          dialog-elseif-t
          dialog-else-t
          dialog-endif-t
          dialog-stopping-t
          dialog-cycling-t
          dialog-at-random-t
          dialog-into-t
          dialog-from-t
          dialog-matching-t)))

(cl-defgeneric dialog--rule-head-p (block)
  "Return whether BLOCK is a rule-head."
  (ignore block))

(cl-defmethod dialog--rule-head-p ((block dialog-statement))
  "Return whether BLOCK is a rule-head."
  (save-excursion
    (goto-char (dialog-statement-position block))
    (backward-prefix-chars)
    (zerop (current-column))))

(cl-defgeneric dialog--syntax-definition (block)
  "Return the syntax definition for BLOCK."
  (ignore block))

(cl-defmethod dialog--syntax-definition ((block dialog-statement))
  "Return the syntax definition for BLOCK."
  (if-let* ((forward-arg (pcase (dialog-statement-syntax block)
                           (`("interface" ,_)         1)
                           (`("global" "variable" ,_) 2))))
      (save-excursion
        (goto-char (1+ (dialog-statement-position block)))
        (let ((parse-sexp-ignore-comments t))
          (forward-sexp forward-arg))
        (forward-comment (point-max))
        (dialog--forward-prefix-chars)
        (pcase (dialog--parse-block-at-point)
          ((and (cl-type dialog-statement) inner-block)
           (dialog-statement-syntax inner-block))))
    (dialog-statement-syntax block)))

(defun dialog--parse-statement-syntax ()
  "Parse the inner contents of a special statement list.

Assume that point is on unescaped opening parenthesis and outside of a
comment."
  (and-let* ((statement-end (dialog--list-end)))
    (save-excursion
      (forward-char)
      (let ((parse-sexp-ignore-comments t))
        (cl-loop
         do (comment-forward (point-max))
         do (dialog--forward-prefix-chars)
         while (< (point) statement-end)
         collect (pcase (cons (char-before) (char-after))
                   (`(,_ . ?#)  (forward-sexp) 'object)
                   (`(,_ . ?$)  (forward-sexp) 'variable)
                   (`(,_ . ?*)  (forward-sexp) 'topic)
                   ('(?* . ?\() (forward-sexp) 'mutli-query)
                   ('(?@ . ?\() (forward-sexp) 'access-predicate)
                   (`(?@ . ,_)  (forward-sexp) 'word)
                   ('(?~ . ?\() (forward-sexp) 'not-query)
                   (`(,_ . ?\() (forward-sexp) 'query)
                   (`(,_ . ?\[) (forward-sexp) 'list)
                   (_ (pcase (buffer-substring-no-properties
                              (point)
                              (progn (forward-sexp) (point)))
                        ("0" 'number)
                        ((rx bos (char (?1 . ?9)) (0+ numeric) eos) 'number)
                        (string string)))))))))

(defun dialog--statement-token (statement)
  "Return the symbol representing the statement list STATEMENT."
  (pcase statement
    ;; { ... (or) ... }
    ('("or")     'dialog-or-t)
    ;; (if) ... (then) ... (elseif) ... (then) ... (else) ... (endif)
    ('("if")     'dialog-if-t)
    ('("then")   'dialog-then-t)
    ('("elseif") 'dialog-elseif-t)
    ('("else")   'dialog-else-t)
    ('("endif")  'dialog-endif-t)
    ;; (select) ... (or) ... (or) ... (stopping)
    ;; (select) ... (or) ... (or) ... (cycling)
    ;; (select) ... (or) ... (or) ... (at random)
    ;; (select) ... (or) ... (or) ... (purely at random)
    ;; (select) ... (or) ... (or) ... (then at random)
    ;; (select) ... (or) ... (or) ... (then purely at random)
    ('("select")                      'dialog-select-t)
    ('("stopping")                    'dialog-stopping-t)
    ('("cycling")                     'dialog-cycling-t)
    ('("at" "random")                 'dialog-at-random-t)
    ('("purely" "at" "random")        'dialog-at-random-t)
    ('("then" "at" "random")          'dialog-at-random-t)
    ('("then" "purely" "at" "random") 'dialog-at-random-t)
    ;; (accumulate $Element) ... (into $Sum)
    ;; (collect $Element) ... (into $List)
    ;; (collect words) ... (into $List)
    (`("accumulate" ,_) 'dialog-accumulate-t)
    (`("collect" ,_)    'dialog-collect-t)
    (`("into" ,_)       'dialog-into-t)
    ;; (determine object $Obj) ... (from words) ... (matching all of $List)
    (`("determine" "object" ,_)  'dialog-determine-t)
    ('("from" "words")           'dialog-from-t)
    (`("matching" "all" "of" ,_) 'dialog-matching-t)))

(defun dialog--parse-block-at-point ()
  "Return a struct which represents the block at point.

Return nil when point is not at the start of a block.  The beginning of
the statement is assumed to be unescaped."
  (and (not (dialog--in-comment-p))
       (let ((type (char-after)))
         (cl-case type
           (?\[ (dialog-make-block
                 :position (point)
                 :type type))
           (?\{ (dialog-make-block
                 :position (point)
                 :type type))
           (?\( (let ((syntax (dialog--parse-statement-syntax)))
                  (dialog-make-statement
                   :position (point)
                   :type type
                   :symbol (dialog--statement-token syntax)
                   :syntax syntax)))))))

(defun dialog--parse-dominating-block ()
  "Scan backwards and return the dominant block state.

A dominant block is one which opens a new indentatation level without
closing the previous indentation level.  In practical terms this means
prefering the opening \"(if)\" of an If statement over \"(else)\",
\"(elseif)\", or \"(then)\" blocks, and preferring the block that
precedes an \"(or)\" block."
  (let* ((block (dialog--parse-block))
         (parent block))
    (while (and (dialog-statement-p parent)
                (memq (dialog-statement-symbol parent)
                      '(dialog-else-t
                        dialog-elseif-t
                        dialog-or-t
                        dialog-then-t))
                (not (dialog--rule-head-p parent))
                (setq parent (save-excursion
                               (goto-char (dialog-statement-position parent))
                               (dialog--parse-block)))))
    (or parent block)))

(defun dialog--parse-block ()
  "Scan backwards and return the current block state."
  (save-excursion
    (let* ((ppss (syntax-ppss))
           (list-opening (dialog--list-start ppss))
           (paren-depth (dialog--paren-depth ppss))
           block block-end)
      (while (and (null block)
                  ;; Match an unescaped statement opening.
                  (re-search-backward (dialog-rx unescaped
                                                 (group (char ?\( ?\[ ?{)))
                                      nil t))
        (goto-char (match-beginning 1))
        (when-let* ((statement (dialog--parse-block-at-point)))
          (cond ((and list-opening (= (point) list-opening))
                 ;; This is the block opening that matches the list start of the
                 ;; original value of point.
                 (setq block statement))
                ((> (dialog--paren-depth) paren-depth)
                 ;; Ignore a match in a deeper paren level.
                 )
                ((not (dialog-statement-p statement))
                 ;; Ignore a block that opens with [ or {.
                 )
                ((dialog--rule-head-p statement)
                 (setq block statement))
                ((dialog--opens-block-p statement)
                 (pcase (cons (dialog-statement-symbol statement)
                              (car block-end))
                   ;; Always match for an opening with no existing close.
                   (`(,_ . nil)
                    (setq block statement))
                   ;; Always match an opening "(or)".
                   (`('dialog-or-t . ,_)
                    (setq block statement))
                   ;; Match statement pairs.
                   ((or '(dialog-if-t        . dialog-endif-t)
                        `(dialog-select-t    . ,(or 'dialog-stopping-t
                                                    'dialog-cycling-t
                                                    'dialog-at-random-t))
                        '(dialog-determine-t . dialog-matching-t)
                        `(,(or 'dialog-accumulate-t 'dialog-collect-t)
                          . dialog-into-t))
                    (pop block-end))))
                ((dialog--closes-block-p statement)
                 (push (dialog-statement-symbol statement)
                       block-end)))))
      block)))

;;;; Motion

(defcustom dialog-block-motion-push-mark t
  "Specifies whether block motion will push to the `mark-ring'.

A non-nil value indicates that block motion commands are permitted to
push the previous location to the `mark-ring' when the value of point
changes."
  :type 'boolean
  :safe #'booleanp)

(defun dialog-up-block ()
  "Move point to the opening of the current block."
  (interactive)
  (when-let* ((block (dialog--parse-block)))
    (unless (or (null dialog-block-motion-push-mark)
                (region-active-p))
      (push-mark (point)))
    (goto-char (dialog-block-position block))))

(defun dialog-beginning-of-defun (&optional arg)
  "Move backwards to the beginning of a rule-head.

With ARG, do it that many times.  Negative ARG means move forwards to
the ARGth following beginning of defun.

If search is successful, return t.  Success is defined to be any
successful match in ARG attempts to move.  Point ends up at the
beginning of the line where the search succeeded.  Otherwise, return
nil."
  (unless arg (setq arg 1))
  (let* ((forwards (cl-minusp arg))
         (search-fn (if forwards #'re-search-forward #'re-search-backward))
         (inc-fn (if forwards #'1+ #'1-))
         match-pos)
    (save-excursion
      ;; Ensure that searching forwards doesn't match the current position.
      (when (and forwards (looking-at-p (dialog-rx rule-head-start)))
        (forward-char 1))
      ;; Search for the argth rule-head in the given direction.
      (while (and (not (zerop arg))
                  (funcall search-fn (dialog-rx rule-head-start) nil t)
                  (or (dialog--in-comment-p)
                      (setq arg (funcall inc-fn arg)
                            match-pos (line-beginning-position))))))
    (and match-pos (goto-char match-pos))))

(defun dialog-end-of-defun ()
  "Move forwards to the end of a rule-head."
  (end-of-line)
  (or (and (re-search-forward (rx bol graphic) nil t)
           (progn (forward-char -2) t))
      (goto-char (point-max))))

;;;; Indentation

(defcustom dialog-dedent-line
  (rx (or (syntax ?\)) (seq "(or)" (0+ whitespace) (or "%%" line-end))))
  "A regular expression which should match lines to dedent.

The match is made with point at the indentation column for the line.  A
successful match means that indentation for the line will be decreased
to align with the block-opening."
  :type 'string
  :safe #'stringp)

(defcustom dialog-indent-inside-block
  (rx (or (or ?\( ?\[) (seq ?\{ (or whitespace line-end))))
  "A regular expression which should match a block to indent.

The match is made with point before the character which opens the block.
A successful match means that indentation inside the block will be
increased.

This value had no effect for lines following block-defining syntax such
as \"(if)\".  To configure indentation following special syntax, modify
the value of `dialog-indent-inside-special-syntax'."
  :type 'string
  :safe #'stringp)

(defcustom dialog-indent-inside-special-syntax t
  "Specifies whether lines following special syntax are indented.

A non-nil value means that the indentation level will be increased for
lines following special block-defining syntax such as \"(if)\"."
  :type 'boolean
  :safe #'booleanp)

(defcustom dialog-indent-initial-size 1
  "Specifies a multiplier used for the first level of indentation.

Increasing this to 2 will give a double sized indent for the first level
of indentation but a normally sized indent for subsequent levels."
  :type 'integer
  :safe #'integerp)

(defcustom dialog-indent-offset 8
  "Specifies the indentation offset applied by `dialog-indent-line'.

Lines determined to be within blocks are indented by this number of
columns per block level."
  :type 'integer
  :safe #'integerp)

(cl-defgeneric dialog--indent-block-p (block in-list)
  "Return whether BLOCK increases the indentation level.

IN-LIST is ignored."
  (ignore in-list)
  (save-excursion
    (goto-char (dialog-block-position block))
    (looking-at-p dialog-indent-inside-block)))

(cl-defmethod dialog--indent-block-p ((block dialog-statement) in-list)
  "Return whether BLOCK increases the indentation level.

IN-LIST should be non-nil when the original block search stared inside
the punctuation will defines the block."
  (cond (in-list
         (save-excursion
           (goto-char (dialog-block-position block))
           (looking-at-p dialog-indent-inside-block)))
        (dialog-indent-inside-special-syntax
         (dialog-statement-symbol block))))

(defun dialog--new-indent ()
  "Return the calculated indentation level for the current line."
  (save-excursion
    (back-to-indentation)
    (if-let* ((opening-block (dialog--parse-dominating-block)))
        ;; Calculate new level.
        (let ((line-sticky (and (zerop (current-column))
                                (/= (line-end-position) (point))))
              (line-block (save-excursion
                            (dialog--forward-prefix-chars)
                            (dialog--parse-block-at-point)))
              (inside-list (eq (dialog--list-start)
                               (dialog-block-position opening-block)))
              (new-level 0))
          ;; Decrement indentation to match particular indentation styles.
          (when (and (dialog--indent-block-p opening-block inside-list)
                     (looking-at-p dialog-dedent-line))
            (cl-decf new-level))
          (cond ((dialog--rule-head-p opening-block)
                 ;; Increase indentation when the block opening is a rule-head,
                 ;; unless the line being indented starts in column zero and is
                 ;; not empty.
                 (unless line-sticky
                   (cl-incf new-level dialog-indent-initial-size)))
                (inside-list
                 ;; Increase indentation when inside a statement.
                 (when (dialog--indent-block-p opening-block inside-list)
                   (cl-incf new-level)))
                (dialog-indent-inside-special-syntax
                 ;; Add indentation based on matching block tokens.
                 (pcase (cons (dialog-statement-symbol opening-block)
                              (and (dialog-statement-p line-block)
                                   (dialog-statement-symbol line-block)))
                   ;; Avoid further pattern matches if there is no block open.
                   (`(nil . ,_))
                   ;; Avoid further pattern matches for a block open without a
                   ;; block close.
                   (`(,_ . nil) (cl-incf new-level))
                   ;; Matching token pairs.
                   ((or
                     ;; (if) ... (then) ... (elseif) ... (then) ... (else) ... (endif)
                     `(dialog-if-t         . ,(or 'dialog-then-t
                                                  'dialog-elseif-t
                                                  'dialog-else-t
                                                  'dialog-endif-t))
                     `(dialog-then-t       . ,(or 'dialog-elseif-t
                                                  'dialog-else-t
                                                  'dialog-endif-t))
                     `(dialog-elseif-t     . ,(or 'dialog-then-t
                                                  'dialog-elseif-t
                                                  'dialog-else-t
                                                  'dialog-endif-t))
                     '(dialog-else-t       . dialog-endif-t)
                     '(dialog-accumulate-t . dialog-into-t)
                     '(dialog-collect-t    . dialog-into-t)
                     '(dialog-determine-t  . dialog-from-t)
                     '(dialog-from-t       . dialog-matching-t)
                     `(dialog-select-t     . ,(or 'dialog-stopping-t
                                                  'dialog-cycling-t
                                                  'dialog-at-random-t))))
                   ;; Default to increasing the indentation.
                   (_ (cl-incf new-level)))))
          ;; Move to the position where the current block was opened.
          (goto-char (dialog-block-position opening-block))
          (max (+ (current-indentation) (* new-level dialog-indent-offset))
               0))
      ;; If there is no block then this is the first statement in the file.
      0)))

(defun dialog-indent-line ()
  "Indent the current line to match the block level.

When point is within the current indentation it will move to the new
indentation column."
  (let ((new-indent (dialog--new-indent))
        (cur-indent (current-indentation)))
    (if (= new-indent cur-indent)
        'noindent
      (let ((goto-indentation (<= (current-column) cur-indent)))
        (save-excursion
          (indent-line-to new-indent))
        (when goto-indentation
          (back-to-indentation))))))

(defun dialog-toggle-indent ()
  "Toggle indentation for the current line."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (if (cl-plusp (skip-chars-forward " \t"))
        (delete-region (line-beginning-position) (point))
      (tab-to-tab-stop)
      (funcall indent-line-function)))
  ;; Move to the current indentation column when inside indentation.
  (when (<= (current-column) (current-indentation))
    (back-to-indentation)))

;;;; Align

(defcustom dialog-align-rules-list
  `((dialog-rule-body
     (regexp   . ,#'dialog-align-rule-match)
     (separate . group)
     (tab-stop . t)
     (valid    . ,#'dialog-align-rule-match-valid-p)))
  "Specifies the list of available alignment rules.

See the variable `align-rules-list' for details on the list and rule
formats."
  :type align-rules-list-type
  :risky t)

(defun dialog-align-rule-match (bound _no-error)
  "Match a line for alignment and set match data.

Do not search beyond BOUND.  Return the buffer position for the end of
the match or nil if there was no match."
  (let* ((forwards (cl-plusp bound))
         (bound-check-func (if forwards #'>= #'<=))
         (search-func (if forwards #'re-search-forward #'re-search-backward))
         new-pos)
    (when (funcall bound-check-func bound (point))
      (save-excursion
        (when (funcall search-func (dialog-rx rule-head-start) bound t)
          ;; Move to the opening "(".
          (beginning-of-line)
          (dialog--forward-prefix-chars)
          ;; Move across the sexp and look for a whitespace separator.
          (condition-case nil
              (progn
                (forward-sexp)
                (when (re-search-forward
                       (rx (group (0+ whitespace))) (line-end-position) t)
                  (setq new-pos (if forwards
                                    ;; Already at the end of the match.
                                    (point)
                                  ;; Move as if searching backwards.
                                  (line-beginning-position)))))
            (scan-error)))))
    (and new-pos (goto-char new-pos))))

(defun dialog-align-rule-match-valid-p ()
  "Validate the current alignment rule.

Ignore matches where the match ends at the end of the line.  This
prevents whitespace adjustments being made for lines which have no
trailing syntax while still allowing the alignment to work across a
region which contains such lines."
  (/= (match-end 0) (line-end-position)))

(add-to-list 'align-open-comment-modes 'dialog-mode)

;;;; Comint

(defvar-local dialog-game-files nil
  "The configured game files for a given project.

The value should be a list of strings.  The recommended way to set this
value is by using directory local variables.")

;;;###autoload
(put 'dialog-game-files 'safe-local-variable #'listp)

(defcustom dialog-debug-buffer-name "*dgdebug*"
  "Specifies the buffer name used for the debug process buffer."
  :type 'string)

(defun dialog-debug-buffer ()
  "Return the current debug buffer."
  (if (derived-mode-p 'dialog-debug-mode)
      (current-buffer)
    (get-buffer dialog-debug-buffer-name)))

(defun dialog-debug-display-buffer ()
  "Display the current debug buffer."
  (interactive)
  (if-let* ((buffer (dialog-debug-buffer)))
      (display-buffer buffer)
    (user-error "No debug buffer exists")))

(defun dialog-debug-process ()
  "Return the current debug process."
  (and-let* ((buffer (dialog-debug-buffer)))
    (get-buffer-process buffer)))

(defcustom dialog-debug-program "dgdebug"
  "Specifies the name of the Dialog debugger executable."
  :type 'string)

(defcustom dialog-debug-as-interp (not (eq system-type 'windows-nt))
  "Specifies whether the debug program runs as a command interpreter.

A non-nil value will start the debug program using `comint' which
enables interactive debugging and sending commands to the game as it is
running.  A value of nil means that the process is launched directly
with no further process control."
  :type 'boolean
  :safe #'booleanp)

;;;###autoload
(defun dialog-debug-run (&optional prompt)
  "Run the Dialog debugger and/or display its buffer.

The value of `dialog-game-files' determines which files are loaded by
the debug program.  If the value is nil a prompt will appear to specify
which game files should be loaded.  Filenames should be specified
relative to the project root, as determined by `project-root'.  If the
project root cannot be determined the value of `default-directory' will
be used in its place.  When called with a single prefix argument PROMPT,
always prompt for the game files.  When called with a double prefix
argument, always prompt for the project root and the game files.

If `dialog-debug-as-interp' is nil the debug program is started with no
further process control and no associated buffer, otherwise it will be
started in a `dialog-debug-mode' buffer.  The current buffer will be
re-used if its major mode is `dialog-debug-mode', otherwise an existing
buffer will be re-used if its name matches `dialog-debug-buffer-name';
to support multiple processes rename an existing buffer with
\\[rename-buffer] to allow the creation of a new one.  The currently
used buffer will be displayed if it exists."
  (interactive "P")
  (let ((buffer (and dialog-debug-as-interp
                     (or (dialog-debug-buffer)
                         (with-current-buffer (generate-new-buffer
                                               dialog-debug-buffer-name)
                           (dialog-debug-mode)
                           (current-buffer))))))
    (unless (and buffer (comint-check-proc buffer))
      (let* ((program (or (executable-find dialog-debug-program)
                          (user-error "Cannot find debug program '%s'"
                                      dialog-debug-program)))
             (program-basename (file-name-base program))
             ;; Force a prompt for the game directory with a double prefix
             ;; argument.  Fallback to the current directory if there is no
             ;; project.
             (game-directory (if (equal prompt '(16))
                                 (read-directory-name
                                  "Game directory: " nil nil t)
                               (dialog--project-directory)))
             ;; Prompt for game files if none are defined or if there was a
             ;; prefix argument.
             (game-files (or (and (not prompt) dialog-game-files)
                             (mapcar (lambda (file)
                                       (if (file-name-absolute-p file)
                                           ;; Expand ~ in absolute names.
                                           (expand-file-name file)
                                         ;; Keep relative names.
                                         file))
                                     (let ((default-directory game-directory))
                                       (completing-read-multiple
                                        "Game files: "
                                        #'completion-file-name-table))))))
        (cond (dialog-debug-as-interp
               (with-current-buffer buffer
                 (setq default-directory game-directory))
               (apply #'make-comint-in-buffer
                      program-basename buffer program nil game-files))
              (t
               (message "Starting debug program")
               (let ((default-directory game-directory))
                 (apply #'start-process
                        program-basename buffer program game-files))))))
    (when buffer
      (pop-to-buffer buffer))))

(defcustom dialog-debug-send-command-default "@replay"
  "Specifies the default command sent to the debug process.

The command is sent by the function `dialog-debug-send-command'."
  :type 'string)

(defcustom dialog-debug-send-command-function
  (if dialog-debug-as-interp
      #'dialog-debug-send-command-with-comint
    #'dialog-debug-send-command-with-clipboard)
  "Specifies the function used to send a command to the debug program.

The function should locate the active instance of the debugger and send
the value of the variable `dialog-debug-send-command-input' plus an
additional newline character."
  :type 'function)

(defcustom dialog-debug-send-command-hook (list #'save-some-buffers)
  "A hook which is called before sending a command to the debug process.

At the time that the hook functions are called, the value of the
variable `dialog-debug-send-command-input' contains the current command
which is about to be sent to a live process in the debug buffer."
  :type 'hook)

(defcustom dialog-debug-send-command-prompt-sets-default nil
  "Specifies whether to set the default command from the prompt.

A non-nil value means that the command entered at the prompt will become
the new default value to send when the prompt for a command is not
shown."
  :type 'boolean
  :safe #'booleanp)

(defvar dialog-debug-send-command-input nil
  "The current command which is being sent to the debug process.")

(defvar dialog-debug-send-command-history nil
  "History of minibuffer input for `dialog-debug-send-command'.")

(defun dialog-debug-send-command-presets-valid-p (alist)
  "Check that ALIST is an alist of strings."
  (and (listp alist)
       (cl-loop for preset in alist
                unless (and (consp preset)
                            (stringp (car preset))
                            (stringp (cdr preset)))
                return nil
                finally return t)))

(defcustom dialog-debug-send-command-presets
  '(("(restart)"   . "Restart the program")
    ("(trace off)" . "Disable query tracing")
    ("(trace on)"  . "Enable query tracing")
    ("(undo)"      . "Restore the program state at the time of the latest (save undo 0)")
    ("@again"      . "Undo, then re-enter the last line of game input")
    ("@dynamic"    . "Show the current state of all dynamic predicates")
    ("@g"          . "Undo, then re-enter the last line of game input")
    ("@help"       . "Display the debugger help text")
    ("@quit"       . "Quit the debugger")
    ("@replay"     . "Restart, then replay the accumulated game input")
    ("@restore"    . "Restart and read game input from a file")
    ("@save"       . "Save accumulated game input to a file")
    ("@tree"       . "Show the current state of the object tree"))
  "Alist of commands to send and their descriptions.

These commands are suggested during command completion and are also made
available to send using menus."
  :type '(repeat
	  (cons (string :tag "Command")
		(string :tag "Description")))
  :safe #'dialog-debug-send-command-presets-valid-p)

(defun dialog-debug-send-command (&optional prompt)
  "Send a command to the debug program.

The default command to send is determined by the value of
`dialog-debug-send-command-default'.  With a prefix argument PROMPT,
prompt for the command to send instead of using the default."
  (interactive "P")
  (let ((dialog-debug-send-command-input
         (if prompt
             (let ((source-buffer (current-buffer)))
               (dialog--completing-read
                "Command: "
                (lambda (string pred action)
                  (if (eq action 'metadata)
                      (list
                       'metadata
                       (cons 'annotation-function #'dialog--annotate-command)
                       (cons 'group-function #'dialog--group-command))
                    (complete-with-action
                     action
                     (buffer-local-value
                      'dialog-debug-send-command-presets source-buffer)
                     string
                     pred)))
                nil nil nil 'dialog-debug-send-command-history))
           dialog-debug-send-command-default)))
    (when (and prompt dialog-debug-send-command-prompt-sets-default)
      (setq dialog-debug-send-command-default dialog-debug-send-command-input))
    (run-hooks 'dialog-debug-send-command-hook)
    (funcall dialog-debug-send-command-function)))

(defun dialog-debug-send-command-from-line (&optional no-error)
  "Send the current line as a command to the debug program.

Leading and trailing whitespace on the line is removed.  If the line
begins with comment syntax this is also removed.  When NO-ERROR is
non-nil do not emit an error when refusing to send a line because it was
empty."
  (interactive)
  (let ((dialog-debug-send-command-default
         (replace-regexp-in-string
          (rx string-start (>= 2 ?%) (0+ whitespace))
          ""
          (string-trim
           (buffer-substring-no-properties (line-beginning-position)
                                           (line-end-position))))))
    (if (string-empty-p dialog-debug-send-command-default)
        (unless no-error
          (user-error "Current line is empty"))
      (dialog-debug-send-command))))

(defun dialog-debug-send-command-from-region ()
  "Send the active region as a command to the debug program.

The region is sent line-by-line with any leading comment syntax removed.
Empty lines are not sent."
  (interactive)
  (if (use-region-p)
      (save-excursion
        (save-restriction
          (narrow-to-region (region-beginning) (region-end))
          (goto-char (point-min))
          (while (and (progn (dialog-debug-send-command-from-line 'no-error) t)
                      (zerop (forward-line))
                      (not (eobp))))))
    (user-error "No active region")))

(defun dialog-debug-send-command-dwim ()
  "Send the active region or current line as a command to the debug program.

When a region is active, send the region, otherwise send the current line."
  (interactive)
  (if (use-region-p)
      (dialog-debug-send-command-from-region)
    (dialog-debug-send-command-from-line)))

(defun dialog-debug-send-command-with-clipboard ()
  "Save a command to the clipboard."
  (gui-set-selection 'CLIPBOARD dialog-debug-send-command-input)
  (message "Command '%s' saved to clipboard" dialog-debug-send-command-input))

(defun dialog-debug-send-command-with-comint ()
  "Send a command to the debug process in the comint buffer."
  (when-let* ((process (or (dialog-debug-process)
                           (user-error "No debug process is running"))))
    (message "Sending command '%s' to process '%s'"
             dialog-debug-send-command-input (process-name process))
    (comint-simple-send process dialog-debug-send-command-input)))

(defun dialog-debug-set-default-command ()
  "Set the default command to be sent to the debug process."
  (interactive)
  (setq dialog-debug-send-command-default
        (let ((source-buffer (current-buffer)))
          (dialog--completing-read
           "Default command: "
           (lambda (string pred action)
             (if (eq action 'metadata)
                 (list 'metadata
                       (cons 'annotation-function #'dialog--annotate-command)
                       (cons 'group-function #'dialog--group-command))
               (complete-with-action
                action
                (buffer-local-value
                 'dialog-debug-send-command-presets source-buffer)
                string
                pred)))))))

(defcustom dialog-debug-use-pty t
  "Specifies whether the debug process uses a pseudo-terminal.

A value of nil indicates to use a pipe instead of a pseudo-terminal.  A
value of t indicates to use a pseudo-terminal.  The debug buffer needs
to be recreated for changes to this variable to take effect.

Running the debug process in a pseudo-terminal makes it work more like
it would in traditional terminal."
  :type 'boolean
  :safe #'booleanp)

(defun dialog-debug-toggle-use-pty ()
  "Toggle the value of `dialog-debug-use-pty'."
  (interactive)
  (setq dialog-debug-use-pty (not dialog-debug-use-pty))
  (message "Use of a pseudo-terminal for the next debug buffer is now %s"
           (if dialog-debug-use-pty "enabled" "disabled")))

(defvar dialog-debug-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'dialog-debug-send-command)
    (define-key map (kbd "C-c C-d d") #'dialog-data-display-dynamic)
    (define-key map (kbd "C-c C-d t") #'dialog-data-display-tree)
    (define-key map (kbd "C-c C-z") #'quit-window)
    (set-keymap-parent map comint-mode-map)
    map))

(easy-menu-define dialog-debug-mode-menu dialog-debug-mode-map
  "Menu for Dialog Debug Mode."
  '("Dialog"
    ["Enable automatic debug command sending" dialog-debug-auto-command-mode
     :style toggle
     :selected dialog-debug-auto-command-mode
     :help "Enable automatically sending debug commands at the debug prompt"]
    ["Enable automatic debug output responses" dialog-debug-auto-response-mode
     :style toggle
     :selected dialog-debug-auto-response-mode
     :help "Enable automatically sending responses to debug output"]
    ["Enable trace highlighting and keymaps" dialog-trace-mode
     :style toggle
     :selected dialog-trace-mode
     :help "Enable highlighting and add keymaps to trace output"]
    ["Enable automatic display of trace source files" dialog-trace-follow-mode
     :style toggle
     :selected dialog-trace-follow-mode
     :help "Enable automatic display of source files referenced in trace output"]
    "---"
    ["Start the debug program" dialog-debug-run
     :active (not (dialog-debug-process))
     :help "Start the Dialog debug program"]
    ["Display the current dynamic data state" dialog-data-display-dynamic
     :active (dialog-data-buffer "@dynamic")
     :visible dialog-debug-as-interp
     :help "Display the buffer for the current dynamic data state"]
    ["Display the current object tree" dialog-data-display-tree
     :active (dialog-data-buffer "@tree")
     :visible dialog-debug-as-interp
     :help "Display the buffer for the current object tree state"]
    "---"
    ["Set the default command to send" dialog-debug-set-default-command
     :help "Set the default command to send to the debug program"]
    ["Send default command" dialog-debug-send-command
     :active (or (not dialog-debug-as-interp) (dialog-debug-process))
     :help "Send the default command to the debug program"]
    ["Send command"
     (lambda ()
       (interactive)
       (dialog-debug-send-command 'prompt))
     :active (or (not dialog-debug-as-interp) (dialog-debug-process))
     :help "Send a command to the debug program"]
    "---"
    ["Browse the manual" dialog-browse-manual
     :help "Browse the Dialog manual in the default browser"]))

(define-derived-mode dialog-debug-mode comint-mode "DGDebug"
  "Major mode for running the Dialog interactive debugger.

\\<dialog-debug-mode-map>"
  (setq comint-process-echoes t)
  (setq-local comint-prompt-read-only t)
  (setq-local comint-prompt-regexp (rx line-start "> "))
  (setq-local process-connection-type dialog-debug-use-pty)
  (setq-local scroll-conservatively most-positive-fixnum)
  (hack-dir-local-variables-non-file-buffer)
  ;; After local variables have loaded.
  (dialog--add-to-menu))

(add-hook 'dialog-debug-mode-hook #'dialog-debug-auto-command-mode)
(add-hook 'dialog-debug-mode-hook #'dialog-trace-mode)

;;;;; Comint auto-commands

(defvar-local dialog-debug-auto-command-buffer nil
  "The buffer used for capturing command output.")

(defvar-local dialog-debug-auto-command-queue nil
  "The current queue of commands to automatically send.")

(defvar-local dialog-debug-auto-commands (list "@dynamic" "@tree")
  "The list of commands to automatically send following normal output.")

(defcustom dialog-debug-auto-command-hook
  (list #'dialog-data-collect #'dialog-data-render)
  "A hook which is called after each auto-command output."
  :type 'hook)

(defcustom dialog-debug-auto-command-setup-hook
  (list #'dialog-data-capture-reset)
  "A hook which is called before any auto-commands have been sent."
  :type 'hook)

(defun dialog-debug-auto-command-send (string)
  "Check STRING for a prompt and respond by sending debug commands."
  (let* ((auto-command (car dialog-debug-auto-command-queue))
         (at-prompt (if auto-command
                        ;; This is auto-command output.  Insert it into capture
                        ;; buffer and then check for a prompt in that buffer.
                        ;; Process ANSI control sequences for the most recent
                        ;; line and the new chunk of output.
                        (with-current-buffer dialog-debug-auto-command-buffer
                          (let ((inhibit-read-only t)
                                (line-pos (line-beginning-position)))
                            (insert string)
                            (ansi-color-filter-region line-pos (point)))
                          ;; Don't override the start position for the next
                          ;; usage of `ansi-color-filter-region' to ensure that
                          ;; ANSI sequences split between chunks are processed.
                          (setq ansi-color-context-region nil)
                          ;; Check for a prompt in the capture buffer.
                          (string-equal "> " (buffer-substring-no-properties
                                              (line-beginning-position)
                                              (point))))
                      ;; This is regular output.  Check for the prompt in the
                      ;; last line of the Comint buffer with the new string
                      ;; appended to it once ANSI control sequences are
                      ;; processed.
                      (string-suffix-p
                       "\n> "
                       (ansi-color-apply
                        (concat (buffer-substring-no-properties
                                 (line-beginning-position) (point))
                                string)))))
         (process (get-buffer-process (current-buffer))))
    (when at-prompt
      ;; Run hooks when seeing a prompt after an auto-command.
      (when auto-command
        (run-hooks 'dialog-debug-auto-command-hook))
      ;; Setup auto-commands if at the prompt and popping the current
      ;; auto-command from the queue gives no command.
      (unless (pop dialog-debug-auto-command-queue)
        ;; Setup the auto-command queue.
        (setq dialog-debug-auto-command-queue
              (copy-sequence dialog-debug-auto-commands))
        ;; Make the pseudo-terminal taller and override the adjustment function
        ;; so that any window sizes changes don't reset the size to match the
        ;; window.
        (when process-connection-type
          (advice-add 'window--adjust-process-windows :override #'ignore)
          (set-process-window-size process 65535 79))
        (run-hooks 'dialog-debug-auto-command-setup-hook))
      ;; Check whether there is a next command to send.
      (if-let* ((next-command (car dialog-debug-auto-command-queue)))
          (progn
            ;; Create/Clear the output buffer and send the next auto-command.
            (with-current-buffer (setq
                                  dialog-debug-auto-command-buffer
                                  (get-buffer-create
                                   (dialog--derived-buffer-name
                                    (buffer-name) "auto-command" 'private)))
              (let ((inhibit-read-only t))
                (erase-buffer)))
            ;; Send the next command.
            (comint-simple-send process next-command))
        ;; All auto-commands have been sent, and so restore the pseudo-terminal
        ;; size.  An immediate resize can potentially jam the Comint buffer if
        ;; someone is pressing keys as fast as they can and the system is slow,
        ;; so use an idle timer.
        (when process-connection-type
          (advice-remove 'window--adjust-process-windows #'ignore)
          (run-with-idle-timer 0.25 nil #'window--adjust-process-windows))))
    ;; Don't insert auto-command output into the Comint buffer.
    (if auto-command "" string)))

(define-minor-mode dialog-debug-auto-command-mode
  "Enable automatic commands from Comint output filters."
  :lighter " AutoCommand"
  :interactive (dialog-debug-mode)
  (if dialog-debug-auto-command-mode
      (add-hook 'comint-preoutput-filter-functions
                #'dialog-debug-auto-command-send 90 t)
    (remove-hook 'comint-preoutput-filter-functions
                 #'dialog-debug-auto-command-send t)))

(defun dialog-debug-auto-output-responder (_string)
  "Respond to process output by sending additional input."
  (when-let* ((process (get-buffer-process (current-buffer))))
    (save-excursion
      (goto-char (point-max))
      (pcase (buffer-substring-no-properties (line-beginning-position) (point))
        ("[more]" (comint-send-string process "\n"))))))

(define-minor-mode dialog-debug-auto-response-mode
  "Enable automatic responses from Comint output filters."
  :lighter " AutoResponse"
  :interactive (dialog-debug-mode)
  (if dialog-debug-auto-response-mode
      (add-hook 'comint-output-filter-functions
                #'dialog-debug-auto-output-responder 90 t)
    (remove-hook 'comint-output-filter-functions
                 #'dialog-debug-auto-output-responder t)))

;;;;; Comint data collection and display.

(defvar-local dialog-data-command-output nil
  "Alist of commands and command output.")

(defun dialog-data-capture-reset ()
  "Remove previous captured output."
  (setq dialog-data-command-output nil))

(defun dialog-data-collect ()
  "Collect output from the auto-command buffer and store it for later use."
  (when-let* ((command-output
               (with-current-buffer dialog-debug-auto-command-buffer
                 (goto-char (point-min))
                 (and (re-search-forward (rx line-start
                                             (group (1+ (not control)))
                                             (opt ?\C-m)
                                             ?\C-j)
                                         nil t)
                      (let ((command (match-string-no-properties 1))
                            (output (buffer-substring-no-properties
                                     (point) (- (point-max) 2))))
                        (cons command output))))))
    ;; Store in the debug buffer.
    (push command-output dialog-data-command-output)))

(defun dialog-data-render ()
  "Render the most recent captured output into a presentation buffer."
  (pcase (car dialog-data-command-output)
    (`(,command . ,output)
     (let* ((buffer-name (dialog--derived-buffer-name (buffer-name) command))
            (old-buffer (get-buffer buffer-name))
            (buffer (or old-buffer
                        (with-current-buffer (generate-new-buffer buffer-name)
                          (dialog-data-mode)
                          (current-buffer)))))
       (with-temp-buffer
         ;; Insert with trailing white-space removed.
         (insert (replace-regexp-in-string (rx (1+ blank) line-end) "" output))
         ;; Remove leading indentation.
         (when-let* ((initial-indent (cl-loop initially (goto-char (point-min))
                                              for indent = (current-indentation)
                                              when (cl-plusp indent)
                                              minimize indent
                                              while (zerop (forward-line)))))
           (indent-rigidly (point-min) (point-max) (- initial-indent)))
         ;; Non-destructive replacement of previous buffer contents.
         (let ((temp-buffer (current-buffer)))
           (with-current-buffer buffer
             (save-restriction
               (widen)
               (let ((inhibit-read-only t))
                 (replace-buffer-contents temp-buffer)))
             ;; When this is a brand new buffer, leave point at the start of it.
             (unless old-buffer
               (goto-char (point-min))))))))))

(defun dialog-data-buffer (command)
  "Return the buffer containing the output of the COMMAND."
  (and-let* ((debug-buffer (dialog-debug-buffer)))
    (get-buffer (dialog--derived-buffer-name
                 (buffer-name debug-buffer) command))))

(defun dialog-data-display-dynamic ()
  "Display the buffer containing \"@dynamic\" command output."
  (interactive)
  (if-let* ((buffer (dialog-data-buffer "@dynamic")))
      (display-buffer buffer)
    (user-error "No data buffer for @dynamic output exists")))

(defun dialog-data-display-tree ()
  "Display the buffer containing \"@tree\" command output."
  (interactive)
  (if-let* ((buffer (dialog-data-buffer "@tree")))
      (display-buffer buffer)
    (user-error "No data buffer for @tree output exists")))

(defvar dialog-data-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") #'next-line)
    (define-key map (kbd "p") #'previous-line)
    map))

(define-derived-mode dialog-data-mode special-mode "DGData"
  "Major mode for interacting with Dialog state data."
  ;; Font-lock needs to be active so that `outline-minor-mode-highlight' is
  ;; reapplied reliably, as well as to identify the heading if
  ;; `outline-minor-mode' gets disabled.
  (setq-local font-lock-defaults
              `(((,(rx line-start (char (?A . ?Z)) (1+ not-newline))
                  . 'underline))
                'keywords-only))
  (setq-local outline-level (lambda () 1))
  (setq-local outline-minor-mode-cycle t)
  (setq-local outline-minor-mode-cycle-filter nil)
  (setq-local outline-minor-mode-highlight 'override)
  (setq-local outline-minor-mode-use-buttons t)
  (setq-local outline-regexp (rx line-start (char (?A . ?Z)))))

(add-hook 'dialog-data-mode-hook #'outline-minor-mode)

;;;; Completion

(defun dialog--annotate-command (command)
  "Return the annotation for COMMAND."
  (and-let* ((item (assoc command dialog-debug-send-command-presets))
             (description (cdr item)))
    (concat " " description)))

(defun dialog--completing-read (&rest args)
  "Completing-read with Dialog specific minibuffer keymap.

Call `completing-read' with ARGS using a minibuffer keymap that doesn't
bind special completion commands to the space and \"?\" keys."
  (let ((minibuffer-local-completion-map
         (copy-keymap minibuffer-local-completion-map)))
    (define-key minibuffer-local-completion-map " " #'self-insert-command)
    (define-key minibuffer-local-completion-map "?" #'self-insert-command)
    (apply #'completing-read args)))

(defun dialog--group-command (command transform)
  "Group COMMAND by its command type.

When TRANSFORM is non-nil return the command, otherwise return the
command type."
  (cond (transform
         command)
        ((string-prefix-p "(" command)
         "Predicate")
        ((string-prefix-p "@" command)
         "Debug command")
        (t
         "Input")))

;;;; Documentation look-up

(defcustom dialog-manual-url "https://dialog-if.github.io/manual/"
  "Specifies the URL of the Dialog manual."
  :type 'string
  :safe #'stringp)

;;;###autoload
(defun dialog-browse-manual (&optional secondary)
  "Browse the online version of the Dialog manual.

With prefix argument SECONDARY use the secondary browser instead of the
default browser."
  (interactive "P")
  (let ((browse-url-browser-function
         (if secondary
             browse-url-secondary-browser-function
           browse-url-browser-function)))
    (browse-url dialog-manual-url)))

;;;; Electric-indent

(defun dialog-electric-indent (char)
  "Return whether inserting CHAR will re-indent the current line.

If a newline character is inserted on a line which begins in column 0,
do not re-indent the line."
  (and (= char ?\C-j)
       (save-excursion
         (forward-char -1)
         (zerop (current-indentation)))
       'no-indent))

;;;; Filling

(defun dialog-do-auto-fill ()
  "Dialog specific auto-fill function."
  (when (or
         ;; Any line which has some indentation.
         (cl-plusp (current-indentation))
         ;; Comments which start in column 0.
         (and-let* ((start (dialog--start-of-comment-or-string)))
           (save-excursion
             (goto-char start)
             (zerop (current-column)))))
    ;; Stop `default-indent-new-line' starting a line in column zero.
    (let ((indent-line-function #'indent-relative))
      (do-auto-fill))))

;;;; Flymake

(defcustom dialog-compiler-program "dialogc"
  "Specifies the name of the Dialog compiler executable."
  :type 'string)

;; Prevent byte-compiler warnings when Flymake is not loaded.
(declare-function flymake-diagnostic-data "flymake" (diag))
(defvar flymake-list-only-diagnostics)

(defun dialog--clear-flymake-diagnostics ()
  "Delete all global list-only diagnostics which relate to this project.

Verify that the diagnostics originated from this Flymake backend by
checking for diagnostic data which was added as an identifier."
  (let ((project-directory (dialog--project-directory)))
    (setq flymake-list-only-diagnostics
          (cl-loop for (file . diags) in flymake-list-only-diagnostics
                   when (file-in-directory-p file project-directory)
                   do (setq diags
                            (cl-loop
                             for diag in diags
                             unless (eq (flymake-diagnostic-data diag) 'dialogc)
                             collect diag))
                   when diags
                   collect (cons file diags)))))

(defun dialog--make-flymake-command ()
  "Return the list of strings to run the Flymake process."
  (append (list dialog-compiler-program
                "--output" (if (eq system-type 'windows-nt)
                               "nul"
                             "/dev/null"))
          dialog-game-files))

(defvar-local dialog--flymake-proc nil
  "The currently active Flymake process.")

(defconst dialog-error-regexp
  (rx line-start
      (group (1+ alpha)) ": "          ; Error type
      (group (1+ (not ?,))) ", line "  ; Filename
      (group (1+ digit)) ": "          ; Line number
      (group (1+ not-newline))         ; Message
      line-end)
  "A regexp pattern which matches error output from the Dialog compiler.")

;; Configure additional diagnostic symbols for "Debug" and "Info" messages.
(put :dialog-debug 'flymake-category 'flymake-note)
(put :dialog-debug 'flymake-type-name "debug")
(put :dialog-info 'flymake-category 'flymake-note)
(put :dialog-info 'flymake-type-name "info")

(defun dialog-flymake (report-fn &rest _args)
  "Flymake backend for Dialog.

REPORT-FN is Flymake's callback function."
  (unless (executable-find dialog-compiler-program)
    (error "Cannot find Dialog compiler"))
  (when (process-live-p dialog--flymake-proc)
    (kill-process dialog--flymake-proc))
  (let ((default-directory (dialog--project-directory))
        (source-buffer (current-buffer)))
    (if dialog-game-files
        (dolist (file dialog-game-files)
          (unless (file-exists-p file)
            (flymake-log :warning "Game file '%s' does not exist" file)))
      (flymake-log :warning "No game files are configured"))
    (save-restriction
      (widen)
      (setq
       dialog--flymake-proc
       (make-process
        :name "dialog-flymake"
        :noquery t
        :connection-type 'pipe
        :buffer (generate-new-buffer " *dialog-flymake*")
        :command (dialog--make-flymake-command)
        :sentinel
        (lambda (proc _event)
          (when (memq (process-status proc) '(exit signal))
            (unwind-protect
                (if (with-current-buffer source-buffer
                      (eq proc dialog--flymake-proc))
                    (with-current-buffer (process-buffer proc)
                      (goto-char (point-min))
                      (let ((ht (make-hash-table :test #'equal))
                            (source-file (buffer-file-name source-buffer))
                            source-diags)
                        ;; Push all diagnostics into a hash table to group them
                        ;; by filename.
                        (cl-loop
                         while (re-search-forward dialog-error-regexp nil t)
                         for type = (pcase (match-string 1)
                                      ("Debug"   :dialog-debug)
                                      ("Error"   :error)
                                      ("Info"    :dialog-info)
                                      ("Warning" :warning)
                                      (_         :note))
                         for filename = (match-string 2)
                         for beg = (cons (string-to-number (match-string 3)) 0)
                         for msg = (match-string 4)
                         for diag = (flymake-make-diagnostic
                                     filename beg nil type msg 'dialogc)
                         do (push diag (gethash filename ht)))
                        ;; Add all but the diagnostics for the source buffer as
                        ;; list-only diagnostics.
                        (dialog--clear-flymake-diagnostics)
                        (maphash
                         (lambda (file diags)
                           (if (and source-file (file-equal-p file source-file))
                               (setq source-diags diags)
                             (push (cons (expand-file-name file) diags)
                                   flymake-list-only-diagnostics)))
                         ht)
                        (funcall report-fn source-diags)))
                  (flymake-log :warning "Canceling obsolete check %s" proc))
              (kill-buffer (process-buffer proc))))))))))

;;;; Imenu

(defcustom dialog-imenu-topic-separator imenu-level-separator
  "Specifies the topic separator used for Imenu names."
  :type 'string
  :safe #'stringp)

(defun dialog--create-imenu-index ()
  "Build and return an Imenu index alist."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (cl-loop
       with topic
       while (re-search-forward (dialog-rx (or rule-head-start topic)) nil t)
       for position = (match-beginning 0)
       if (= (char-after position) ?#)  ; Topic.
       collect (cons (setq topic (match-string-no-properties 0))
                     (if imenu-use-markers
                         (copy-marker position t)
                       position))
       else  ; Rule-head.
       collect (let* ((end (progn (forward-char -1) (dialog--list-end)))
                      (rule-head (dialog--normalize-string
                                  (buffer-substring-no-properties
                                   position
                                   (if end (1+ end) (line-end-position))))))
                 ;; Skip the rule-body for the next match.
                 (dialog-end-of-defun)
                 ;; Prepend the topic if there is one and the rule uses it.
                 (cons (if (and topic (dialog--rule-uses-topic-p))
                           (concat topic dialog-imenu-topic-separator rule-head)
                         rule-head)
                       (if imenu-use-markers
                           (copy-marker position t)
                         position)))))))

;;;; Outline

(defun dialog-outline-level ()
  "Return the depth for the current outline heading."
  (cl-case (char-after)
    ;; Topic.
    (?# (1- most-positive-fixnum))
    ;; Comment.
    (?% (save-excursion
          (forward-same-syntax)
          (- (current-column) 2)))
    ;; Rule-head.
    (t most-positive-fixnum)))

;;;; Paragraphs

(defun dialog--forward-same-comment-style (forward-arg)
  "Move forwards through comments with the same comment style.

FORWARD-ARG is the argument for `forward-line'.  Don't move from the
current line if there is no comment on it or if there is other syntax in
front of the comment syntax."
  (end-of-line)
  (when-let* ((start (dialog--start-of-comment-or-string)))
    (goto-char start)
    (when (= (current-column) (current-indentation))
      (let ((target-regexp (rx (literal (buffer-substring-no-properties
                                         (point)
                                         (progn
                                           (forward-same-syntax)
                                           (point))))
                               (not ?%)))
            (target-indentation (current-indentation)))
        (while (and (save-excursion
                      (and (zerop (forward-line forward-arg))
                           (= (current-indentation) target-indentation)
                           (progn
                             (back-to-indentation)
                             (looking-at-p target-regexp))))
                    (forward-line forward-arg)))))))

(defconst dialog-paragraph-delimiter-regexp
  (rx (opt (syntax ?')) (or ?\( ?\[ ?\{))
  "The default regular expression used to identify paragraph delimiters.")

(defcustom dialog-paragraph-delimiter dialog-paragraph-delimiter-regexp
  "Configure an additional method for delimiting paragraphs.

This directly configures the behavior of `dialog-forward-paragraph'
which will indirectly determine the behavior of commands like
`fill-paragraph'.  Regular expression matches and function calls are
made at the indentation column."
  :type '(choice (const :tag "No additional delimiter" nil)
                 (const :tag "One paragraph per non-comment line" t)
                 (const :tag "Syntax start" dialog-paragraph-delimiter-regexp)
                 (string :tag "Custom regular expression")
                 (function :tag "Custom function")))

(defun dialog--paragraph-delimiter-p ()
  "Return whether the current line should delimit a paragraph."
  (pcase dialog-paragraph-delimiter
    ((and (pred functionp) fn)
     (save-excursion
       (back-to-indentation)
       (funcall fn)))
    ((and (pred stringp) regexp)
     (save-excursion
       (back-to-indentation)
       (looking-at-p regexp)))
    (delimit
     delimit)))

(defun dialog-forward-paragraph (&optional arg)
  "Move forward to the end of the paragraph.

With argument ARG, do it ARG times.  Move backwards when ARG is a
negative value.  If a limit is reached, return the number of paragraphs
left to move."
  (interactive "p")
  (unless arg (setq arg 1))
  (let* ((forwards (cl-plusp arg))
         (dec-fn (if forwards #'1- #'1+))
         (forward-arg (if forwards 1 -1))
         (line-edge-fn (if forwards #'end-of-line #'back-to-indentation))
         (re-search-fn (if forwards #'re-search-forward #'re-search-backward)))
    (cl-loop
     named arg-loop
     while (not (zerop arg))
     do (cl-loop
         with target-indentation
         initially
         ;; Try to move out of the current paragraph to find the next paragraph,
         ;; and then try to move through comments with the same style.
         (funcall re-search-fn (rx graphic) nil t)
         (dialog--forward-same-comment-style forward-arg)
         ;; Test the line for a trailing comment or a paragraph delimiter.
         (when (or (dialog--line-has-comment-p)
                   (dialog--paragraph-delimiter-p))
           (setq arg (funcall dec-fn arg))
           (cl-return))
         ;; Set the indentation level to search for.
         (setq target-indentation (current-indentation))
         ;; Move 1 line.  Exit the outer loop at buffer limit.
         unless (zerop (forward-line forward-arg))
         do (cl-return-from arg-loop)
         ;; Test the line for an indentation change, no indentation, emptiness,
         ;; a trailing comment, or a paragraph delimiter.
         when (or (/= (current-indentation) target-indentation)
                  (zerop (current-indentation))
                  (dialog--empty-line-p)
                  (dialog--line-has-comment-p)
                  (dialog--paragraph-delimiter-p))
         do (progn
              ;; Go back to the last line which is in the paragraph.
              (forward-line (- forward-arg))
              (setq arg (funcall dec-fn arg))
              (cl-return)))
     do (funcall line-edge-fn)))
  arg)

(defun dialog-backward-paragraph (&optional arg)
  "Move backwards to the end of the current paragraph ARG times.

Behavior is as described for `dialog-forward-paragraph' when called with
a negative argument."
  (interactive "p")
  (unless arg (setq arg 1))
  (dialog-forward-paragraph (- arg)))

;;;; Trace output

(defcustom dialog-trace-display-buffer-action
  '((display-buffer-reuse-window display-buffer-in-previous-window)
    (inhibit-same-window . t)
    (inhibit-switch-frame . t)
    (reusable-frames . visible))
  "The display action used when displaying file from trace output."
  :type display-buffer--action-custom-type
  :risky t)

(defun dialog-trace--display-file-line (file line)
  "Display a buffer for FILE and move point to line number LINE."
  (when-let* ((buffer (find-file-noselect file))
              (window (display-buffer
                       buffer dialog-trace-display-buffer-action)))
    (with-selected-window window
      (save-restriction
        (widen)
        (goto-char (point-min))
        (forward-line (1- line))))))

(defcustom dialog-trace-pop-to-buffer-action
  '((display-buffer-reuse-window display-buffer-in-previous-window)
    (inhibit-same-window . t))
  "The display action used when switching to a file from trace output."
  :type display-buffer--action-custom-type
  :risky t)

(defun dialog-trace--pop-to-file-line (file line)
  "Pop to a buffer for FILE and move point to line number LINE."
  (when-let* ((buffer (find-file-noselect file)))
    (when (pop-to-buffer buffer dialog-trace-pop-to-buffer-action)
      (save-restriction
        (widen)
        (goto-char (point-min))
        (forward-line (1- line))))))

(defun dialog-trace--file-and-line-ref ()
  "Return the file and line reference for the current trace output line."
  (save-excursion
    (beginning-of-line)
    (get-text-property (point) 'dialog-trace-file)))

(defcustom dialog-trace-display-file-ref-hook nil
  "A hook which is run after displaying a trace file reference."
  :type 'hook)

(defun dialog-trace-display-file-ref ()
  "Display the buffer of the file referenced in the current trace line."
  (interactive)
  (pcase (dialog-trace--file-and-line-ref)
    (`(,file . ,line)
     (dialog-trace--display-file-line file line)
     (run-hooks 'dialog-trace-display-file-ref-hook))
    (_
     (user-error "No file reference on this line"))))

(defcustom dialog-trace-pop-to-file-ref-hook nil
  "A hook which is run after popping to a trace file reference."
  :type 'hook)

(defun dialog-trace-pop-to-file-ref ()
  "Pop to the buffer of the file referenced in the current trace line."
  (interactive)
  (pcase (dialog-trace--file-and-line-ref)
    (`(,file . ,line)
     (dialog-trace--pop-to-file-line file line)
     (run-hooks 'dialog-trace-pop-to-file-ref-hook))
    (_
     (user-error "No file reference on this line"))))

(defun dialog-trace-mouse-click (event)
  "Handle mouse click EVENT on a trace line."
  (interactive "e")
  (pcase (save-excursion
           (posn-set-point (event-end event))
           (dialog-trace--file-and-line-ref))
    (`(,file . ,line)
     (dialog-trace--pop-to-file-line file line)
     (run-hooks 'dialog-trace-pop-to-file-ref-hook))
    (_
     (user-error "No file reference at this click position"))))

(defvar dialog-trace-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'dialog-trace-pop-to-file-ref)
    (define-key map (kbd "f") #'dialog-trace-follow-mode)
    (define-key map (kbd "n") #'dialog-trace-forward)
    (define-key map (kbd "o") #'dialog-trace-display-file-ref)
    (define-key map (kbd "p") #'dialog-trace-backward)
    (define-key map [mouse-2] #'dialog-trace-mouse-click)
    map))

(defvar-local dialog-trace-file-regexp nil
  "The regular expression to match a trace line with a file reference.")

(defun dialog-trace--propertize (beg end)
  "Process trace output between BEG and END to add text-properties."
  (goto-char end)
  (setq end (line-end-position))
  (goto-char beg)
  (beginning-of-line)
  (setq beg (point))
  (with-silent-modifications
    (while (re-search-forward
            (rx line-start (group (1+ "| ")) (1+ not-newline) line-end) end t)
      ;; Propertize the call depth indicators.
      (add-text-properties
       (match-beginning 1)
       (match-end 1)
       '( font-lock-face font-lock-comment-face))
      ;; Propertize the entire line.
      (add-text-properties
       (line-beginning-position)
       (point)
       `( cursor-face underline
          dialog-trace-line t
          keymap ,dialog-trace-map))
      ;; Propertize the file and line reference, if present.
      (save-excursion
        (beginning-of-line)
        (when (looking-at dialog-trace-file-regexp)
          ;; Make a button.
          (add-text-properties
           (match-beginning 1)
           (match-end 2)
           `( follow-link t
              font-lock-face font-lock-comment-face
              help-echo "mouse-2: visit this file in other window"
              mouse-face highlight))
          ;; Store the file and line number.
          (add-text-properties
           (point)
           (line-end-position)
           `( dialog-trace-file ,(cons (match-string-no-properties 1)
                                       (string-to-number
                                        (match-string-no-properties 2)))))))))
  `(jit-lock-bounds ,beg . ,end))

(defun dialog-trace--unpropertize ()
  "Remove trace-mode related text-properties from trace output."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (with-silent-modifications
        (cl-loop
         for prop-match = (text-property-search-forward 'dialog-trace-line)
         while prop-match
         do (remove-text-properties
             (prop-match-beginning prop-match)
             (prop-match-end prop-match)
             ;; There is an assumption here that all property-names being
             ;; removed haven't been modified by or originally belonged to
             ;; functionality from unrelated modes.
             '( cursor-face nil
                dialog-trace-file nil
                dialog-trace-line nil
                font-lock-face nil
                help-echo nil
                keymap nil
                mouse-face nil)))))))

;;;###autoload
(define-minor-mode dialog-trace-mode
  "Propertize and enable keymaps for Dialog trace output."
  :interactive t
  (cond (dialog-trace-mode
         (setq dialog-trace-file-regexp
               (rx-to-string '(seq
                               line-start
                               ?|
                               (1+ not-newline)
                               " "
                               (group (eval (cons 'or dialog-game-files)))
                               ?:
                               (group (1+ numeric))
                               line-end)
                             'no-group))
         (jit-lock-register #'dialog-trace--propertize)
         ;; Run now on the entire buffer, otherwise text-property searches are
         ;; limited to the visible portion of the buffer.
         (jit-lock-fontify-now))
        (t
         (jit-lock-unregister #'dialog-trace--propertize)
         (dialog-trace--unpropertize))))

(defcustom dialog-trace-follow-restore-window-configuration nil
  "Specifies how `dialog-trace-follow-mode' handles window configuration.

When the value is non-nil the window configuration at the time
`dialog-trace-follow-mode' is enabled will be restored when the mode is
disabled."
  :type 'boolean
  :safe #'booleanp)

(defvar-local dialog-trace-follow-window-configuration nil
  "The window configuration to be restored by `dialog-trace-follow-mode'.")

;;;###autoload
(define-minor-mode dialog-trace-follow-mode
  "Enable automatic display of the current trace line.

This only affects navigation commands such as `dialog-trace-forward' and
`dialog-trace-backward' rather than any command which moves point
between lines."
  :lighter " TraceFollow"
  :interactive t
  (cond (dialog-trace-follow-mode
         ;; Enable `dialog-trace-mode' if not already enabled.
         (unless dialog-trace-mode
           (dialog-trace-mode))
         (setq dialog-trace-follow-window-configuration
               (current-window-configuration)))
        (dialog-trace-follow-restore-window-configuration
         (set-window-configuration dialog-trace-follow-window-configuration))))

(defun dialog-trace-forward (&optional arg interactive)
  "Move forwards ARG trace output lines.

When calls are INTERACTIVE and `dialog-trace-follow-mode' is enabled,
display the file which is referenced in the current trace line at the
appropriate line number."
  (interactive "p\np")
  (unless arg (setq arg 1))
  (let* ((forwards (cl-plusp arg))
         (from-line (line-number-at-pos))
         (inc-fn (if forwards #'1- #'1+))
         (search-fn (if forwards
                        #'text-property-search-forward
                      #'text-property-search-backward)))
    (while (and (not (zerop arg))
                (funcall search-fn 'dialog-trace-line t #'eq t))
      (setq arg (funcall inc-fn arg)))
    (when (and interactive dialog-trace-follow-mode)
      (unless (eq (line-number-at-pos) from-line)
        (dialog-trace-display-file-ref)))))

(defun dialog-trace-backward (&optional arg interactive)
  "Move backwards ARG trace output lines.

See the function `dialog-trace-forward' for a description of how
INTERACTIVE calls are handled."
  (interactive "p\np")
  (unless arg (setq arg 1))
  (dialog-trace-forward (- arg) interactive))

;;;; Xref

(defun dialog-xref--backend ()
  "Return the xref backend for Dialog Mode."
  'dialog)

(defvar-local dialog-xref--identifier-cache nil
  "Cons pair of `buffer-modified-tick' and an identifier alist.")

(defun dialog-xref--get-cache ()
  "Return the cache value from each buffer."
  (cl-loop
   with project-directory = (dialog--project-directory)
   for game-file in dialog-game-files
   for expanded-file = (expand-file-name game-file project-directory)
   for buffer = (set-buffer (find-file-noselect expanded-file 'no-warnings))
   when (derived-mode-p 'dialog-mode)
   unless (eq (buffer-modified-tick) (car dialog-xref--identifier-cache))
   do (setq
       dialog-xref--identifier-cache
       (cons (buffer-modified-tick)
             (save-excursion
               (save-restriction
                 (widen)
                 (goto-char (point-min))
                 (cl-loop
                  while (re-search-forward (dialog-rx unescaped ?\() nil t)
                  for ppss = (syntax-ppss)
                  unless (> (dialog--paren-depth ppss) 1)
                  if (dialog--in-comment-p ppss)
                  do (end-of-line)
                  else
                  collect (let* ((block (dialog--parse-block))
                                 (start (dialog-statement-position block))
                                 (end (1+ (dialog--list-end start)))
                                 (syntax-string
                                  (dialog--normalize-string
                                   (buffer-substring-no-properties start end))))
                            (goto-char end)
                            (cons syntax-string block)))))))
   collect (cons buffer (cdr dialog-xref--identifier-cache))))

(defun dialog-xref--match-string-syntax (syntax1 syntax2)
  "Match string elements in syntax lists SYNTAX1 and SYNTAX2.

Return a non-nil value when both lists are the same length and when
string elements in both lists have the same positions and are `equal'."
  (cl-do
      ((s1 syntax1 (cdr s1))
       (s2 syntax2 (cdr s2)))
      ((or (null s1) (null s2))
       (and (null s1) (null s2)))
    (when (or (stringp (car s1)) (stringp (car s2)))
      (unless (equal (car s1) (car s2))
        (cl-return)))))

(cl-defmethod xref-backend-apropos ((_backend (eql dialog)) pattern)
  "Find all references matching PATTERN."
  (cl-loop
   for (buffer . string-block) in (dialog-xref--get-cache)
   nconc (cl-loop
          for (string . block) in string-block
          when (string-match-p pattern string)
          collect (xref-make string
                             (xref-make-buffer-location
                              buffer
                              (dialog-statement-position block))))))

(defvar dialog-xref--identifier-block-filter nil
  "The function to use when filtering blocks used to generate xref results.")

(cl-defmethod xref-backend-definitions ((backend (eql dialog)) identifier)
  "Find definitions of IDENTIFIER using BACKEND."
  (let ((dialog-xref--identifier-block-filter #'dialog--rule-head-p))
    (xref-backend-references backend identifier)))

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql dialog)))
  "Return the relevant identifier at point."
  (save-excursion
    (dialog--forward-prefix-chars)
    (let (dialog-block-motion-push-mark)
      (while (cl-plusp (dialog--paren-depth))
        (dialog-up-block)))
    (and (eq (char-after) ?\()
         (looking-back (dialog-rx unescaped) (line-beginning-position))
         (pcase (dialog--parse-block-at-point)
           ((and (app dialog-statement-syntax syntax)
                 (guard syntax))
            (propertize
             (dialog--normalize-string
              (buffer-substring-no-properties (point) (1+ (dialog--list-end))))
             'dialog-position (point)
             'dialog-syntax syntax))))))

(cl-defmethod xref-backend-identifier-completion-table ((_backend (eql dialog)))
  "Return the completion table for identifiers."
  (completion-table-dynamic
   (lambda (_string)
     (cl-loop for (nil . string-block) in (dialog-xref--get-cache)
              append string-block))
   'switch-buffer))

(cl-defmethod xref-backend-references ((_backend (eql dialog)) identifier)
  "Find references of IDENTIFIER."
  (cl-loop
   with cache = (dialog-xref--get-cache)
   with properties = (text-properties-at 0 identifier)
   with id-position = (plist-get properties 'dialog-position)
   with id-syntax = (or
                     ;; Syntax-list supplied from identifier-at-point.
                     (plist-get properties 'dialog-syntax)
                     ;; Find a syntax-list in one of the cache values.
                     (cl-loop
                      for (nil . string-block) in cache
                      for block = (alist-get
                                   (dialog--normalize-string identifier)
                                   string-block
                                   nil nil #'equal)
                      when block
                      return (dialog-statement-syntax block)))
   for (buffer . string-block) in cache
   nconc (cl-loop
          for (string . block) in string-block
          for block-position = (dialog-statement-position block)
          ;; Skip the position corresponding to the identifier-at-point.
          unless (and id-position (= block-position id-position))
          ;; Only use blocks where the filter matches.
          when (pcase dialog-xref--identifier-block-filter
                 ((and (pred functionp) fn)
                  (funcall fn block))
                 (_
                  t))
          ;; Match string elements in the syntax-list.
          when (dialog-xref--match-string-syntax
                (dialog--syntax-definition block) id-syntax)
          collect (xref-make
                   string
                   (xref-make-buffer-location buffer block-position)))))

;;;; Keymap

(defvar dialog-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-b") #'dialog-debug-display-buffer)
    (define-key map (kbd "C-c C-c") #'dialog-debug-send-command)
    (define-key map (kbd "C-c C-d d") #'dialog-data-display-dynamic)
    (define-key map (kbd "C-c C-d t") #'dialog-data-display-tree)
    (define-key map (kbd "C-c C-e") #'dialog-debug-send-command-dwim)
    (define-key map (kbd "C-c C-i") #'dialog-toggle-indent)
    (define-key map (kbd "C-c C-n") #'dialog-forward-paragraph)
    (define-key map (kbd "C-c C-p") #'dialog-backward-paragraph)
    (define-key map (kbd "C-c C-u") #'dialog-up-block)
    (define-key map (kbd "C-c C-z") #'dialog-debug-run)
    map))

;;;; Menu

(defun dialog--add-to-menu ()
  "Add additional commands to the \"Dialog\" menu.

This should only be called after local variables have been loaded."
  (easy-menu-add-item
   (lookup-key (current-local-map) [menu-bar dialog])
   nil
   `("Send command from presets"
     :active (or (not dialog-debug-as-interp) (dialog-debug-process))
     ,@(cl-loop for (command . description) in dialog-debug-send-command-presets
                collect (vector
                         command
                         (let ((command command))  ; Lexical binding.
                           (lambda ()
                             (interactive)
                             (let ((dialog-debug-send-command-default command))
                               (dialog-debug-send-command))))
                         :help (or description (concat "Send " command)))))
   "Send command"))

(easy-menu-define dialog-mode-menu dialog-mode-map
  "Menu for Dialog Mode."
  '("Dialog"
    ["Start of rule" beginning-of-defun
     :help "Go to the start of the rule definition around point"]
    ["End of rule" end-of-defun
     :help "Go to the end of the rule definition around point"]
    ["Mark rule" mark-defun
     :help "Mark the rule definition around point"]
    "---"
    ["Toggle indentation" dialog-toggle-indent
     :help "Toggle the indentation on the current line"]
    "---"
    ["Jump to place" imenu
     :help "Jump to a place of significance in the buffer"]
    ["Jump to block opening" dialog-up-block
     :help "Jump to the opening of the current block"]
    ["Forward paragraph" dialog-forward-paragraph
     :help "Move forwards by one Dialog paragraph"]
    ["Backward paragraph" dialog-backward-paragraph
     :help "Move backwards by one Dialog paragraph"]
    "---"
    ["Enable the use of a pseudo-terminal" dialog-debug-toggle-use-pty
     :style toggle
     :selected dialog-debug-use-pty
     :visible dialog-debug-as-interp
     :help "Enable running the Dialog debug program using a pseudo-terminal"]
    ["Start the debug program" dialog-debug-run
     :active (not (dialog-debug-process))
     :help "Start the Dialog debug program"]
    ["Display debug buffer" dialog-debug-display-buffer
     :active (dialog-debug-buffer)
     :visible dialog-debug-as-interp
     :help "Display the buffer for the Dialog debug program"]
    ["Display and switch to debug buffer"
     (lambda ()
       (interactive)
       (pop-to-buffer (dialog-debug-buffer)))
     :active (dialog-debug-buffer)
     :visible dialog-debug-as-interp
     :help "Display and switch to the buffer for the Dialog debug program"]
    ["Display the current dynamic data state" dialog-data-display-dynamic
     :active (dialog-data-buffer "@dynamic")
     :visible dialog-debug-as-interp
     :help "Display the buffer for the current dynamic data state"]
    ["Display the current object tree" dialog-data-display-tree
     :active (dialog-data-buffer "@tree")
     :visible dialog-debug-as-interp
     :help "Display the buffer for the current object tree state"]
    "---"
    ["Set the default command to send" dialog-debug-set-default-command
     :help "Set the default command to send to the debug program"]
    ["Send default command" dialog-debug-send-command
     :active (or (not dialog-debug-as-interp) (dialog-debug-process))
     :help "Send the default command to the debug program"]
    ["Send current line as command" dialog-debug-send-command-from-line
     :active (or (not dialog-debug-as-interp) (dialog-debug-process))
     :help "Send the current line to the debug program"]
    ["Send region as commands" dialog-debug-send-command-from-region
     :active (and (or (not dialog-debug-as-interp) (dialog-debug-process))
                  (use-region-p))
     :help "Send the lines in the current region to the debug program"]
    ["Send command"
     (lambda ()
       (interactive)
       (dialog-debug-send-command 'prompt))
     :active (or (not dialog-debug-as-interp) (dialog-debug-process))
     :help "Send a command to the debug program"]
    "---"
    ["Browse the manual" dialog-browse-manual
     :help "Browse the Dialog manual in the default browser"]))

;;;; Syntax table

(defconst dialog-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; Set line comment start and end.
    (modify-syntax-entry ?% ". 12" table)
    (modify-syntax-entry ?\n ">" table)
    ;; Set allowed symbol constituents.
    (modify-syntax-entry ?! "_" table)
    (modify-syntax-entry ?# "_" table)
    (modify-syntax-entry ?$ "_" table)
    (modify-syntax-entry ?& "_" table)
    (modify-syntax-entry ?* "_" table)
    (modify-syntax-entry ?+ "_" table)
    (modify-syntax-entry ?- "_" table)
    (modify-syntax-entry ?/ "_" table)
    (modify-syntax-entry ?: "_" table)
    (modify-syntax-entry ?< "_" table)
    (modify-syntax-entry ?= "_" table)
    (modify-syntax-entry ?> "_" table)
    (modify-syntax-entry ?? "_" table)
    (modify-syntax-entry ?\" "_" table)
    (modify-syntax-entry ?\' "_" table)
    (modify-syntax-entry ?\; "_" table)
    (modify-syntax-entry ?^ "_" table)
    (modify-syntax-entry ?_ "_" table)
    (modify-syntax-entry ?` "_" table)
    (modify-syntax-entry ?| "_" table)
    ;; Set expression prefixes.
    (modify-syntax-entry ?@ "'" table)
    (modify-syntax-entry ?~ "'" table)
    ;; Set Escape character.
    (modify-syntax-entry ?\\ "\\" table)
    table))

(defconst dialog-syntax-propertize-function
  (syntax-propertize-rules
   ((dialog-rx unescaped (group ?*) ?\()
    (1 "'"))))

;;;; Mode

;;;###autoload
(define-derived-mode dialog-mode prog-mode "Dialog"
  "Major mode for editing Dialog files."
  (setq align-mode-rules-list dialog-align-rules-list)
  (setq imenu-create-index-function #'dialog--create-imenu-index)
  (setq-local beginning-of-defun-function #'dialog-beginning-of-defun)
  (setq-local comment-start "%% ")
  (setq-local comment-start-skip (rx "%%" (0+ (syntax ?-))))
  (setq-local end-of-defun-function #'dialog-end-of-defun)
  (setq-local fill-forward-paragraph-function #'dialog-forward-paragraph)
  (setq-local font-lock-defaults '((dialog-font-lock-keywords
                                    dialog-font-lock-keywords-1
                                    dialog-font-lock-keywords-2
                                    dialog-font-lock-keywords-3)))
  (setq-local indent-line-function #'dialog-indent-line)
  (setq-local normal-auto-fill-function #'dialog-do-auto-fill)
  (setq-local outline-level #'dialog-outline-level)
  (setq-local outline-regexp (dialog-rx outline))
  (setq-local syntax-propertize-function dialog-syntax-propertize-function)
  (add-hook 'electric-indent-functions #'dialog-electric-indent nil t)
  (add-hook 'flymake-diagnostic-functions #'dialog-flymake nil t)
  ;; Flymake is using source files rather than buffers.
  (setq-local flymake-no-changes-timeout nil)
  (add-hook 'xref-backend-functions #'dialog-xref--backend nil t)
  (add-to-list 'font-lock-extend-region-functions
               #'dialog--font-lock-extend-region-syntax-form)
  (add-hook 'hack-local-variables-hook #'dialog--add-to-menu nil t))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.dg\\'" . dialog-mode))

(provide 'dialog-mode)
;;; dialog-mode.el ends here
