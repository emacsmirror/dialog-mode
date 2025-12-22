;;; dialog-mode.el --- Major mode for editing Dialog files -*- lexical-binding: t; -*-

;; Copyright (C) 2023-2025 Morgan Willcock

;; Author: Morgan Willcock <morgan@ice9.digital>
;; Keywords: languages
;; Maintainer: Morgan Willcock <morgan@ice9.digital>
;; Package-Requires: ((emacs "28.1"))
;; URL: https://git.sr.ht/~mew/dialog-mode
;; Version: 1.0.0

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

;;; News:

;; Version 1.0.0 (????-??-??)
;; ==========================

;; Initial release.

;;; Commentary:

;; Dialog Mode is an Emacs major mode for creating and editing Dialog files.
;; The following features are implemented:

;; * Syntax-highlighting.
;; * Indentation.
;; * Motion around and selection of rule definitions.
;; * Align support for alignment of syntax following a rule-head.
;; * Imenu support for rule-heads (including topic when relevant).
;; * Outline Mode support for comments and topics.
;; * Comint support for running the Dialog debugger.
;; * Flymake support.

;; The following commands are bound in the major-mode keymap:

;;   `dialog-toggle-indent' {C-c TAB}
;;     Add or remove indentation on the current line.

;;   `dialog-toggle-indent-and-newline' {C-c RET}
;;     Add or remove indentation on the current line and then insert a newline.

;;   `dialog-up-block' {C-c C-u}
;;     Move point to the beginning of the current block.

;;   `dialog-debug-send-command' {C-c C-c}
;;     Send a command (usually "@replay") to the debug process.  There needs to
;;     already be a debug process running for this to work.  If hooks are
;;     configured to save the current buffer this is effectively a hot-reload to
;;     incorporate the latest buffer changes.

;;   `dialog-debug-run' {C-c C-z}
;;     Start the debugger as `comint' process and pop to its buffer.  If the
;;     process already exists, just pop to its buffer.

;;   `fill-paragraph' {M-q}
;;     Fill the current paragraph.  This is rebound to avoid calling
;;     `prog-fill-reindent-defun' which wouldn't have the expected effect.

;; When using `fill-paragraph' the effects are currently restricted to the
;; current line.  This restriction is in place because general text and Dialog
;; syntax are likely both present on contiguous lines of varying length at the
;; same indentation level.  To fill multiple lines, select the region first.

;; For source code which uses a double sized indent for the first level of
;; indentation, set the value of `dialog-indent-initial-size' to 2.

;; Use `align' and `align-current' to modify whitespace for vertical alignment
;; of syntax which shares the line with a rule-head.  Alignment is configured to
;; use tab-stops by default but can be customized by modifying the variable
;; `dialog-align-rules-list'.

;; Comint support will start the Dialog debugger with the game files specified
;; by the value of `dialog-game-files' which is a list of file names to use.
;; This variable is intended to be used as a directory local variable to allow
;; the file names to vary per project.  An example .dir-locals.el file might
;; look like this:

;;   ((nil . ((dialog-game-files . ("cloak.dg" "stdlib.dg")))))

;; Setting the value of `dialog-game-files' by other methods should also work.
;; Taking a guess by looking for files with a ".dg" extension as the major mode
;; is being initialized is potentially inefficient and error prone but may be
;; suitable for smaller projects where the debug process is only managed from
;; `dialog-mode' buffers:

;;   (add-hook 'dialog-mode-hook
;;             (lambda ()
;;               (unless dialog-game-files
;;                 (let ((files (directory-files
;;                               default-directory nil "\\.dg\\'"))
;;                       (stddebug "stddebug.dg")
;;                       (stdlib "stdlib.dg"))
;;                   ;; Remove the debug library from the list.
;;                   (setq files (delete stddebug files))
;;                   ;; Move the standard library to the end of the list.
;;                   (when (member stdlib files)
;;                     (setq files (append (delete stdlib files)
;;                                         (list stdlib))))
;;                   (setq dialog-game-files files)))))

;; If no game files are configured a prompt will appear to select them.  This is
;; a prompt for multiple files; the default separator for completing multiple
;; files in Emacs is a comma.

;; Note: The order of the files in the `dialog-game-files' list is significant
;; in the same way it is when compiling or manually running the debug program.

;; The game file names should be specified as relative to the current project
;; root as determined by `project'.  If the game source code is being version
;; controlled it is likely that no further configuration will be required, in
;; other cases it may be required to find another way to identify the project
;; root.  One way to do this is by using the standard library file name as
;; project root marker:

;;   (require 'project)
;;   (add-to-list 'project-vc-extra-root-markers "stdlib.dg")

;; If the project root cannot be determined the current working directory is
;; used instead.  This is likely to be less reliable and limits some
;; functionality to buffers which also happen to have the correct working
;; directory.

;; For an equivalent of hot-reload, the function `dialog-debug-send-command'
;; will default to sending "@replay" to the debug process after the default
;; value of `dialog-debug-send-command-hook' has prompted to save any modified
;; buffers.  To save the current buffer automatically or take any other custom
;; actions before the command is sent, customize the hook variable to have the
;; desired effect.

;;   ;; Automatically save the current `dialog-mode' buffer when replaying.
;;   (add-hook 'dialog-debug-send-command-hook
;;             (lambda ()
;;               (when (and (derived-mode-p 'dialog-mode)
;;                          (equal dialog-debug-send-command-input "@replay"))
;;                 (save-buffer))))

;; To make the debug process work more like it does in a terminal and support
;; the display of text styling, set the value of `dialog-debug-use-pty' to t and
;; toggle automatic dismissal of "[more]" prompts with the command
;; `dialog-debug-toggle-output-responder'.

;; To run the debug program directly instead of as a command interpreter set the
;; value `dialog-debug-as-interp' to nil.  This also defaults command sending to
;; use the clipboard.  A value of nil is the default when using Microsoft
;; Windows because the Windows build of the debugger can currently only run in a
;; graphical window and is unable to receive input outside of that interface.
;; That said, the function used to send a command is configurable and so you are
;; free to attempt to send a command to the Windows build of the debugger by
;; another method at your own risk:

;;   (defconst dialog-debug-send-ahk-script
;;     "
;;   command := EnvGet('DIALOG_DEBUG_COMMAND')
;;   SetTitleMatchMode 3  ; Exact match for window title.
;;   Try {
;;       ControlSend command '{Enter}',, 'Dialog Interactive Debugger'
;;   }
;;   Catch {
;;       Exit 1
;;   }
;;   "
;;     "The AutoHotkey send command script.")

;;   (defun dialog-debug-send-command-with-ahk ()
;;     "Send a command to the debug program window using AutoHotkey."
;;     (let ((process-environment
;;            (cons
;;             (concat "DIALOG_DEBUG_COMMAND=" dialog-debug-send-command-input)
;;             process-environment)))
;;       (message "Sending command '%s' using AutoHotkey"
;;                dialog-debug-send-command-input)
;;       (unless (eq 0 (with-temp-buffer
;;                       (insert dialog-debug-send-ahk-script)
;;                       (call-process-region (point-min) (point-max)
;;                                            "autohotkey" nil nil nil "*")))
;;         (message "Failed to send command"))))

;;   (setq dialog-debug-send-command-function
;;         #'dialog-debug-send-command-with-ahk)

;; Basic configuration:

;;   (with-eval-after-load 'dialog-mode
;;     ;; Match indentation and fill-column to the standard library.
;;     (add-hook 'dialog-mode-hook
;;               (lambda ()
;;                 (indent-tabs-mode)
;;                 (setq fill-column 79)))
;;     ;; Bind a key for easier access to Imenu.
;;     (define-key dialog-mode-map (kbd "C-c C-j") #'imenu))

;; If using Imenu or `which-function-mode' it will be beneficial to make sure
;; that the value of `imenu-auto-rescan' is set to t.

;; It may be preferable to customize the value of `font-lock-maximum-decoration'
;; to reduce the font-lock level for Dialog Mode to 2.

;;; Code:

(require 'align)
(require 'comint)
(require 'imenu)
(require 'project)
(eval-when-compile
  (require 'cl-lib)
  ;; For `when-let*' and `and-let*' in Emacs 28.
  (when (< emacs-major-version 29)
    (require 'subr-x)))

;;;; Faces

(defgroup dialog-faces nil
  "Faces used by Dialog Mode."
  :group 'dialog
  :prefix "dialog-")

(defface dialog-dictionary-word-face
  '((default :inherit font-lock-type-face))
  "Face to highlight a Dialog dictionary word.")
(defvar dialog-dictionary-word-face
  'dialog-dictionary-word-face
  "Font-lock face specification to highlight a Dialog dictionary word.")

(defface dialog-escape-sequence-face
  ;; `font-lock-escape-face' appeared in Emacs 29.
  `((default :inherit ,(if (facep 'font-lock-escape-face)
                           'font-lock-escape-face
                         'escape-glyph)))
  "Face to highlight a Dialog escape sequence.")
(defvar dialog-escape-sequence-face
  'dialog-escape-sequence-face
  "Font-lock face specification to highlight a Dialog escape sequence.")

(defface dialog-object-name-face
  '((default :inherit font-lock-constant-face))
  "Face to highlight a Dialog object name.")
(defvar dialog-object-name-face
  'dialog-object-name-face
  "Font-lock face specification to highlight a Dialog object name.")

(defface dialog-special-block-face
  '((default :inherit font-lock-keyword-face))
  "Face to highlight a Dialog special block.")
(defvar dialog-special-block-face
  'dialog-special-block-face
  "Font-lock face specification to highlight Dialog special block syntax.")

(defface dialog-special-character-face
  '((default :inherit font-lock-builtin-face))
  "Face to highlight a Dialog special character.")
(defvar dialog-special-character-face
  'dialog-special-character-face
  "Font-lock face specification to highlight a Dialog special character.")

(defface dialog-topic-name-face
  '((default :inherit font-lock-preprocessor-face))
  "Face to highlight a Dialog topic name.")
(defvar dialog-topic-name-face
  'dialog-topic-name-face
  "Font-lock face specification to highlight a Dialog topic name.")

(defface dialog-variable-name-face
  '((default :inherit font-lock-variable-name-face))
  "Face to highlight a Dialog variable name.")
(defvar dialog-variable-name-face
  'dialog-variable-name-face
  "Font-lock face specification to highlight a Dialog variable name.")

;;;; Customization

(defgroup dialog nil
  "Major mode for editing Dialog files."
  :tag "Dialog"
  :link '(emacs-commentary-link "dialog-mode")
  :group 'languages
  :prefix "dialog-")

;;;; Syntax table

(defconst dialog-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; Set line comment start and end.
    (modify-syntax-entry ?% ". 124" table)
    (modify-syntax-entry ?\n ">" table)
    ;; Set allowed symbol constituents.
    (modify-syntax-entry ?! "_" table)
    (modify-syntax-entry ?$ "_" table)
    (modify-syntax-entry ?& "_" table)
    (modify-syntax-entry ?' "_" table)
    (modify-syntax-entry ?+ "_" table)
    (modify-syntax-entry ?- "_" table)
    (modify-syntax-entry ?/ "_" table)
    (modify-syntax-entry ?: "_" table)
    (modify-syntax-entry ?< "_" table)
    (modify-syntax-entry ?= "_" table)
    (modify-syntax-entry ?> "_" table)
    (modify-syntax-entry ?? "_" table)
    (modify-syntax-entry ?\; "_" table)
    (modify-syntax-entry ?^ "_" table)
    (modify-syntax-entry ?_ "_" table)
    (modify-syntax-entry ?` "_" table)
    (modify-syntax-entry ?| "_" table)
    ;; Set expression prefixes.
    (modify-syntax-entry ?# "'" table)
    (modify-syntax-entry ?* "'" table)
    (modify-syntax-entry ?@ "'" table)
    (modify-syntax-entry ?~ "'" table)
    ;; Set Escape character.
    (modify-syntax-entry ?\\ "\\" table)
    table))

(defconst dialog-mode-parse-syntax-table
  (let ((table (make-syntax-table dialog-mode-syntax-table)))
    (modify-syntax-entry ?* "w" table)
    table))

;;;; Search patterns

(defmacro dialog-rx (&rest regexps)
  "Extended version of `rx' for translation of form REGEXPS."
  `(rx-let ((block-syntax
             (seq (or line-start (not ?\\))
                  ?\(
                  (group
                   (or "or"
                       "if" "then" "elseif" "then" "else" "endif"
                       "select" "stopping" "cycling" "at random"
                       "purely at random" "then at random"
                       "then purely at random"
                       "accumulate" "collect" "into"
                       "determine object" "from words" "matching all of"))))
            (dictionary-word
             (seq ?@ (or (1+ (char alphanumeric ?-))
                         (seq ?\\ (char ?b ?d ?l ?n ?r ?s ?u)))))
            (escape-sequence
             (seq ?\\ (char ?# ?$ ?* ?@ ?\[ ?\( ?\) ?\\ ?\] ?{ ?| ?} ?~)))
            (object
             (seq ?# (0+ user-chars)))
            (outline
             (seq line-start (or topic
                                 (seq (>= 3 ?%)
                                      (1+ whitespace)
                                      (0+ not-newline)))))
            (rule-head-line
             (seq rule-head-start (1+ not-newline)))
            (rule-head-start
             (seq line-start (optional (or ?@ ?~)) ?\())
            (special-character
             (char ?# ?$ ?@ ?~ ?* ?|))
            (topic
             (seq line-start ?# (group (1+ user-chars))))
            (user-chars
             (or (char alphanumeric)
                 (char ?! ?% ?: ?< ?> ?_ ?`)))
            (variable
             (seq ?$ (0+ user-chars))))
     (rx ,@regexps)))

;;;; Font lock

(defconst dialog-font-lock-keywords-1
  `((,(dialog-rx topic) . dialog-topic-name-face))
  "Font lock keywords for level 1 highlighting in Dialog mode.

Highlights Dialog topics.")

(defconst dialog-font-lock-keywords-2
  (append
   dialog-font-lock-keywords-1
   `((,(dialog-rx object)            . dialog-object-name-face)
     (,(dialog-rx dictionary-word)   . dialog-dictionary-word-face)
     (,(dialog-rx variable)          . dialog-variable-name-face)
     (,(dialog-rx escape-sequence)   . dialog-escape-sequence-face)
     (,(dialog-rx special-character) . dialog-special-character-face)))
  "Font lock keywords for level 2 highlighting in Dialog mode.

Highlights escape sequences, special characters, and user defined names
for dictionary words, objects, and variables.")

(defconst dialog-font-lock-keywords-3
  (append
   dialog-font-lock-keywords-2
   `((,(dialog-rx block-syntax) (1 dialog-special-block-face))))
  "Font lock keywords for level 3 highlighting in Dialog mode.

Highlights selected Dialog special syntax, escape sequences, special
characters, and user defined names for dictionary words, objects, and
variables.")

(defvar dialog-font-lock-keywords dialog-font-lock-keywords-2
  "Default expressions to highlight in Dialog mode.")

;;;; Utility

(defun dialog--paren-depth (&optional ppss)
  "Return the current parentheses depth.

Prefer existing parser state PPSS over calling `syntax-ppss'."
  (car (or ppss (syntax-ppss))))

(defun dialog--start-of-comment-or-string (&optional ppss)
  "Return the starting position of the comment or string at point.

Return nil when point is outside of a comment or string.  Prefer
existing parser state PPSS over calling `syntax-ppss'."
  (nth 8 (or ppss (syntax-ppss))))

(defalias 'dialog--in-comment-or-string-p #'dialog--start-of-comment-or-string
  "Return a non-nil value when inside a comment or string.")

(defun dialog--project-directory ()
  "Return the current project directory or the current directory."
  (if-let* ((project (project-current)))
      (project-root project)
    default-directory))

(defun dialog--rule-uses-topic-p ()
  "Return a non-nil value when the rule at point uses a topic."
  (save-excursion
    (when (or
           ;; Move out of a comment or string.
           (and-let* ((start (dialog--start-of-comment-or-string)))
             (goto-char start))
           ;; Check if already looking at a rule-head.
           (not (looking-at-p (dialog-rx rule-head-start))))
      (dialog-beginning-of-defun))
    ;; Search for an unescaped * in rule-head or body.
    (let ((bound (save-excursion
                   (dialog-end-of-defun)
                   (point))))
      (cl-loop while (re-search-forward (rx (not ?\\) (0+ ?\\ ?\\) ?*) bound t)
               for ppss = (syntax-ppss)
               unless (dialog--in-comment-or-string-p ppss)
               when (cl-plusp (dialog--paren-depth ppss))
               return t))))

;;;; Special statement parser

(cl-defstruct (dialog-block
               (:constructor dialog-make-block
                             (&key
                              position
                              prefix-char
                              statement-type))
               (:copier nil))
  "`position' records the buffer position which begins the dialog
statement.

`prefix-char' is the optional prefix character which can appear before
opening parentheses or braces, or nil when a prefix character was not
present.

`statement-type' is a character which represents the statement, either
\"{\", \"[\", or \"(\"."
  position
  prefix-char
  statement-type)

(cl-defstruct (dialog-special
               (:include dialog-block)
               (:constructor dialog-make-special
                             (&key
                              position
                              prefix-char
                              statement-list
                              &aux
                              (statement-type ?\()
                              (statement-symbol
                               (dialog--statement-token statement-list))))
               (:copier nil))
  "`statement-list' is a list which represents the parsed top-levels of a
statement.

`statement-symbol' is the symbol which represents the value of statement
when resolved to a syntax token."
  statement-list
  statement-symbol)

(cl-defgeneric dialog--opens-indent-p (block)
  "Return whether BLOCK increases the indentation level.")

(cl-defmethod dialog--opens-indent-p ((block dialog-special))
  "Return whether BLOCK increases the indentation level."
  (memq (dialog-special-statement-symbol block)
        '(dialog-if-t
          dialog-then-t
          dialog-elseif-t
          dialog-else-t
          dialog-select-t
          dialog-accumulate-t
          dialog-collect-t
          dialog-determine-t
          dialog-from-t)))

(cl-defgeneric dialog--closes-indent-p (block)
  "Return whether BLOCK decreases the indentation level.")

(cl-defmethod dialog--closes-indent-p ((block dialog-special))
  "Return whether BLOCK decreases the indentation level."
  (memq (dialog-special-statement-symbol block)
        '(dialog-then-t
          dialog-elseif-t
          dialog-else-t
          dialog-endif-t
          dialog-stopping-t
          dialog-cycling-t
          dialog-at-random-t
          dialog-into-t
          dialog-from-t
          dialog-matching-t)))

(defun dialog--rule-head-p (block)
  "Return whether BLOCK is a rule-head."
  (save-excursion
    (goto-char (dialog-block-position block))
    (dialog--backward-prefix-char)
    (zerop (current-column))))

(defun dialog--backward-prefix-char ()
  "Return the prefix character before point and move past it.

If no prefix character is present, do nothing and return nil."
  (and-let* ((char (char-before)))
    (and (char-equal (char-syntax char) ?')
         (progn (forward-char -1) t)
         char)))

(defun dialog--forward-prefix-char ()
  "Return the prefix character after point and move past it.

If no prefix character is present, do nothing and return nil."
  (and-let* ((char (char-after)))
    (and (char-equal (char-syntax char) ?')
         (progn (forward-char) t)
         char)))

(defun dialog--parse-special-statement-list ()
  "Parse the inner contents of a special statement list.

Assume that point is on unescaped opening parenthesis and outside of a
comment."
  (let ((parse-sexp-ignore-comments t)
        statement)
    (with-syntax-table dialog-mode-parse-syntax-table
      (and-let* ((statement-end (condition-case nil
                                    (scan-sexps (point) 1)
                                  (scan-error))))
        (cl-decf statement-end)
        (forward-char)
        (while (progn
                 (comment-forward (point-max))
                 (< (point) statement-end))
          (push (cl-case (char-after)
                  (?#  (forward-sexp) 'object)
                  (?$  (forward-sexp) 'variable)
                  (?@  (forward-sexp) 'word)
                  (?\( (forward-sexp) 'statement)
                  (?\[ (forward-sexp) 'list)
                  (t   (buffer-substring-no-properties
                        (point)
                        (progn (forward-sexp) (point)))))
                statement))
        (nreverse statement)))))

(defun dialog--statement-token (statement)
  "Return the symbol representing the statement list STATEMENT."
  (pcase statement
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

(defun dialog--parse-statement (list-start &optional skip-prefix)
  "Return a struct which represents the statement at point.

The mandatory argument LIST-START is the opening position of a list when
point is within list or nil otherwise.  SKIP-PREFIX should be a non-nil
value when point needs to skip a prefix character to find the beginning
of the statement."
  (when skip-prefix
    (dialog--forward-prefix-char))
  (cond ((and (not (bobp))
              (char-equal ?\\ (char-syntax (char-before))))
         ;; Skip for escape sequence.
         nil)
        ((dialog--in-comment-or-string-p)
         ;; Skip for comments and strings.
         nil)
        ((eq (point) list-start)
         ;; Inside a statement.  Return a struct which just represents the
         ;; statement opening.
         (dialog-make-block
          :position (point)
          :statement-type (char-after)
          :prefix-char (dialog--backward-prefix-char)))
        ((eq (char-after) ?\()
         ;; At top level.  Return a struct which represents the statement.
         (dialog-make-special
          :position (point)
          :prefix-char (save-excursion
                         (dialog--backward-prefix-char))
          :statement-list (save-excursion
                            (dialog--parse-special-statement-list))))))

(defun dialog--parse-dominating-block ()
  "Scan backwards and return the dominant block state.

A dominant block is one which opens a new indentatation level without
closing the previous indentation level.  In practical terms this means
prefering the opening \"(if)\" of an If statement over
\"(else)\",\"(elseif)\", or \"(then)\" blocks."
  (let* ((block (dialog--parse-block))
         (parent block))
    (while (and (dialog-special-p parent)
                (memq (dialog-special-statement-symbol parent)
                      '(dialog-else-t dialog-elseif-t dialog-then-t))
                (not (dialog--rule-head-p parent))
                (setq parent (save-excursion
                               (goto-char (dialog-special-position parent))
                               (dialog--parse-block)))))
    (or parent block)))

(defun dialog--parse-block ()
  "Scan backwards and return the current block state."
  (save-excursion
    (let ((list-start (nth 1 (syntax-ppss)))
          block
          block-end)
      (while (and (null block)
                  (re-search-backward (rx (char ?\( ?\[ ?{)) nil t))
        (when-let* ((statement (dialog--parse-statement list-start)))
          (cond ((looking-at-p (rx ?{ graphic)))  ; Ignore "tight bracing".
                ((not (dialog-special-p statement))
                 ;; Bump against list opening.
                 (when (eq (dialog-block-position statement) list-start)
                   (setq block statement)))
                ((dialog--rule-head-p statement)
                 (setq block statement))
                ((dialog--opens-indent-p statement)
                 (pcase (cons (dialog-special-statement-symbol statement)
                              (car block-end))
                   (`(,_ . nil)
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
                ((dialog--closes-indent-p statement)
                 (push (dialog-special-statement-symbol statement)
                       block-end)))))
      block)))

;;;; Motion

(defcustom dialog-block-motion-push-mark t
  "Specifies whether block motion will push to the `mark-ring'.

A non-nil value indicates that block motion commands are permitted to
push the previous location to the `mark-ring' when the value of point
changes."
  :type 'boolean)

(defun dialog-up-block ()
  "Move point to the opening of the current block."
  (interactive)
  (let ((from (point)))
    (goto-char (dialog-block-position (dialog--parse-block)))
    (unless (or (null dialog-block-motion-push-mark)
                (region-active-p)
                (eq from (point)))
      (push-mark from))))

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
                  (or (dialog--in-comment-or-string-p)
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

(defun dialog--dedicated-line-p (block line)
  "Return whether LINE in BLOCK is a dedicated line."
  (and (or
        ;; Inside a braced expression.
        (eq (dialog-block-statement-type block) ?{)
        ;; Inside a block defined by a special statement (non-nil token).
        (and (dialog-special-p block)
             (dialog-special-statement-symbol block)))
       ;; Match "(or)".
       (and (dialog-special-p line)
            (equal (dialog-special-statement-list line) '("or")))
       ;; Check there is nothing else preceding it on the same line.
       (> (save-excursion
            (goto-char (dialog-block-position line))
            (line-beginning-position))
          (save-excursion
            (goto-char (dialog-block-position line))
            (forward-comment (- (point)))
            (point)))
       ;; Check there is nothing else following it on the same line.
       (< (save-excursion
            (goto-char (dialog-block-position line))
            (line-end-position))
          (save-excursion
            (goto-char (dialog-block-position line))
            (forward-sexp)  ; Move forwards across the "(or)".
            (forward-comment (point-max))
            (point)))))

(defcustom dialog-indent-offset 8
  "Specifies the indentation offset applied by `dialog-indent-line'.

Lines determined to be within blocks are indented by this number of
columns per block level."
  :type 'integer)

(defcustom dialog-indent-in-statement (list ?\( ?\[ ?{)
  "Specifies which statement types have additional indentation applied.

Statement types which match will have the indentation level of a
multi-line body increased."
  :type '(repeat character))

(defcustom dialog-indent-initial-size 1
  "Specifies a multiplier used for the first level of indentation.

Increasing this to 2 will give a double sized indent for the first level
of indentation but a normally sized indent for subsequent levels."
  :type 'integer)

(defun dialog--new-indent ()
  "Return the calculated indentation level for the current line."
  (save-excursion
    (let ((list-start (prog1
                          (nth 1 (syntax-ppss))
                        (back-to-indentation)))
          (block-statement (dialog--parse-dominating-block)))
      (if (not (dialog-block-p block-statement))
          ;; If there is no block then this is the first statement in the file.
          0
        ;; Calculate new level.
        (let ((line-sticky (and (zerop (current-column))
                                (/= (line-end-position) (point))))
              (line-statement (dialog--parse-statement list-start t))
              (new-level 0))
          ;; Remove one level of indentation when the current line begins by
          ;; closing one parenthesis level.
          (when (memq (alist-get (char-after) '((?\) . ?\()
                                                (?\] . ?\[)
                                                (?}  . ?{)))
                      dialog-indent-in-statement)
            (cl-decf new-level))
          ;; Move to the position where the current block was opened.
          (goto-char (dialog-block-position block-statement))
          (dialog--backward-prefix-char)
          (cond ((zerop (current-column))
                 ;; Increase indentation when the block opening is a rule-head,
                 ;; unless the line being indented starts in column zero and is
                 ;; not empty.
                 (unless line-sticky
                   (cl-incf new-level dialog-indent-initial-size)))
                ((not (dialog-special-p block-statement))
                 ;; Increase indentation inside a statement.
                 (when (memq (dialog-block-statement-type block-statement)
                             dialog-indent-in-statement)
                   (cl-incf new-level)))
                ((pcase (cons (dialog-special-statement-symbol block-statement)
                              (and (dialog-special-p line-statement)
                                   (dialog-special-statement-symbol line-statement)))
                   ;; Avoid further pattern matches if there is no block open.
                   (`(nil . ,_))
                   ;; Avoid further pattern matches for a block open without a
                   ;; block close.
                   (`(,_ . nil) t)
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
                   (_ t))
                 ;; Add indentation based on matching block tokens.
                 (cl-incf new-level)))
          ;; Decrement indentation for special statements which are on their
          ;; own line.
          (when (and (dialog--dedicated-line-p block-statement line-statement)
                     (cl-plusp new-level))
            (cl-decf new-level))
          (max (+ (current-indentation) (* new-level dialog-indent-offset))
               0))))))

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
    (back-to-indentation)
    (let ((end (point)))
      (cond ((zerop (skip-chars-backward " \t"))
             (tab-to-tab-stop)
             (funcall indent-line-function))
            (t
             (delete-region (point) end)))))
  ;; Move to the current indentation column when inside indentation.
  (when (<= (current-column) (current-indentation))
    (back-to-indentation)))

(defun dialog-toggle-indent-and-newline (arg interactive)
  "Toggle indentation for the current line and insert a newline.

The `newline' function is called interactively with ARG and INTERACTIVE
after toggling indentation and moving point to the end of the line."
  (interactive "*P\np")  ; Matched to interactive spec for `newline'.
  (dialog-toggle-indent)
  (end-of-line)
  (funcall-interactively #'newline arg interactive))

;;;; Align

(defcustom dialog-align-rules-list
  `((dialog-assignment
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
         (search-func (if forwards #'re-search-forward #'re-search-backward))
         found new-pos)
    (save-excursion
      (while (and (funcall search-func (dialog-rx rule-head-start) bound t)
                  (or (dialog--in-comment-or-string-p)
                      (not (setq found t)))))
      (when found
        ;; Move to the opening "(".
        (beginning-of-line)
        (dialog--forward-prefix-char)
        ;; Move across the sexp and look for a whitespace separator.
        (condition-case nil
            (progn
              (forward-sexp)
              (and (re-search-forward
                    (rx (group (0+ whitespace))) (line-end-position) t)
                   (setq new-pos (if forwards
                                     ;; Already at the end of the match.
                                     (point)
                                   ;; Move as if searching backwards.
                                   (line-beginning-position)))))
          (scan-error))))
    (and new-pos (goto-char new-pos))))

(defun dialog-align-rule-match-valid-p ()
  "Validate the current alignment rule.

Ignore matches where the match ends at the end of the line.  This
prevents whitespace adjustments being made for lines which have no
trailing syntax while still allowing the alignment to work across a
region which contains such lines."
  (/= (match-end 0) (line-end-position)))

(add-to-list 'align-dq-string-modes 'dialog-mode)
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

(defcustom dialog-debug-program "dgdebug"
  "Specifies the name of the Dialog debugger executable."
  :type 'string)

(defcustom dialog-debug-as-interp (not (eq system-type 'windows-nt))
  "Specifies whether the debug program runs as a command interpreter.

A non-nil value will start the debug program using `comint' which
enables interactive debugging and sending commands to the game as it is
running.  A value of nil means that the process is launched directly
with no further process control."
  :type 'boolean)

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
started in a `dialog-debug-mode' buffer.  An existing buffer will be
re-used if its name matches `dialog-debug-buffer-name'; to support
multiple processes rename an existing buffer with \\[rename-buffer] to
allow the creation of a new one.  The currently used buffer will be
displayed if it exists."
  (interactive "P")
  (let ((buffer (and dialog-debug-as-interp
                     (or (get-buffer dialog-debug-buffer-name)
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

;;;###autoload
(defalias 'run-dialog #'dialog-debug-run)

(defcustom dialog-debug-send-default-command "@replay"
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

(defvar dialog-debug-send-command-input nil
  "The current command which is being sent to the debug process.")

(defvar dialog-debug-send-history nil
  "History of minibuffer input for `dialog-debug-send-command'.")

(defun dialog-debug-send-command (&optional prompt)
  "Send a command to the debug program.

The default command to send is determined by the value of
`dialog-debug-send-default-command'.  With a prefix argument PROMPT,
prompt for the command to send instead of using the default."
  (interactive "P")
  (setq dialog-debug-send-command-input
        (if prompt
            (read-from-minibuffer
             "Command: " nil nil nil 'dialog-debug-send-history)
          dialog-debug-send-default-command))
  (run-hooks 'dialog-debug-send-command-hook)
  (funcall dialog-debug-send-command-function))

(defun dialog-debug-send-command-with-clipboard ()
  "Save a command to the clipboard."
  (gui-set-selection 'CLIPBOARD dialog-debug-send-command-input)
  (message "Command '%s' saved to clipboard" dialog-debug-send-command-input))

(defun dialog-debug-send-command-with-comint ()
  "Send a command to the debug process in the comint buffer."
  (when-let* ((process (or (get-buffer-process dialog-debug-buffer-name)
                           (user-error "No debug process is running"))))
    (message "Sending command '%s' to process '%s'"
             dialog-debug-send-command-input (process-name process))
    (comint-simple-send process dialog-debug-send-command-input)))

(defvar dialog-debug-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-z") #'quit-window)
    (set-keymap-parent map comint-mode-map)
    map))

(defcustom dialog-debug-use-output-responder t
  "Specifies whether the output filter should send responses.

Sending responses is only relevant when the debug process is using a Pty
and `dialog-debug-output-responder' has been added to the value
`comint-output-filter-functions'.  See `dialog-debug-use-pty'."
  :type 'boolean)

(defun dialog-debug-toggle-output-responder ()
  "Toggle the value of `dialog-debug-use-output-responder'."
  (interactive)
  (setq dialog-debug-use-output-responder
        (not dialog-debug-use-output-responder))
  (message "Output responder is now %s" (if dialog-debug-use-output-responder
                                            "enabled"
                                          "disabled")))

(defun dialog-debug-output-responder (_string)
  "Respond to process output by sending additional input."
  (when dialog-debug-use-output-responder
    (when-let* ((process (get-buffer-process (current-buffer))))
      (save-excursion
        (goto-char (point-max))
        (pcase (buffer-substring-no-properties
                (line-beginning-position) (point))
          ("[more]" (comint-send-string process "\n")))))))

(defcustom dialog-debug-use-pty nil
  "Specifies whether the debug process uses a Pty.

A value of nil indicates to use a pipe instead of a Pty.  A value of t
indicates to use a Pty.  The debug buffer needs to be recreated for
changes to this variable to take effect.

Running the debug process in a Pty makes it work more like it would in
traditional terminal and also signals that the filter function
`dialog-debug-output-responder' should be added to the buffer local
value of `comint-output-filter-functions' for the debug buffer.  This
function allows \"[more]\" prompts to be dismissed automatically, see
`dialog-debug-toggle-output-responder'."
  :type 'boolean)

(define-derived-mode dialog-debug-mode comint-mode "DGDebug"
  "Major mode for running the Dialog interactive debugger.

\\<dialog-debug-mode-map>"
  (setq-local comint-prompt-read-only t)
  (setq-local scroll-conservatively most-positive-fixnum)
  (when (setq-local process-connection-type dialog-debug-use-pty)
    (add-hook 'comint-output-filter-functions
              #'dialog-debug-output-responder 90 t)))

;;;; Filling

(defun dialog-do-autofill ()
  "Dialog specific function for `auto-fill-mode'."
  (let ((fill-forward-paragraph-function (lambda (arg)
                                           (forward-line arg)
                                           0)))
    (do-auto-fill)))

(defun dialog-fill-paragraph (&optional justify)
  "Dialog specific function for filling paragraphs.

If JUSTIFY is non-nil, justify as well."
  (interactive "P")
  (save-excursion
    (end-of-line)
    (if (dialog--in-comment-or-string-p)
        ;; Use default fill for comments and strings.
        (fill-comment-paragraph justify)
      ;; Restrict the fill to the current line.
      ;; TODO: Find a safe way to identify a "paragraph".  It isn't obvious how
      ;; to differentiate between text and code - using the indentation level
      ;; doesn't work well in practice.
      (save-restriction
        (narrow-to-region (line-beginning-position) (point))
        (fill-paragraph justify)
        t))))

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
      (setq dialog--flymake-proc
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
                             ;; Push all diagnostics into a hash table to group
                             ;; them by filename.
                             (cl-loop
                              while (search-forward-regexp
                                     dialog-error-regexp nil t)
                              for type = (pcase (match-string 1)
                                           ("Debug"   :dialog-debug)
                                           ("Error"   :error)
                                           ("Info"    :dialog-info)
                                           ("Warning" :warning)
                                           (_         :note))
                              for filename = (match-string 2)
                              for beg = (cons
                                         (string-to-number (match-string 3)) 0)
                              for msg = (match-string 4)
                              for diag = (flymake-make-diagnostic
                                          filename beg nil type msg
                                          'dialogc)
                              do (push diag (gethash filename ht)))
                             ;; Add all but the diagnostics for the source
                             ;; buffer as list-only diagnostics.
                             (dialog--clear-flymake-diagnostics)
                             (maphash
                              (lambda (file diags)
                                (if (and source-file
                                         (file-equal-p file source-file))
                                    (setq source-diags diags)
                                  (push (cons (expand-file-name file) diags)
                                        flymake-list-only-diagnostics)))
                              ht)
                             (funcall report-fn source-diags)))
                       (flymake-log :warning "Canceling obsolete check %s"
                                    proc))
                   (kill-buffer (process-buffer proc))))))))))

;;;; Imenu

(defcustom dialog-imenu-topic-separator imenu-level-separator
  "Specifies the topic separator used for Imenu names."
  :type 'string)

(defun dialog--create-imenu-index ()
  "Build and return an Imenu index alist."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let (index topic)
        (while (re-search-forward (dialog-rx (or rule-head-start topic)) nil t)
          (cond
           ((dialog--in-comment-or-string-p))
           ((eq (char-after (match-beginning 0)) ?#)
            (setq topic (match-string-no-properties 0)))
           (t
            (end-of-line)
            ;; Move out of a comment or string.
            (when-let* ((start (dialog--start-of-comment-or-string)))
              (goto-char start))
            ;; Move backwards through whitespace.
            (forward-comment (- (point-max)))
            ;; Create the index entry.
            (let ((rule-head (buffer-substring-no-properties
                              (match-beginning 0) (point))))
              (push
               ;; Prepend the topic if there is one and the rule uses it.
               (cons (if (and topic (dialog--rule-uses-topic-p))
                         (concat topic dialog-imenu-topic-separator rule-head)
                       rule-head)
                     (if imenu-use-markers
                         (copy-marker (point) t)
                       (point)))
               index))
            ;; Don't re-match the previous match.
            (dialog-end-of-defun))))
        (nreverse index)))))

;;;; Outline mode

(defun dialog-outline-level ()
  "Return the depth for the current outline heading."
  (if (eq (char-after) ?#)
      most-positive-fixnum
    (save-excursion
      (forward-same-syntax)
      (- (current-column) 2))))

;;;; Keymap

(defvar dialog-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'dialog-debug-send-command)
    (define-key map (kbd "C-c C-i") #'dialog-toggle-indent)
    (define-key map (kbd "C-c C-m") #'dialog-toggle-indent-and-newline)
    (define-key map (kbd "C-c C-u") #'dialog-up-block)
    (define-key map (kbd "C-c C-z") #'dialog-debug-run)
    ;; Restore the previous key-binding for `fill-paragraph' since it doesn't
    ;; currently make sense to call `prog-fill-reindent-defun'.
    (define-key map (kbd "M-q") #'fill-paragraph)
    map))

;;;; Mode

;;;###autoload
(define-derived-mode dialog-mode prog-mode "Dialog"
  "Major mode for editing Dialog files."
  (setq align-mode-rules-list dialog-align-rules-list)
  (setq imenu-create-index-function #'dialog--create-imenu-index)
  (setq-local beginning-of-defun-function #'dialog-beginning-of-defun)
  (setq-local comment-start "%%")
  (setq-local end-of-defun-function #'dialog-end-of-defun)
  (setq-local fill-paragraph-function #'dialog-fill-paragraph)
  (setq-local font-lock-defaults '((dialog-font-lock-keywords
                                    dialog-font-lock-keywords-1
                                    dialog-font-lock-keywords-2
                                    dialog-font-lock-keywords-3)))
  (setq-local indent-line-function #'dialog-indent-line)
  (setq-local normal-auto-fill-function #'dialog-do-autofill)
  (setq-local outline-level #'dialog-outline-level)
  (setq-local outline-regexp (dialog-rx outline))
  (add-hook 'flymake-diagnostic-functions #'dialog-flymake nil t)
  ;; Flymake is using source files rather than buffers.
  (setq-local flymake-no-changes-timeout nil))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.dg\\'" . dialog-mode))

(provide 'dialog-mode)
;;; dialog-mode.el ends here
