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
	\"
(string)
\"
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
	\"
(string)
\"
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

(ert-deftest dialog-align-ignore-strings-and-comments ()
  "Re-align syntax following rule-heads.

Ignore comments and strings that look like rule-heads."
  (dialog-mode-tests--buffer-changes
      "
(head 1)(test)
(head 2)   (test)
\"
(not head)(test)
\"
(head 3)	(test)
;; (not head)(test)
(head 4) (test)
"
      "
(head 1)	(test)
(head 2)	(test)
\"
(not head)(test)
\"
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

(ert-deftest dialog-uses-topic-ignore-trailing-comments ()
  "Look for use of a topic in a rule's body.

Ignore trailing comments."
  (dialog-mode-tests--with-temp-buffer
      "(head)	%% (body *)"
    (goto-char (point-min))
    (should-not (dialog--rule-uses-topic-p))))

(ert-deftest dialog-uses-topic-ignore-trailing-strings ()
  "Look for use of a topic in a rule's body.

Ignore trailing strings."
  (dialog-mode-tests--with-temp-buffer
      "(head)	\"*\""
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

(ert-deftest dialog-uses-topic-in-rule-body-ignore-strings ()
  "Look for use of a topic in a rule's body.

Ignore strings."
  (dialog-mode-tests--with-temp-buffer
      "(head)
	(body \"*\")"
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

(ert-deftest dialog-uses-topic-ignore-rule-in-string ()
  "Look for use of a topic in a rule's body.

Ignore a string that looks like a rule-head."
  (dialog-mode-tests--with-temp-buffer
      "\"
(head *)\"
	(body *)"
    (goto-char (+ (point-min) 2))
    (should-not (dialog--rule-uses-topic-p))))

;;; dialog-mode-tests.el ends here
