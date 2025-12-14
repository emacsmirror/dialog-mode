Dialog Mode is an Emacs major mode for creating and editing Dialog files.
The following features are implemented:

* Syntax-highlighting.
* Indentation.
* Motion around and selection of rule definitions.
* Align support for alignment of syntax following a rule-head.
* Imenu support for rule-heads (including topic when relevant).
* Outline Mode support for comments and topics.
* Comint support for running the Dialog debugger.

The following commands are bound in the major-mode keymap:

  `dialog-toggle-indent' {C-c TAB}
    Add or remove indentation on the current line.

  `dialog-toggle-indent-and-newline' {C-c RET}
    Add or remove indentation on the current line and then insert a newline.

  `dialog-up-block' {C-c C-u}
    Move point to the beginning of the current block.

  `dialog-debug-send-command' {C-c C-c}
    Send a command (usually "@replay") to the debug process.  There needs to
    already be a debug process running for this to work.  If hooks are
    configured to save the current buffer this is effectively a hot-reload to
    incorporate the latest buffer changes.

  `dialog-debug-run' {C-c C-z}
    Start the debugger as `comint' process and pop to its buffer.  If the
    process already exists, just pop to its buffer.

  `fill-paragraph' {M-q}
    Fill the current paragraph.  This is rebound to avoid calling
    `prog-fill-reindent-defun' which wouldn't have the expected effect.

When using `fill-paragraph' the effects are currently restricted to the
current line.  This restriction is in place because general text and Dialog
syntax are likely both present on contiguous lines of varying length at the
same indentation level.  To fill multiple lines, select the region first.

For source code which uses a double sized indent for the first level of
indentation, set the value of `dialog-indent-initial-size' to 2.

Use `align' and `align-current' to modify whitespace for vertical alignment
of syntax which shares the line with a rule-head.  Alignment is configured to
use tab-stops by default but can be customized by modifying the variable
`dialog-align-rules-list'.

Comint support will start the Dialog debugger with the game files specified
by the value of `dialog-game-files' which is a list of file names to use.
This variable is intended to be used as a directory local variable to allow
the file names to vary per project.  An example .dir-locals.el file might
look like this:

  ((nil . ((dialog-game-files . ("cloak.dg" "stdlib.dg")))))

Setting the value of `dialog-game-files' by other methods should also work.
Taking a guess by looking for files with a ".dg" extension as the major mode
is being initialized is potentially inefficient and error prone but may be
suitable for smaller projects where the debug process is only managed from
`dialog-mode' buffers:

  (add-hook 'dialog-mode-hook
            (lambda ()
              (unless dialog-game-files
                (let ((files (directory-files
                              default-directory nil "\\.dg\\'"))
                      (stddebug "stddebug.dg")
                      (stdlib "stdlib.dg"))
                  ;; Remove the debug library from the list.
                  (setq files (delete stddebug files))
                  ;; Move the standard library to the end of the list.
                  (when (member stdlib files)
                    (setq files (append (delete stdlib files)
                                        (list stdlib))))
                  (setq dialog-game-files files)))))

If no game files are configured a prompt will appear to select them.  This is
a prompt for multiple files; the default separator for completing multiple
files in Emacs is a comma.

Note: The order of the files in the `dialog-game-files' list is significant
in the same way it is when compiling or manually running the debug program.

The game file names are expanded relative to the current project root as
determined by `project'.  If the game source code is being version controlled
it is likely that no further configuration will be required, in other cases
it may be required to find another way to identify the project root.  One way
to do this is by using the standard library file name as project root marker:

  (require 'project)
  (add-to-list 'project-vc-extra-root-markers "stdlib.dg")

If the project root cannot be determined the game file names are expanded
relative to the current directory.

For an equivalent of hot-reload, the function `dialog-debug-send-command'
will default to sending "@replay" to the debug process after the default
value of `dialog-debug-send-command-hook' has prompted to save any modified
buffers.  To save the current buffer automatically or take any other custom
actions before the command is sent, customize the hook variable to have the
desired effect.

  ;; Automatically save the current `dialog-mode' buffer when replaying.
  (add-hook 'dialog-debug-send-command-hook
            (lambda ()
              (when (and (derived-mode-p 'dialog-mode)
                         (equal dialog-debug-send-command-input "@replay"))
                (save-buffer))))

To make the debug process work more like it does in a terminal and support
the display of text styling, set the value of `dialog-debug-use-pty' to t and
toggle automatic dismissal of "[more]" prompts with the command
`dialog-debug-toggle-output-responder'.

To run the debug program directly instead of as a command interpreter set the
value `dialog-debug-as-interp' to nil.  This also defaults command sending to
use the clipboard.  A value of nil is the default when using Microsoft
Windows because the Windows build of the debugger can currently only run in a
graphical window and is unable to receive input outside of that interface.
That said, the function used to send a command is configurable and so you are
free to attempt to send a command to the Windows build of the debugger by
another method at your own risk:

  (defconst dialog-debug-send-ahk-script
    "
  command := EnvGet('DIALOG_DEBUG_COMMAND')
  SetTitleMatchMode 3  ; Exact match for window title.
  Try {
      ControlSend command '{Enter}',, 'Dialog Interactive Debugger'
  }
  Catch {
      Exit 1
  }
  "
    "The AutoHotkey send command script.")

  (defun dialog-debug-send-command-with-ahk ()
    "Send a command to the debug program window using AutoHotkey."
    (let ((process-environment
           (cons
            (concat "DIALOG_DEBUG_COMMAND=" dialog-debug-send-command-input)
            process-environment)))
      (message "Sending command '%s' using AutoHotkey"
               dialog-debug-send-command-input)
      (unless (eq 0 (with-temp-buffer
                      (insert dialog-debug-send-ahk-script)
                      (call-process-region (point-min) (point-max)
                                           "autohotkey" nil nil nil "*")))
        (message "Failed to send command"))))

  (setq dialog-debug-send-command-function
        #'dialog-debug-send-command-with-ahk)

Basic configuration:

  (with-eval-after-load 'dialog-mode
    ;; Match indentation and fill-column to the standard library.
    (add-hook 'dialog-mode-hook
              (lambda ()
                (indent-tabs-mode)
                (setq fill-column 79)))
    ;; Bind a key for easier access to Imenu.
    (define-key dialog-mode-map (kbd "C-c C-j") #'imenu))

If using Imenu or `which-function-mode' it will be beneficial to make sure
that the value of `imenu-auto-rescan' is set to t.

It may be preferable to customize the value of `font-lock-maximum-decoration'
to reduce the font-lock level for Dialog Mode to 2.
