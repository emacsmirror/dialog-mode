;;; dialog-mode-tests.el --- Tests for dialog-mode -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests to verify the correct operation of dialog-mode.

;;; Code:

(require 'dialog-mode)
(require 'ert)

;;; Tests

;;;; Helper macros

(defmacro dialog-mode-tests--with-temp-buffer (buffer-contents &rest body)
  "Evaluate BODY in a temporary Dialog mode buffer containing BUFFER-CONTENTS."
  (declare (indent 1))
  `(with-temp-buffer
     (dialog-mode)
     (indent-tabs-mode)
     (setq case-fold-search nil)
     (setq-local dialog-indent-initial-size 1)
     (setq-local dialog-indent-offset 8)
     (insert ,buffer-contents)
     ,@body))

(defmacro dialog-mode-tests--buffer-changes (before after &rest body)
  "Test a buffer change within a temporary Dialog mode buffer.

The string BEFORE is inserted into a temporary buffer before BODY
is evaluated.  The test succeeds if the new buffer contents are
now equal to the string AFTER."
  (declare (indent 2))
  `(dialog-mode-tests--with-temp-buffer
       ,before
     ,@body
     (should (equal (buffer-string) ,after))))

(defmacro dialog-mode-tests--test-indentation (buffer-contents)
  "Check indentation of BUFFER-CONTENTS within a temporary Dialog mode buffer."
  `(dialog-mode-tests--with-temp-buffer
       ,buffer-contents
     (let ((inhibit-message t))
       (indent-region (point-min) (point-max)))
     (should (equal (buffer-string) ,buffer-contents))))

;;;; Indentation for statements

(ert-deftest dialog-indent-topic ()
  "Do not modify indentation for topics."
  (dialog-mode-tests--test-indentation
   "(rule head)
#mytopic"))

(ert-deftest dialog-indent-comment ()
  "Do not modify indentation for comments."
  (dialog-mode-tests--test-indentation
   "(rule head)
%% My comment."))

(ert-deftest dialog-indent-rule-head-prefix-@ ()
  "Do not modify indentation for rule-head prefix @."
  (dialog-mode-tests--test-indentation
   "(rule head)
@($Obj is open)"))

(ert-deftest dialog-indent-rule-head-prefix-~ ()
  "Do not modify indentation for rule-head prefix ~."
  (dialog-mode-tests--test-indentation
   "(rule head)
~(refuse [find $])"))

(ert-deftest dialog-indent-following-rule-head ()
  "Increase indentation level for statements following rule heads."
  (dialog-mode-tests--test-indentation
   "%% Statements following rule head.
(program entry point)
	Hello, world!"))

(ert-deftest dialog-indent-tight-bracing ()
  "Maintain indentation level where bracing touches statements."
  (dialog-mode-tests--test-indentation
   "%% Tight bracing.
(perform [about])
	Please make sure to check out the (link resource @manual){printed
	manual} that was bundled with the game."))

(ert-deftest dialog-indent-tight-bracing-no-dedent ()
  "Maintain indentation level where bracing touches statements.

Do not dedent a line which begins with tight bracing."
  (dialog-mode-tests--test-indentation
   "%% Tight bracing.
(perform [about])
	Please make sure to check out the (link resource @manual){printed
	manual
	}
	that was bundled with the game."))

(ert-deftest dialog-indent-simple-disjunction ()
  "Maintain indentation level for simple disjunction."
  (dialog-mode-tests--test-indentation
   "%% Simple disjunction.
(tasty $Obj)
	(fruit $Obj)
	(or)
	($Obj = #steak) (player eats meat)"))

(ert-deftest dialog-indent-braced-disjunction ()
  "Reduce indentation level for braced disjunction."
  (dialog-mode-tests--test-indentation
   "%% Braced disjunction.
(royalty $Person)
	{
		(the mother of $Person is $Parent)
	(or)
		(the father of $Person is $Parent)
	}
	(royalty $Parent)"))

(ert-deftest dialog-indent-braced-statement ()
  "Increase indentation level within braced statements."
  (dialog-mode-tests--test-indentation
   "%% Braced statement.
(program entry point)
	(exhaust) {
		*(query { Veni (or) Vidi (or) Vici })
		!
	}"))

(ert-deftest dialog-indent-collect-into-statement ()
  "Increase indentation level within collect into statements."
  (dialog-mode-tests--test-indentation
   "%% Collect into statement.
(program entry point)
	(collect $F)
		*(fruit $F)
	(into $FruitList)
	Come and buy! $FruitList!"))

(ert-deftest dialog-indent-accumulate-into-statement ()
  "Increase indentation level within accumulate into statements."
  (dialog-mode-tests--test-indentation
   "%% Accumulate into statement.
(program entry point)
	(accumulate 1)
		*(fruit $)
	(into $Num)
	I know of $Num pieces of fruit."))

(ert-deftest dialog-indent-branch-statement ()
  "Increase indentation level for branch statements."
  (dialog-mode-tests--test-indentation
   "%% Conjunctions and disjunctions.
(eat $Obj)
	You take a large bite, and conclude that it is
	{
		{ (fruit $Obj) (or) (pastry $Obj) }
		sweet
	(or)
		($Obj = #steak) (player eats meat)
		savoury
	(or)
		inedible
	}."))

(ert-deftest dialog-indent-if-statement ()
  "Increase indentation level within if statements."
  (dialog-mode-tests--test-indentation
   "%% If statement.
(eat $Obj)
	You take a large bite, and conclude that it is
	(if) (fruit $Obj) (or) (pastry $Obj) (then)
		sweet
	(elseif) ($Obj = #steak) (player eats meat) (then)
		savoury
	(else)
		inedible
	(endif)."))

(ert-deftest dialog-indent-select-at-random-statement ()
  "Increase indentation level within select at random statements."
  (dialog-mode-tests--test-indentation
   "%% Select at random statement.
(descr #bouncer)
	The bouncer
	(select)
		eyes you suspiciously
	(or)
		hums a ditty
	(or)
		looks at his watch
	(at random)."))

(ert-deftest dialog-indent-select-stopping-statement ()
  "Increase indentation level within select stopping statements."
  (dialog-mode-tests--test-indentation
   "%% Select stopping statement.
(report)
	(select)
		This is printed the first time.
	(or)
		This is printed the second time.
	(or)
		This is printed ever after.
	(stopping)
	(line)"))

(ert-deftest dialog-indent-access-predicate ()
  "Increase indentation level within access predicate."
  (dialog-mode-tests--test-indentation
   "%% Access predicate.
@($Obj is $Rel $Parent)
	*($Obj has parent $Parent)
	*($Obj has relation $Rel)"))

;;;; Indentation for parenthesis level

(ert-deftest dialog-indent-with-parens-inline ()
  "Increase indentation level with parens sharing a line."
  (dialog-mode-tests--test-indentation
   "(1
	2
	3 (4
		5
		6))"))

(ert-deftest dialog-indent-with-parens-outline ()
  "Increase indentation level with parens on their own line."
  (dialog-mode-tests--test-indentation
   "(
	1
	2
	3
	(
		4
		5
		6
	)
)"))

(ert-deftest dialog-indent-with-inline-parens ()
  "Indentation level is not affected by inline parens."
  (dialog-mode-tests--test-indentation
   "((1
	2
	3
	((4
		5
		6))))"))

;;;; Beginning of defun

(ert-deftest dialog-beginning-of-defun-backwards ()
  "Test moving backwards to the previous rule-head."
  (dialog-mode-tests--with-temp-buffer
      "
(head1)
%% (comment)
(head2)

(head3)
"
    (beginning-of-defun)
    (should (looking-at-p "^(head3)$"))
    (beginning-of-defun)
    (should (looking-at-p "^(head2)$"))
    (beginning-of-defun)
    (should (looking-at-p "^(head1)$"))
    (beginning-of-defun)
    (should (looking-at-p "^(head1)$"))))

(ert-deftest dialog-beginning-of-defun-backwards-with-arg ()
  "Test moving backwards to the nth rule-heads."
  (dialog-mode-tests--with-temp-buffer
      "
(head1)
(head2)
(head3)
"
    (beginning-of-defun 2)
    (should (looking-at-p "^(head2)$"))
    (beginning-of-defun 2)
    (should (looking-at-p "^(head1)$"))
    (beginning-of-defun 2)
    (should (looking-at-p "^(head1)$"))))

(ert-deftest dialog-beginning-of-defun-forwards ()
  "Test moving forwards to the next rule-head."
  (dialog-mode-tests--with-temp-buffer
      "
(head1)
%% (comment)
(head2)

(head3)
"
    (goto-char (point-min))
    (beginning-of-defun -1)
    (should (looking-at-p "^(head1)$"))
    (beginning-of-defun -1)
    (should (looking-at-p "^(head2)$"))
    (beginning-of-defun -1)
    (should (looking-at-p "^(head3)$"))
    (beginning-of-defun -1)
    (should (looking-at-p "^(head3)$"))))

(ert-deftest dialog-beginning-of-defun-forwards-with-arg ()
  "Test moving forwards to the nth rule-head."
  (dialog-mode-tests--with-temp-buffer
      "
(head1)
(head2)
(head3)
"
    (goto-char (point-min))
    (beginning-of-defun -2)
    (should (looking-at-p "^(head2)$"))
    (beginning-of-defun -2)
    (should (looking-at-p "^(head3)$"))
    (beginning-of-defun -2)
    (should (looking-at-p "^(head3)$"))))

;;;; End of defun

(ert-deftest dialog-end-of-defun-forwards ()
  "Test moving forwards to end of the current head-rule."
  (dialog-mode-tests--with-temp-buffer
      "
(head1)
(head2)
(head3)
"
    (goto-char (point-min))
    (end-of-defun)
    (should (looking-at-p "^(head2)$"))
    (end-of-defun)
    (should (looking-at-p "^(head3)$"))
    (end-of-defun)
    (should (eobp))
    (end-of-defun)
    (should (eobp))))

(ert-deftest dialog-end-of-defun-forwards-with-args ()
  "Test moving forwards to end of the nth current head-rule."
  (dialog-mode-tests--with-temp-buffer
      "
(head1)
(head2)
(head3)
(head4)
(head5)
"
    (goto-char (point-min))
    (end-of-defun 2)
    (should (looking-at-p "^(head3)$"))
    (end-of-defun 2)
    (should (looking-at-p "^(head5)$"))
    (end-of-defun 2)
    (should (eobp))))

(ert-deftest dialog-end-of-defun-forwards-whitespace ()
  "Test moving forwards to end of the current head-rule.

If rule-heads are separated by whitespace then the end of the whitespace
is where the scope of the rule-head ends."
  (dialog-mode-tests--with-temp-buffer
      "
(head1)

(head2)

(head3)

"
    (goto-char (1+ (point-min)))
    (end-of-defun)
    (should (eq (line-number-at-pos) 3))
    (end-of-defun)
    (should (eq (line-number-at-pos) 5))
    (end-of-defun)
    (should (eobp))))

(ert-deftest dialog-end-of-defun-forwards-ignore-body ()
  "Test moving forwards to end of the current head-rule.

Ignore rule bodies."
  (dialog-mode-tests--with-temp-buffer
      "
(head1) body
	body
(head2) body
	body
(head3) body
	body
"
    (goto-char (1+ (point-min)))
    (end-of-defun)
    (should (looking-at-p "^(head2) body$"))
    (end-of-defun)
    (should (looking-at-p "^(head3) body$"))
    (end-of-defun)
    (should (eobp))))

;;;; Align

(ert-deftest dialog-align ()
  "Re-align syntax following rule-heads."
  (dialog-mode-tests--buffer-changes
      "
(head 1)(test)
(head 2)   (test)
(head 3)	(test)
(head 4) (test)
"
      "
(head 1)	(test)
(head 2)	(test)
(head 3)	(test)
(head 4)	(test)
"
    (align (point-min) (point-max))))

(ert-deftest dialog-align-ignore-body ()
  "Re-align syntax following rule-heads.

Ignore the rule bodies."
  (dialog-mode-tests--buffer-changes
      "
(head 1)(test)
	%% body 1
	(body 1)
(head 2)   (test)
	%% body 2
	(body 2)
(head 3)	(test)
	%% body 3
	(body 3)
(head 4) (test)
	%% body 4
	(body 4)
"
      "
(head 1)	(test)
	%% body 1
	(body 1)
(head 2)	(test)
	%% body 2
	(body 2)
(head 3)	(test)
	%% body 3
	(body 3)
(head 4)	(test)
	%% body 4
	(body 4)
"
    (align (point-min) (point-max))))

(ert-deftest dialog-align-ignore-comments ()
  "Re-align syntax following rule-heads.

Ignore comments that look like rule-heads."
  (dialog-mode-tests--buffer-changes
      "
(head 1)(test)
(head 2)   (test)

(head 3)	(test)
;; (not head)(test)
(head 4) (test)
"
      "
(head 1)	(test)
(head 2)	(test)

(head 3)	(test)
;; (not head)(test)
(head 4)	(test)
"
    (align (point-min) (point-max))))

(ert-deftest dialog-align-current ()
  "Re-align syntax following rule-heads for contiguous lines."
  (dialog-mode-tests--buffer-changes
      "
(head 1)(test)
(head 2)   (test)

(head 3)	(test)
(head 4) (test)
"
      "
(head 1)	(test)
(head 2)	(test)

(head 3)	(test)
(head 4) (test)
"
    (goto-char (1+ (point-min)))
    (align-current)))

;;;; Topic usage check

(ert-deftest dialog-uses-topic-in-rule-head ()
  "Look for use of a topic in a rule-head."
  (dialog-mode-tests--with-temp-buffer
      "(head *)"
    (goto-char (point-min))
    (should (dialog--rule-uses-topic-p))))

(ert-deftest dialog-uses-topic-in-rule-body ()
  "Look for use of a topic in a rule's body."
  (dialog-mode-tests--with-temp-buffer
      "(head)
	(body *)"
    (goto-char (point-min))
    (should (dialog--rule-uses-topic-p))))

(ert-deftest dialog-uses-topic-in-trailing-rule-body ()
  "Look for use of a topic in a rule's trailing body."
  (dialog-mode-tests--with-temp-buffer
      "(head)	(body *)"
    (goto-char (point-min))
    (should (dialog--rule-uses-topic-p))))

(ert-deftest dialog-uses-topic-ignore-as-prefix ()
  "Look for use of a topic in a rule's body.

Ignore the use of * as a prefix."
  (dialog-mode-tests--with-temp-buffer
      "(head)
	(exhaust) { *(extension version) }"
    (goto-char (point-min))
    (should-not (dialog--rule-uses-topic-p))))

(ert-deftest dialog-uses-topic-ignore-trailing-comments ()
  "Look for use of a topic in a rule's body.

Ignore trailing comments."
  (dialog-mode-tests--with-temp-buffer
      "(head)	%% (body *)"
    (goto-char (point-min))
    (should-not (dialog--rule-uses-topic-p))))

(ert-deftest dialog-uses-topic-in-rule-body-ignore-comments ()
  "Look for use of a topic in a rule's body.

Ignore comments."
  (dialog-mode-tests--with-temp-buffer
      "(head)
	%% (body *)"
    (goto-char (point-min))
    (should-not (dialog--rule-uses-topic-p))))

(ert-deftest dialog-uses-topic-in-rule-ignore-top-level ()
  "Look for use of a topic in a rule's body.

Ignore the top-level."
  (dialog-mode-tests--with-temp-buffer
      "(head)	*
	*"
    (goto-char (point-min))
    (should-not (dialog--rule-uses-topic-p))))

(ert-deftest dialog-uses-topic-in-rule-ignore-escaped ()
  "Look for use of a topic in a rule's body.

Ignore escaped asterisks."
  (dialog-mode-tests--with-temp-buffer
      "
(head)	(body \\*)
(head)	(body \\\\\\*)
(head)	(body \\\\\\\\\\*)"
    (goto-char (1+ (point-min)))
    (should-not (dialog--rule-uses-topic-p))
    (forward-line)
    (should-not (dialog--rule-uses-topic-p))
    (forward-line)
    (should-not (dialog--rule-uses-topic-p))))

(ert-deftest dialog-uses-topic-in-rule-double-escaped ()
  "Look for use of a topic in a rule's body.

Match when the escape character is escaped."
  (dialog-mode-tests--with-temp-buffer
      "
(head)	(body \\\\*)
(head)	(body \\\\\\\\\\\\*)
(head)	(body \\\\\\\\\\\\\\\\\\\\*)"
    (goto-char (1+ (point-min)))
    (should (dialog--rule-uses-topic-p))
    (forward-line)
    (should (dialog--rule-uses-topic-p))
    (forward-line)
    (should (dialog--rule-uses-topic-p))))

;;;; Paragraph motion

(ert-deftest dialog-forward-paragraph-through-comments ()
  "Test paragraph motion forwards through comments."
  (dialog-mode-tests--with-temp-buffer
      "
(rule head)

        (if) (condition) (then)

                %%% 1
                %%  2
                %%% 3
                %%% 31
                %%  4
                %%  41
                %%  42
                aa %%  5
                %%  6

                %%  7
                %%  71
                 %% 72
               %%   73
                %%  74
                %%  75

        (endif)

"
    (goto-char (point-min))
    (dolist (string (list "(rule head)"
                          "(then)"
                          "1"
                          "2"
                          "31"
                          "42"
                          "5"
                          "6"
                          "71"
                          "72"
                          "73"
                          "75"
                          "(endif)"
                          "(endif)"))
      (dialog-forward-paragraph)
      (should (equal (buffer-substring-no-properties
                      (save-excursion
                        (forward-sexp -1)
                        (point))
                      (point))
                     string)))))

(ert-deftest dialog-forward-paragraph-through-comments-2 ()
  "Test paragraph motion forwards through comments.

Move 2 paragraphs at a time."
  (dialog-mode-tests--with-temp-buffer
      "
(rule head)

        (if) (condition) (then)

                %%% 1
                %%  2
                %%% 3
                %%% 31
                %%  4
                %%  41
                %%  42
                aa %%  5
                %%  6

                %%  7
                %%  71
                 %% 72
               %%   73
                %%  74
                %%  75

        (endif)

"
    (goto-char (point-min))
    (dolist (string (list "(then)"
                          "2"
                          "42"
                          "6"
                          "72"
                          "75"
                          "(endif)"
                          "(endif)"))
      (dialog-forward-paragraph 2)
      (should (equal (buffer-substring-no-properties
                      (save-excursion
                        (forward-sexp -1)
                        (point))
                      (point))
                     string)))))

(ert-deftest dialog-backward-paragraph-through-comments ()
  "Test paragraph motion backwards through comments."
  (dialog-mode-tests--with-temp-buffer
      "
(rule head)

        (if) (condition) (then)

                %%% 1
                %%  2
                %%% 3
                %%% 31
                %%  4
                %%  41
                %%  42
                aa %%  5
                %%  6

                %%  7
                %%  71
                 %% 72
               %%   73
                %%  74
                %%  75

        (endif)

"
    (goto-char (point-max))
    (dolist (string (list "(endif)"
                          "74"
                          "73"
                          "72"
                          "7"
                          "6"
                          "5"
                          "4"
                          "3"
                          "2"
                          "1"
                          "(then)"
                          "(rule head)"
                          "(rule head)"))
      (dialog-forward-paragraph -1)
      (save-excursion
        (end-of-line)
        (should (equal (buffer-substring-no-properties
                        (save-excursion
                          (forward-sexp -1)
                          (point))
                        (point))
                       string))))))

(ert-deftest dialog-backward-paragraph-through-comments-2 ()
  "Test paragraph motion backwards through comments.

Move 2 paragraphs at a time."
  (dialog-mode-tests--with-temp-buffer
      "
(rule head)

        (if) (condition) (then)

                %%% 1
                %%  2
                %%% 3
                %%% 31
                %%  4
                %%  41
                %%  42
                aa %%  5
                %%  6

                %%  7
                %%  71
                 %% 72
               %%   73
                %%  74
                %%  75

        (endif)

"
    (goto-char (point-max))
    (dolist (string (list "74"
                          "72"
                          "6"
                          "4"
                          "2"
                          "(then)"
                          "(rule head)"
                          "(rule head)"))
      (dialog-forward-paragraph -2)
      (save-excursion
        (end-of-line)
        (should (equal (buffer-substring-no-properties
                        (save-excursion
                          (forward-sexp -1)
                          (point))
                        (point))
                       string))))))

(ert-deftest dialog-forward-paragraph-through-syntax ()
  "Test paragraph motion forwards through syntax."
  (dialog-mode-tests--with-temp-buffer
      "
(descr *)

        (if) (message has been trampled) (then)
                The message has been carelessly trampled, making it
                difficult to read. You can just distinguish the
                words...
                %% comment 1
                (par)
                (bold)\*\*\* You have lost \*\*\*(roman)
        (else)
                (increase score by 1)
                The message, neatly marked in the sawdust, reads...
                %% comment 2
                (par)
                (bold)\*\*\* You have won \*\*\*(roman)
                (testing)
        (endif)
        (game over)

"
    (let (dialog-paragraph-delimiter)
      (goto-char (point-min))
      (dolist (string (list "(descr *)"
                            "(then)"
                            "words..."
                            "1"
                            "***(roman)"
                            "(else)"
                            "reads..."
                            "2"
                            "(testing)"
                            "(game over)"
                            "(game over)"))
        (dialog-forward-paragraph)
        (should (equal (buffer-substring-no-properties
                        (save-excursion
                          (forward-sexp -1)
                          (point))
                        (point))
                       string))))))

(ert-deftest dialog-forward-paragraph-through-syntax-2 ()
  "Test paragraph motion forwards through syntax.

Move 2 paragraphs at a time."
  (dialog-mode-tests--with-temp-buffer
      "
(descr *)

        (if) (message has been trampled) (then)
                The message has been carelessly trampled, making it
                difficult to read. You can just distinguish the
                words...
                %% comment 1
                (par)
                (bold)\*\*\* You have lost \*\*\*(roman)
        (else)
                (increase score by 1)
                The message, neatly marked in the sawdust, reads...
                %% comment 2
                (par)
                (bold)\*\*\* You have won \*\*\*(roman)
                (testing)
        (endif)
        (game over)

"
    (let (dialog-paragraph-delimiter)
      (goto-char (point-min))
      (dolist (string (list "(then)"
                            "1"
                            "(else)"
                            "2"
                            "(game over)"
                            "(game over)"))
        (dialog-forward-paragraph 2)
        (should (equal (buffer-substring-no-properties
                        (save-excursion
                          (forward-sexp -1)
                          (point))
                        (point))
                       string))))))

(ert-deftest dialog-backward-paragraph-through-syntax ()
  "Test paragraph motion backwards through syntax."
  (dialog-mode-tests--with-temp-buffer
      "
(descr *)

        (if) (message has been trampled) (then)
                The message has been carelessly trampled, making it
                difficult to read. You can just distinguish the
                words...
                %% comment 1
                (par)
                (bold)\*\*\* You have lost \*\*\*(roman)
        (else)
                (increase score by 1)
                The message, neatly marked in the sawdust, reads...
                %% comment 2
                (par)
                (bold)\*\*\* You have won \*\*\*(roman)
                (testing)
        (endif)
        (game over)

"
    (let (dialog-paragraph-delimiter)
      (goto-char (point-max))
      (dolist (string (list "(endif)"
                            "(par)"
                            "2"
                            "(increase score by 1)"
                            "(else)"
                            "(par)"
                            "1"
                            "it"
                            "(then)"
                            "(descr *)"
                            "(descr *)"))
        (dialog-forward-paragraph -1)
        (save-excursion
          (end-of-line)
          (should (equal (buffer-substring-no-properties
                          (save-excursion
                            (forward-sexp -1)
                            (point))
                          (point))
                         string)))))))

(ert-deftest dialog-backward-paragraph-through-syntax-2 ()
  "Test paragraph motion backwards through syntax.

Move 2 paragraphs at a time."
  (dialog-mode-tests--with-temp-buffer
      "
(descr *)

        (if) (message has been trampled) (then)
                The message has been carelessly trampled, making it
                difficult to read. You can just distinguish the
                words...
                %% comment 1
                (par)
                (bold)\*\*\* You have lost \*\*\*(roman)
        (else)
                (increase score by 1)
                The message, neatly marked in the sawdust, reads...
                %% comment 2
                (par)
                (bold)\*\*\* You have won \*\*\*(roman)
                (testing)
        (endif)
        (game over)

"
    (let (dialog-paragraph-delimiter)
      (goto-char (point-max))
      (dolist (string (list "(par)"
                            "(increase score by 1)"
                            "(par)"
                            "it"
                            "(descr *)"
                            "(descr *)"))
        (dialog-forward-paragraph -2)
        (save-excursion
          (end-of-line)
          (should (equal (buffer-substring-no-properties
                          (save-excursion
                            (forward-sexp -1)
                            (point))
                          (point))
                         string)))))))

(ert-deftest dialog-forward-paragraph-through-syntax-default-delimiter ()
  "Test paragraph motion forwards through syntax with default delimiter."
  (dialog-mode-tests--with-temp-buffer
      "
(descr *)

        (if) (message has been trampled) (then)
                The message has been carelessly trampled, making it
                difficult to read. You can just distinguish the
                words...
                %% comment 1
                (par)
                (bold)\*\*\* You have lost \*\*\*(roman)
        (else)
                (increase score by 1)
                The message, neatly marked in the sawdust, reads...
                %% comment 2
                (par)
                (bold)\*\*\* You have won \*\*\*(roman)
                (testing)
        (endif)
        (game over)

"
    (goto-char (point-min))
    (dolist (string (list "(descr *)"
                          "(then)"
                          "words..."
                          "1"
                          "(par)"
                          "***(roman)"
                          "(else)"
                          "(increase score by 1)"
                          "reads..."
                          "2"
                          "(par)"
                          "***(roman)"
                          "(testing)"
                          "(endif)"
                          "(game over)"
                          "(game over)"))
      (dialog-forward-paragraph)
      (should (equal (buffer-substring-no-properties
                      (save-excursion
                        (forward-sexp -1)
                        (point))
                      (point))
                     string)))))

(ert-deftest dialog-backward-paragraph-through-syntax-default-delimiter ()
  "Test paragraph motion backwards through syntax with default delimiter."
  (dialog-mode-tests--with-temp-buffer
      "
(descr *)

        (if) (message has been trampled) (then)
                The message has been carelessly trampled, making it
                difficult to read. You can just distinguish the
                words...
                %% comment 1
                (par)
                (bold)\*\*\* You have lost \*\*\*(roman)
        (else)
                (increase score by 1)
                The message, neatly marked in the sawdust, reads...
                %% comment 2
                (par)
                (bold)\*\*\* You have won \*\*\*(roman)
                (testing)
        (endif)
        (game over)

"
    (goto-char (point-max))
    (dolist (string (list "(game over)"
                          "(endif)"
                          "(testing)"
                          "***(roman)"
                          "(par)"
                          "2"
                          "reads..."
                          "(increase score by 1)"
                          "(else)"
                          "***(roman)"
                          "(par)"
                          "1"
                          "it"
                          "(then)"
                          "(descr *)"
                          "(descr *)"))
      (dialog-forward-paragraph -1)
      (save-excursion
        (end-of-line)
        (should (equal (buffer-substring-no-properties
                        (save-excursion
                          (forward-sexp -1)
                          (point))
                        (point))
                       string))))))

(ert-deftest dialog-forward-paragraph-through-syntax-line-delimiter ()
  "Test paragraph motion forwards through syntax with a line delimiter."
  (dialog-mode-tests--with-temp-buffer
      "
(descr *)

        (if) (message has been trampled) (then)
                The message has been carelessly trampled, making it
                difficult to read. You can just distinguish the
                words...
                %% comment 1
                (par)
                (bold)\*\*\* You have lost \*\*\*(roman)
        (else)
                (increase score by 1)
                The message, neatly marked in the sawdust, reads...
                %% comment 2
                (par)
                (bold)\*\*\* You have won \*\*\*(roman)
                (testing)
        (endif)
        (game over)

"
    (let ((dialog-paragraph-delimiter t))
      (goto-char (point-min))
      (dolist (string (list "(descr *)"
                            "(then)"
                            "it"
                            "the"
                            "words..."
                            "1"
                            "(par)"
                            "***(roman)"
                            "(else)"
                            "(increase score by 1)"
                            "reads..."
                            "2"
                            "(par)"
                            "***(roman)"
                            "(testing)"
                            "(endif)"
                            "(game over)"
                            "(game over)"))
        (dialog-forward-paragraph)
        (should (equal (buffer-substring-no-properties
                        (save-excursion
                          (forward-sexp -1)
                          (point))
                        (point))
                       string))))))

(ert-deftest dialog-forward-paragraph-through-syntax-line-delimiter-2 ()
  "Test paragraph motion forwards through syntax with a line delimiter.

Move 2 paragraphs at a time."
  (dialog-mode-tests--with-temp-buffer
      "
(descr *)

        (if) (message has been trampled) (then)
                The message has been carelessly trampled, making it
                difficult to read. You can just distinguish the
                words...
                %% comment 1
                (par)
                (bold)\*\*\* You have lost \*\*\*(roman)
        (else)
                (increase score by 1)
                The message, neatly marked in the sawdust, reads...
                %% comment 2
                (par)
                (bold)\*\*\* You have won \*\*\*(roman)
                (testing)
        (endif)
        (game over)

"
    (let ((dialog-paragraph-delimiter t))
      (goto-char (point-min))
      (dolist (string (list "(then)"
                            "the"
                            "1"
                            "***(roman)"
                            "(increase score by 1)"
                            "2"
                            "***(roman)"
                            "(endif)"
                            "(game over)"
                            "(game over)"))
        (dialog-forward-paragraph 2)
        (should (equal (buffer-substring-no-properties
                        (save-excursion
                          (forward-sexp -1)
                          (point))
                        (point))
                       string))))))

(ert-deftest dialog-backward-paragraph-through-syntax-line-delimiter ()
  "Test paragraph motion backwards through syntax with a line delimiter."
  (dialog-mode-tests--with-temp-buffer
      "
(descr *)

        (if) (message has been trampled) (then)
                The message has been carelessly trampled, making it
                difficult to read. You can just distinguish the
                words...
                %% comment 1
                (par)
                (bold)\*\*\* You have lost \*\*\*(roman)
        (else)
                (increase score by 1)
                The message, neatly marked in the sawdust, reads...
                %% comment 2
                (par)
                (bold)\*\*\* You have won \*\*\*(roman)
                (testing)
        (endif)
        (game over)

"
    (let ((dialog-paragraph-delimiter t))
      (goto-char (point-max))
      (dolist (string (list "(game over)"
                            "(endif)"
                            "(testing)"
                            "***(roman)"
                            "(par)"
                            "2"
                            "reads..."
                            "(increase score by 1)"
                            "(else)"
                            "***(roman)"
                            "(par)"
                            "1"
                            "words..."
                            "the"
                            "it"
                            "(then)"
                            "(descr *)"
                            "(descr *)"))
        (dialog-forward-paragraph -1)
        (save-excursion
          (end-of-line)
          (should (equal (buffer-substring-no-properties
                          (save-excursion
                            (forward-sexp -1)
                            (point))
                          (point))
                         string)))))))

(ert-deftest dialog-backward-paragraph-through-syntax-line-delimiter-2 ()
  "Test paragraph motion backwards through syntax with a line delimiter.

Move 2 paragraphs at a time."
  (dialog-mode-tests--with-temp-buffer
      "
(descr *)

        (if) (message has been trampled) (then)
                The message has been carelessly trampled, making it
                difficult to read. You can just distinguish the
                words...
                %% comment 1
                (par)
                (bold)\*\*\* You have lost \*\*\*(roman)
        (else)
                (increase score by 1)
                The message, neatly marked in the sawdust, reads...
                %% comment 2
                (par)
                (bold)\*\*\* You have won \*\*\*(roman)
                (testing)
        (endif)
        (game over)

"
    (let ((dialog-paragraph-delimiter t))
      (goto-char (point-max))
      (dolist (string (list "(endif)"
                            "***(roman)"
                            "2"
                            "(increase score by 1)"
                            "***(roman)"
                            "1"
                            "the"
                            "(then)"
                            "(descr *)"
                            "(descr *)"))
        (dialog-forward-paragraph -2)
        (save-excursion
          (end-of-line)
          (should (equal (buffer-substring-no-properties
                          (save-excursion
                            (forward-sexp -1)
                            (point))
                          (point))
                         string)))))))

(ert-deftest dialog-forward-paragraph-column-zero ()
  "Test paragraph motion forwards through syntax which start in column 0."
  (dialog-mode-tests--with-temp-buffer
      "
(rule head)
aaa
bbb
#topic1
#topic2
%% comment 1
%% comment 2
ccc
ddd
(rule head)

"
    (goto-char (point-min))
    (dolist (string (list "(rule head)"
                          "aaa"
                          "bbb"
                          "#topic1"
                          "#topic2"
                          "2"
                          "ccc"
                          "ddd"
                          "(rule head)"
                          "(rule head)"))
      (dialog-forward-paragraph)
      (should (equal (buffer-substring-no-properties
                      (save-excursion
                        (forward-sexp -1)
                        (point))
                      (point))
                     string)))))

(ert-deftest dialog-forward-paragraph-column-zero-2 ()
  "Test paragraph motion forwards through syntax which start in column 0.

Move 2 paragraphs at a time."
  (dialog-mode-tests--with-temp-buffer
      "
(rule head)
aaa
bbb
#topic1
#topic2
%% comment 1
%% comment 2
ccc
ddd
(rule head)

"
    (goto-char (point-min))
    (dolist (string (list "aaa"
                          "#topic1"
                          "2"
                          "ddd"
                          "(rule head)"
                          "(rule head)"))
      (dialog-forward-paragraph 2)
      (should (equal (buffer-substring-no-properties
                      (save-excursion
                        (forward-sexp -1)
                        (point))
                      (point))
                     string)))))

(ert-deftest dialog-backward-paragraph-column-zero ()
  "Test paragraph motion backwards through syntax which start in column 0."
  (dialog-mode-tests--with-temp-buffer
      "
(rule head)
aaa
bbb
#topic1
#topic2
%% comment 1
%% comment 2
ccc
ddd
(rule head)

"
    (goto-char (point-max))
    (dolist (string (list "(rule head)"
                          "ddd"
                          "ccc"
                          "1"
                          "#topic2"
                          "#topic1"
                          "bbb"
                          "aaa"
                          "(rule head)"
                          "(rule head)"))
      (dialog-forward-paragraph -1)
      (save-excursion
        (end-of-line)
        (should (equal (buffer-substring-no-properties
                        (save-excursion
                          (forward-sexp -1)
                          (point))
                        (point))
                       string))))))

(ert-deftest dialog-backward-paragraph-column-zero-2 ()
  "Test paragraph motion backwards through syntax which start in column 0.

Move 2 paragraphs at a time."
  (dialog-mode-tests--with-temp-buffer
      "
(rule head)
aaa
bbb
#topic1
#topic2
%% comment 1
%% comment 2
ccc
ddd
(rule head)

"
    (goto-char (point-max))
    (dolist (string (list "ddd"
                          "1"
                          "#topic1"
                          "aaa"
                          "(rule head)"
                          "(rule head)"))
      (dialog-forward-paragraph -2)
      (save-excursion
        (end-of-line)
        (should (equal (buffer-substring-no-properties
                        (save-excursion
                          (forward-sexp -1)
                          (point))
                        (point))
                       string))))))

(ert-deftest dialog-forward-paragraph-mid-line ()
  "Test paragraph motion forwards starting in the middle of the line."
  (dialog-mode-tests--with-temp-buffer
      "
(rule head)
        (test)
        %% comment 1
        %% comment 2
        aaa
        bbb
(rule head)

"
    (goto-char (point-min))
    (dolist (string (list "(rule head)"
                          "(test)"
                          "2"
                          "bbb"
                          "(rule head)"))
      (forward-line)
      (end-of-line)
      (forward-char -2)
      (dialog-forward-paragraph)
      (should (equal (buffer-substring-no-properties
                      (save-excursion
                        (forward-sexp -1)
                        (point))
                      (point))
                     string)))))

(ert-deftest dialog-forward-paragraph-mid-line-2 ()
  "Test paragraph motion forwards starting in the middle of the line.

Move 2 paragraphs at a time."
  (dialog-mode-tests--with-temp-buffer
      "
(rule head)
        (test)
        %% comment 1
        %% comment 2
        aaa
        bbb
(rule head)

"
    (goto-char (point-min))
    (dolist (string (list "(test)"
                          "bbb"
                          "(rule head)"))
      (forward-line)
      (end-of-line)
      (forward-char -2)
      (dialog-forward-paragraph 2)
      (should (equal (buffer-substring-no-properties
                      (save-excursion
                        (forward-sexp -1)
                        (point))
                      (point))
                     string)))))

(ert-deftest dialog-backward-paragraph-mid-line ()
  "Test paragraph motion backwards starting in the middle of the line."
  (dialog-mode-tests--with-temp-buffer
      "
(rule head)
        (test)
        %% comment 1
        %% comment 2
        aaa
        bbb
(rule head)
"
    (goto-char (point-max))
    (dolist (string (list "(rule head)"
                          "aaa"
                          "1"
                          "(test)"
                          "(rule head)"))
      (forward-line -1)
      (end-of-line)
      (forward-char -2)
      (dialog-forward-paragraph -1)
      (save-excursion
        (end-of-line)
        (should (equal (buffer-substring-no-properties
                        (save-excursion
                          (forward-sexp -1)
                          (point))
                        (point))
                       string))))))

(ert-deftest dialog-backward-paragraph-mid-line-2 ()
  "Test paragraph motion backwards starting in the middle of the line.

Move 2 paragraphs at a time."
  (dialog-mode-tests--with-temp-buffer
      "
(rule head)
        (test)
        %% comment 1
        %% comment 2
        aaa
        bbb
(rule head)
"
    (goto-char (point-max))
    (dolist (string (list "aaa"
                          "(test)"
                          "(rule head)"))
      (forward-line -1)
      (end-of-line)
      (forward-char -2)
      (dialog-forward-paragraph -2)
      (save-excursion
        (end-of-line)
        (should (equal (buffer-substring-no-properties
                        (save-excursion
                          (forward-sexp -1)
                          (point))
                        (point))
                       string))))))

;;;; Font-lock

(require 'ert-font-lock nil 'noerror)
;; Prevent compilation warnings where there is no ert-font-lock.
(eval-when-compile
  (unless (functionp 'ert-font-lock-test-file)
    (declare-function ert-font-lock-test-file nil)))

(require 'ert-x)

(ert-deftest dialog-font-lock-level-1 ()
  "Test level 1 font-lock."
  (skip-unless (featurep 'ert-font-lock))
  (let ((font-lock-maximum-decoration '((dialog-mode . 1))))
    (ert-font-lock-test-file
     (ert-resource-file "font-lock-level-1.dg")
     'dialog-mode)))

(ert-deftest dialog-font-lock-level-2 ()
  "Test level 2 font-lock."
  (skip-unless (featurep 'ert-font-lock))
  (let ((font-lock-maximum-decoration '((dialog-mode . 2))))
    (ert-font-lock-test-file
     (ert-resource-file "font-lock-level-2.dg")
     'dialog-mode)))

(ert-deftest dialog-font-lock-level-3 ()
  "Test level 3 font-lock."
  (skip-unless (featurep 'ert-font-lock))
  (let ((font-lock-maximum-decoration '((dialog-mode . 3))))
    (ert-font-lock-test-file
     (ert-resource-file "font-lock-level-3.dg")
     'dialog-mode)))

;;; dialog-mode-tests.el ends here
