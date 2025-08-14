(use-package mistty) ;; https://github.com/szermatt/mistty

;; Includes familiar 'clojure-mode' based major-mode and keybindings:

(define-derived-mode phel-mode clojure-mode "Phel"
  "Major mode for editing Phel language source files."
  (setq-local comment-start "#")

  ;; Avoid picking up graphql-lsp that gets suggested automatically
  (add-to-list 'lsp-disabled-clients '(phel-mode . graphql-lsp))

  (add-hook 'phel-mode-hook 'hs-minor-mode)

  (define-key phel-mode-map (kbd "M-.") 'phel-xref-find-definitions)
  (define-key phel-mode-map (kbd "C-S-<tab>") 'hs-toggle-hiding)
  (define-key phel-mode-map (kbd "C-S-<iso-lefttab>") 'hs-toggle-hiding)

  (define-key phel-mode-map (kbd "C-c M-j") 'phel-repl)

  (define-key phel-mode-map (kbd "C-M-x") 'phel-send-sexp-to-process)
  (define-key phel-mode-map (kbd "C-x C-e") 'phel-send-sexp-to-process)
  (define-key phel-mode-map (kbd "C-c C-e") 'phel-send-region-or-buffer-to-process)

  (define-key phel-mode-map (kbd "C-c C-c") 'phel-send-first-comment-sexp-to-process)

  (define-key phel-mode-map (kbd "C-c C-t") 'phel-run-tests)
  (define-key phel-mode-map (kbd "C-c M-t") 'phel-switch-test-ns)

  (define-key phel-mode-map (kbd "C-c C-d C-p") 'phel-phpdoc)
  (define-key phel-mode-map (kbd "C-c C-d C-w") 'phel-wpdoc)
  (define-key phel-mode-map (kbd "C-c C-d C-d") 'phel-doc)

  (modify-syntax-entry ?# "<" phel-mode-syntax-table)
  (modify-syntax-entry ?\; "." phel-mode-syntax-table)

  ;; TODO correct load order for everything after this?
  :after
  (setq-local lsp-warn-no-matched-clients nil)

  (setq-local paredit-comment-prefix-margin "#")
  (setq-local paredit-comment-prefix-code "## ")
  (setq-local paredit-comment-prefix-toplevel "### ")

  ;; Phel nREPL (WIP) setup
  (setq nrepl-log-messages t)
  ;; These have to be global, not buffer local
  (setq cider-repl-init-code "")

  ;;(setq cider-info-form "")  # added lookup / info ops and this is not needed
  )

;; TODO ethan-whitespace conflict with:
;;personal/programming.el
;;65:  (setq mode-require-final-newline nil)

(add-to-list 'auto-mode-alist '("\\.phel\\'" . phel-mode))


;; Useful clojure-mode default bindings:
;; C-:         clojure-toggle-keyword-string
;; C-c SPC     clojure-align
;; C-c C-r s i clojure-introduce-let
;; C-c C-r s f clojure-let-forward-slurp-sexp
;; C-c C-r s b clojure-let-backward-slurp-sexp
;; C-c C-r s m clojure-move-to-let
;; C-c C-r [   clojure-convert-collection-to-vector
;; C-c C-r (   clojure-convert-collection-to-list
;; C-c C-r #   clojure-convert-collection-to-set
;; C-c C-r {   clojure-convert-collection-to-map
;; C-c C-r '   clojure-convert-collection-to-quoted-list
;; C-c C-r f clojure-thread-first-all
;; C-c C-r l clojure-thread-last-all
;; C-c C-r p clojure-cycle-privacy
;; C-c C-r i clojure-cycle-if (change if to if-not or back)
;; C-c C-r i clojure-cycle-when (change when to when-not or back)
;; C-c C-r o clojure-cycle-not (add or remove not around form)

;; Unbound:
;; clojure-unwind-all
;; clojure-forward-logical-sexp
;; clojure-backward-logical-sexp


;; Test runner 'phel-run-tests', REPL startup command 'phel-repl' and project
;; root selection for search depend on 'phel-config.php' at project dir or
;; it's parent dir. TODO read from composer.json instead.

;; Test runner 'phel-run-tests', REPL startup command 'phel-repl' use default
;; Phel commands by default and can be overridden on project basis by setting
;; custom x-phel-project-data directives in  'docker-compose.yml' as following:

;; x-phel-project-data:
;;   test-command: docker compose exec -w /opt/bitnami/wordpress/wp-content/plugins/my-plugin wordpress vendor/bin/phel test --testdox
;;   repl-command: docker compose exec -w /opt/bitnami/wordpress/wp-content/plugins/my-plugin wordpress vendor/bin/phel repl


;; Interactive REPL evaluation setup inspired from:
;; - https://emacs.stackexchange.com/a/37889/42614
;; - https://stackoverflow.com/a/7053298

(defun phel-get-or-set-process-target (arg)
  "Get the current process target or set a new one if needed."
  (if (or arg
          (not (boundp 'process-target))
          (not (process-live-p (get-buffer-process process-target))))
      (setq process-target
            (completing-read
             "Process: "
             (seq-map (lambda (el) (buffer-name (process-buffer el)))
                      (process-list))))
    process-target))


;; TODO research https://github.com/szermatt/mistty/blob/master/test/mistty-test.el
;; - use mistty--send-string or mistty--enqueue-str (?)
;;   https://github.com/szermatt/mistty/blob/master/mistty-queue.el

(defun phel-send-text-to-process (text)
  "Send the given text to the process buffer. Phel code being sent to REPL
  should be processed beforehand to avoid some quirks."
  (phel-get-or-set-process-target nil)
  (process-send-string process-target text)

  (let ((buf-name (car (last (split-string process-target " " t)))))
    (when (string= buf-name "*mistty*")
      (with-current-buffer buf-name
        (call-interactively 'mistty-send-command)))))

(defun phel-process-source (code)
  "Prepare Phel source code to be evaluated in Phel REPL. Fixes some quirks and
  cleans up comments."
  (with-temp-buffer
    (insert code)
	;;(print-buffer-to-messages "at input")

	;; TODO remove most workarounds https://github.com/phel-lang/phel-lang/pull/820 fixes

    ;; Remove (ns ...) form around require-statements
	;; Workaround for https://github.com/phel-lang/phel-lang/issues/766
	(goto-char (point-min))
    (when (re-search-forward "^(ns\\s-+" nil t)
	  (let ((start (match-beginning 0)))
		;; Erase ending parenthesis
		(goto-char start)
		(forward-sexp)
		(backward-char)
		(delete-char 1)

		;; Erase the ns-form line
		(goto-char start)
		(beginning-of-line)
		(kill-line)))

	;; (print-buffer-to-messages "after ns removal")

	;; Remove comment forms, TODO does not take into account comment lines not
	;; having newline right after comment symbol
	(goto-char (point-min))
    (while (re-search-forward "(comment\\s-*\n" nil t)
	  (let ((start (match-beginning 0)))
        (goto-char start)
        (forward-sexp)
        (delete-region start (point))))

	;; Delete comments (everything on each line after # character)
	(goto-char (point-min))
    (while (re-search-forward "#.*$" nil t)
      (replace-match ""))

	;; Convert :require-file to php/require_once (related to issue 766)
    (goto-char (point-min))
    (while (search-forward "(:require-file " nil t)
      (replace-match "(php/require_once "))

    ;; Convert :require to require (related to issue 766)
    (goto-char (point-min))
    (while (search-forward "(:require " nil t)
      (replace-match "(require "))

	;; .. same for :use
    (goto-char (point-min))
    (while (search-forward "(:use " nil t)
      (replace-match "(use "))

	;; Replace tab characters triggering shell auto-complete
	;; (goto-char (point-min))
    ;; (while (search-forward "\t" nil t)
    ;;   (replace-match " "))

	;; (print-buffer-to-messages "before removing whitespace")

	;; Delete all empty lines
	(goto-char (point-min))
    (flush-lines "^\\s-*$")

	;; If the last character is newline, remove it
	(goto-char (point-max))
	(if (eq (char-before) ?\n)
		(delete-char -1))

	;; (print-buffer-to-messages "after processing")

    (buffer-string)))

(defun phel-blink-region (start end)
  "Make the text between START and END blink."
  (let ((overlay (make-overlay start end)))
    (overlay-put overlay 'face 'success)
    (run-at-time 0.1 nil 'delete-overlay overlay)))

(defun phel-send-region-or-buffer-to-process (arg &optional beg end)
  "Send the current buffer or region to a process buffer. The first time it's
  called, will prompt for the buffer to send to. Subsequent calls send to the
  same buffer, unless a prefix argument is used (C-u), or the buffer no longer
  has an active process."
  (interactive (list current-prefix-arg
					 (when (use-region-p) (region-beginning))
					 (when (use-region-p) (region-end))))

  (phel-get-or-set-process-target arg)

  (let ((text (if (and (region-active-p) (use-region-p))
				  (progn
					(phel-blink-region beg end)
					(buffer-substring-no-properties beg end))
                (progn
				  (phel-blink-region (point-min) (point-max))
				  (buffer-substring-no-properties (point-min) (point-max))))))
    (phel-send-text-to-process (phel-process-source text))))

(defun phel-send-sexp-to-process ()
  "Send the Phel sexp at point to the process buffer."
  (interactive)
  (save-excursion
    (end-of-defun)
    (let ((end (point)))
      (beginning-of-defun)
      (let ((start (point)))
		(phel-blink-region start end)
        (phel-send-text-to-process
		 (phel-process-source (buffer-substring-no-properties start end)))))))

(defun phel-send-first-comment-sexp-to-process ()
  "Evaluates first s-exp inside comment form e.g. for evaluating defn being
  written with pre-set args. Idea from ed at Clojurians Slack. Requires form
  to be placed on newline after comment symbol."
  (interactive)
  (save-excursion
	(re-search-forward "(comment\\s-*\n")  ; TODO allow comment without newline
	(forward-sexp)
	(phel-send-sexp-to-process)))

;; Test runner and REPL startup command setup

(defun phel-find-project-root ()
  "Find the root directory of the Phel project."
  (locate-dominating-file (buffer-file-name) "phel-config.php"))


;; TODO if there are multiple possibilities, allow user ask which to use
(defun phel-read-compose-setting (setting-key)
  "Read a project setting from docker-compose.yml.
   Traverses up the filesystem from the current buffer's file path
   to find the first docker-compose.yml containing the given setting-key
   x-project-data directive.
   Returns tuple '(docker-compose-path setting-value) when found."
  ;; (message (concat "read setting val for " setting-key))
  (let ((file-path (buffer-file-name))
        (root-dir "/")
        (setting-value nil))
    (while (and file-path (not (string= file-path root-dir))
				(not setting-value))
      (let ((docker-compose-path
			 (expand-file-name "docker-compose.yml" file-path)))
        (when (file-exists-p docker-compose-path)
		  ;; (message (concat "at " docker-compose-path))
          (let* ((yaml-data (yaml-parse-string
                             (with-temp-buffer
                               (insert-file-contents docker-compose-path)
                               (buffer-string))))
                 (custom-data (gethash 'x-phel-project-data yaml-data)))
            (when custom-data
              (setq setting-value (gethash (intern setting-key) custom-data))
              (when setting-value
				;;(message "found setting-val")
                (setq setting-value
					  (cons (file-name-directory docker-compose-path)
							setting-value))))))
        (setq file-path (file-name-directory (directory-file-name file-path)))))
    setting-value))

(defun phel-read-repl-command ()
  "Get the REPL command for the current Phel project either from repl.sh or
   custom docker-compose.yml config directive (TODO refactor):
   - x-phel-project-data:
     - repl-command: <command>"
  (let ((repl-sh-path (locate-dominating-file (buffer-file-name) "repl.sh")))
    (if repl-sh-path
        ;; Read command from repl.sh, skipping comments
        (with-temp-buffer
          (insert-file-contents (concat repl-sh-path "repl.sh"))
          (goto-char (point-min))
          ;; Remove all comment lines and empty lines
          (flush-lines "^\\s-*#.*$")
          (flush-lines "^\\s-*$")
          ;; Get the remaining content as the command
          (let ((command (string-trim (buffer-string))))
            (when (not (string-empty-p command))
              (concat "cd " repl-sh-path " && " command))))
      (let ((compose-setting-command (phel-read-compose-setting "repl-command")))
        (if compose-setting-command
            (let ((project-path (car compose-setting-command))
                  (command (cdr compose-setting-command)))
              (concat "cd " project-path " && " command))
          (let ((root (phel-find-project-root)))
            (when root
              (concat "cd " root " && ./vendor/bin/phel repl"))))))))

(defun phel-repl ()
  "Starts or opens existing Phel REPL process mistty buffer in current window.
  Expects buffer name to be '*mistty*'"
  (interactive)
  (if (and (boundp 'mistty-buffer-name)
           (get-buffer "*mistty*"))
      (progn
		;; (message "phel-repl: reusing existing *mistty* buffer")
		(switch-to-buffer "*mistty*"))
    (progn
      (mistty)
      (setq process-target (buffer-name (current-buffer)))
      ;; (setq mistty-repl-command (phel-read-repl-command))
      ;; (message mistty-repl-command)
      (phel-send-text-to-process (phel-read-repl-command)))))

(defun phel-read-test-command ()
  "Get the test runner command for the current Phel project."

  ;; add condition that if there's docker-compose.yml (here or upper level)
  ;; that has the custom directive
  ;; use that as test command (allowing container tests)
  ;; otherwise use default

  ;; TODO if current file is test file?

  (let ((compose-setting-command (phel-read-compose-setting "test-command")))
    (if compose-setting-command
		(let ((project-path (car compose-setting-command))
              (command (cdr compose-setting-command)))
          (concat "cd " project-path " && " command))
	  (let ((root (phel-find-project-root)))
		(when root
		  (concat "cd " root " && ./vendor/bin/phel test --testdox"))))))

;; TODO local vs container setup in progress, test / repl commands broken
;; TODO how to make work with different scenarios, e.g. WordPress plugin project
;; should have independent test suite, while it's useful to have separate
;; full production WP site environment for development and integration testing.
(defun phel-run-tests (&optional run-all)
  "Run tests for file or project, printing results in messages buffer.
  Expects default Phel project structure having 'phel-config.php'.
  By default runs tests for current file. If passed universal argument, runs all
  tests for project. Opens results in new window for now, room for improvement."
  (interactive "P")
  (let* ((command (phel-read-test-command))
         (file (when (not run-all) (buffer-file-name)))
         (phel-config-dir (file-name-directory
							  (locate-dominating-file
							   (buffer-file-name) "phel-config.php")))
         (relative-file (when file
                          (replace-regexp-in-string
                           "src/"
                           "tests/"
                           (file-relative-name file phel-config-dir))))
         (full-command (if relative-file
                           (concat command " " relative-file)
                         command)))
    (message "Running tests with command:")
	(message full-command)
    (let ((output (shell-command-to-string full-command)))
      (with-current-buffer (get-buffer-create "*Phel Test Results*")
        (erase-buffer)
        (insert output)
        (make-frame
		 '((buffer-predicate . (lambda (buf) (eq buf (current-buffer)))))))
      (message "Tests completed. Results in *Phel Test Results* buffer."))))

(defun phel-switch-test-ns ()
  "Attempts to switch to according test namespace or back to source namespace.
  If according test namespace is missing, one is created with initial namespace declaration."
  (interactive)
  (let* ((current-file (buffer-file-name))
         (is-test-file (string-match-p "/tests/" current-file))
         (file-to-switch-to (if is-test-file
                                (replace-regexp-in-string "/tests/" "/src/" current-file)
                              (replace-regexp-in-string "/src/" "/tests/" current-file)))
         (ns-path (replace-regexp-in-string "^.*/\\(src\\|tests\\)/" ""
                                            (file-name-sans-extension file-to-switch-to)))
         (ns-name (replace-regexp-in-string "/" "\\" ns-path t t))
         (parent-dir (let ((dir (file-name-directory current-file)))
                       (while (and dir (not (or (file-exists-p (concat dir "src"))
                                                (file-exists-p (concat dir "tests")))))
                         (setq dir (file-name-directory (directory-file-name dir))))
                       (when dir
                         (file-name-nondirectory (directory-file-name dir)))))
         (module-name (file-name-nondirectory (file-name-sans-extension file-to-switch-to))))
    (message "Switching to %s" file-to-switch-to)
    (if (file-exists-p file-to-switch-to)
        (find-file file-to-switch-to)
      (progn
        (find-file file-to-switch-to)
        (goto-char (point-min))
        (when (= (point-min) (point-max)) ; buffer empty?
		  (insert (if (not is-test-file)
                    (format "(ns %s\\tests\\%s\n  (:require phel\\test :refer [deftest is thrown?])\n  (:require %s\\src\\%s :as %s))\n\n"
                            parent-dir ns-name parent-dir ns-name module-name)
                  (format "(ns %s\\src\\%s)\n\n" parent-dir ns-name))))
        (message "Created and switched to new file: %s" file-to-switch-to)))))

;; Simplified go-to definition

(defvar phel-definition-regex
  "(\\(defn\\(-\\)?\\|def\\|defmacro\\)\\s-?%s\\b"
  "Format string regex template for some Phel functions/macros creating top
  level bindings. '%s' is replaced with the symbol name.")

(defun phel-xref-find-definitions (&optional arg)
  "Search for definition of symbol at point and navigate to it.
  When given universal argument, run 'ripgrep' for the definition instead.
  Uses xref for navigation and 'docker-compose.yml' to determine project root."
  (interactive "P")
  (let* ((symbol (thing-at-point 'symbol t))
         (project-root (locate-dominating-file
						default-directory "docker-compose.yml"))
         (defn-regex (format phel-definition-regex (regexp-quote symbol))))
    (if arg
        (phel-xref-find-definitions-with-consult-ripgrep symbol project-root)
      (phel-xref-find-definitions-in-current-file symbol defn-regex))))

(defun phel-extract-symbol-name (symbol)
  "Extract 'symbol' name without namespace."
  (if (string-match-p "/" symbol)
      (car (last (split-string symbol "/")))
    symbol))

(defun phel-xref-find-definitions-with-consult-ripgrep (symbol project-root)
  "Run consult-ripgrep to find definition of 'symbol' in 'project-root'"
  (if project-root
      (let* ((default-directory project-root)
             (function-name (phel-extract-symbol-name symbol))
             (search-pattern (format phel-definition-regex
									 (regexp-quote function-name)))
             (consult-ripgrep-args (concat consult-ripgrep-args
										   " --no-ignore-vcs")))
        (xref-push-marker-stack)
        (consult-ripgrep default-directory search-pattern))
    (message "Project root not found. Cannot perform ripgrep search.")))

(defun phel-xref-find-definitions-in-current-file (symbol defn-regex)
  "Find definition of 'symbol' in current file using 'defn-regex'"
  (let ((definition-point
         (save-excursion
           (goto-char (point-min))
           (when (re-search-forward defn-regex nil t)
             (match-beginning 0)))))
    (if definition-point
        (progn
          (xref-push-marker-stack)
          (goto-char definition-point)
          (recenter))
      (message "Definition not found in current file."))))

;; Documentation

(defun phel-open-doc-url (url-format)
  "Open documentation URL for the symbol at point."
  (let* ((symbol (thing-at-point 'symbol t))
         (function-name (phel-extract-symbol-name symbol))
         (url (format url-format function-name)))
    (browse-url url)))

(defun phel-doc ()
  "Navigate to PHP documentation for the symbol at point."
  (interactive)
  (phel-open-doc-url "https://phel-lang.org/documentation/api/#%s"))

(defun phel-phpdoc ()
  "Navigate to PHP documentation for the symbol at point."
  (interactive)
  (phel-open-doc-url "https://www.php.net/manual/en/function.%s.php"))

(defun phel-wpdoc ()
  "Navigate to WordPress documentation for the symbol at point."
  (interactive)
  (phel-open-doc-url "https://developer.wordpress.org/reference/functions/%s/"))

;; Misc

(defun print-buffer-to-messages (&optional prefix)
  "Print the current buffer's contents to the *Messages* buffer for debugging.
  If 'prefix' is provided, it is inserted at the specified location in the
  message."
  (interactive)
  (let* ((buffer-contents (buffer-substring-no-properties
						   (point-min) (point-max)))
         (message-template "### Buffer contents ({prefix}):\n%s")
         (message-text
		  (if prefix
              (replace-regexp-in-string "{prefix}" prefix message-template)
            (replace-regexp-in-string " ({prefix})" "" message-template))))
    (message message-text buffer-contents)))
