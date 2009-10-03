;;;; ri-ruby.el emacs wrapper around ri
;;
;; Modified by Perry Smith <pedz@easesoftware.com>
;;   July 11th, 2009
;;
;; Added much debugging capabilities.  Made various parts of the
;; rendered page ``clicka-able''.  The way it is suppose to work is
;; a click on base class will take you to the class or module.  If the
;; page is for a page or module, each method is ``click-able'' to take
;; you to the RDoc page for that method.  etc.
;;
;; Author: Kristof Bastiaensen <kristof@vleeuwen.org>
;;
;;
;;    Copyright (C) 2004,2006 Kristof Bastiaensen
;;
;;    This program is free software; you can redistribute it and/or modify
;;    it under the terms of the GNU General Public License as published by
;;    the Free Software Foundation; either version 2 of the License, or
;;    (at your option) any later version.
;;
;;    This program is distributed in the hope that it will be useful,
;;    but WITHOUT ANY WARRANTY; without even the implied warranty of
;;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;    GNU General Public License for more details.
;;
;;    You should have received a copy of the GNU General Public License
;;    along with this program; if not, write to the Free Software
;;    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
;;----------------------------------------------------------------------
;;
;;
;;  Installing:
;;  ===========
;;
;;  add the following to your init.el, replacing the filenames with
;;  their correct locations:
;;
;;  (setq ri-ruby-script "/home/kristof/.xemacs/ri-emacs.rb")
;;  (autoload 'ri "/home/kristof/.xemacs/ri-ruby.el" nil t)
;;
;;  You may want to bind the ri command to a key.
;;  For example to bind it to F1 in ruby-mode:
;;  Method/class completion is also available.
;;
;;   (add-hook 'ruby-mode-hook (lambda ()
;;                               (local-set-key 'f1 'ri)
;;                               (local-set-key "\M-\C-i" 'ri-ruby-complete-symbol)
;;                               (local-set-key 'f4 'ri-ruby-show-args)
;;                               ))
;;
;;
;;  Usage:
;;  ======
;;  M-x ri
;;
;;  M-Tab for completion
;;  
;;  Bugs:
;;  ====
;;
;;  * The first time you give the ri command on xemacs, it may give
;;    strange behaviour in XEmacs.  This is probably due to a
;;    bug in the way XEmacs handles processes under linux.
;;
;;  * It is reported that the ruby-script doesn't work with XEmacs under
;;    MS-Windows.  This is probably a bug in processes in XEmacs.  
;;
;;  Contributors:
;;  =============
;;
;;  rubikitch (http://www.rubyist.net/~rubikitch/):
;;    fixed highlighting under Emacs

(require 'ansi-color)

(defvar ri-ruby-program "ruby"
  "The ruby program name.")

(defvar ri-ruby-script
  (concat (getenv "HOME") "/.emacs.d/ruby/ri-emacs/ri-emacs.rb")
  "the ruby script to communicate with")

(defvar ri-ruby-process nil
  "The current ri process where emacs is interacting with")

(defvar ri-ruby-history nil
  "The history for ri")

(defvar ri-ruby-process-buffer nil)
;; These three variables are here just to make debugging possible.
(defvar ri-ruby-last-get-expr nil)
(defvar ri-buffer-count 0)
(defvar ri-debug nil)			;set to t when debugging
(defvar ri-kill-buffers (not ri-debug))

(defun ri-ruby-kill ()
  "Kills the ri-ruby process so a new one can be started"
  (interactive)
  (if ri-ruby-process
      (kill-process ri-ruby-process)))

(defun ri-ruby-get-process ()
  (cond ((or (null ri-ruby-process)
	     (not (equal (process-status ri-ruby-process) 'run)))
	 (setq ri-ruby-process
	       (start-process "ri-ruby-process"
			      nil
			      ri-ruby-program ri-ruby-script))
	 (process-kill-without-query ri-ruby-process) ;kill when ending emacs
	 (ri-ruby-process-check-ready)))
  ri-ruby-process)

(defun ri-ruby-process-filter-expr (proc str)
  (let ((ansi-color-context nil))
    (save-excursion
      (set-buffer ri-ruby-process-buffer)
      (goto-char (point-max))
      (insert-string (ansi-color-filter-apply str)))))

(defun ri-ruby-process-filter-lines (proc str)
  (save-excursion
    (set-buffer ri-ruby-process-buffer)
    (goto-char (point-max))
    (insert-string (ansi-color-apply str))))

(defun ri-generate-new-buffer ( str who )
  (generate-new-buffer
   (concat str (int-to-string
		(setq ri-buffer-count (1+ ri-buffer-count))) who)))

(defvar ri-startup-timeout .5)
(defun ri-ruby-process-check-ready ()
  (let ((ri-ruby-process-buffer (ri-generate-new-buffer  " ri-ruby-output" "check-ready"))
	(loop-counter 0)
	(found nil))
    (unwind-protect
	(save-excursion
	  (set-buffer ri-ruby-process-buffer)
	  (set-process-filter ri-ruby-process 'ri-ruby-process-filter-expr)
	  (ri-ruby-check-process ri-ruby-process-buffer)
	  (while (and (< loop-counter 10)
		      (not found))
	    (accept-process-output ri-ruby-process ri-startup-timeout)
	    (goto-char (point-max))
	    (forward-line -1)
	    (if (not (setq found (looking-at "READY.*\n")))
		(progn
		  (and ri-debug (message "counter %d" loop-counter))
		  (setq loop-counter (1+ loop-counter)))))
	  (unless found
	    (delete-process ri-ruby-process)
	    (error "Couldn't start ruby script")))
      (set-process-filter ri-ruby-process t)
      (if ri-kill-buffers
	  (kill-buffer ri-ruby-process-buffer)))))

(defun ri-ruby-check-process (buffer)
  (or (equal (process-status ri-ruby-process) 'run)
      (let ((output (with-current-buffer buffer
                      (buffer-substring (point-min)
                                        (point-max)))))
	(error "Process is not running.\n" output))))

(defun ri-ruby-process-get-expr (cmd param)
  (ri-ruby-get-process)
    (let ((ri-ruby-process-buffer (ri-generate-new-buffer  " ri-ruby-output" "get-expr"))
	  (command (concat cmd " " param "\n")))
      (unwind-protect
	  (save-excursion
	    (set-buffer ri-ruby-process-buffer)
	    (set-process-filter ri-ruby-process 'ri-ruby-process-filter-expr)
	    (and ri-debug (message "Sending %s" command))
	    (process-send-string ri-ruby-process command)
	    (ri-ruby-check-process ri-ruby-process-buffer)
	    (while (progn (goto-char (point-min))
			  (not (looking-at ".*\n"))) ;we didn't read a whole line
	      (ri-ruby-check-process ri-ruby-process-buffer)
	      (accept-process-output ri-ruby-process))
	    (goto-char (point-min))
	    (setq ri-ruby-last-get-expr
		  (read (buffer-substring (point)
					  (point-at-eol)))))
	(set-process-filter ri-ruby-process t)
	(if ri-kill-buffers
	    (kill-buffer ri-ruby-process-buffer)))))

(defun ri-ruby-process-get-lines (cmd param)
  (ri-ruby-get-process)
  (if (equal param "") nil
    (let ((ri-ruby-process-buffer (ri-generate-new-buffer " ri-ruby-output" "get-lines"))
	  (command (concat cmd " " param "\n")))
      (unwind-protect
	  (save-excursion
	    (set-buffer ri-ruby-process-buffer)
	    (set-process-filter ri-ruby-process 'ri-ruby-process-filter-lines)
	    (process-send-string ri-ruby-process command)
	    (ri-ruby-check-process ri-ruby-process-buffer)
	    (while (progn (goto-char (point-max))
			  (goto-char (point-at-bol 0))
			  (not (looking-at "RI_EMACS_END_OF_INFO$")))
	      (ri-ruby-check-process ri-ruby-process-buffer)
	      (accept-process-output ri-ruby-process))
	    (if (bobp) nil
	      (backward-char)
	      (buffer-substring (point-min) (point))))
	(set-process-filter ri-ruby-process t)
	(if ri-kill-buffers
	    (kill-buffer ri-ruby-process-buffer))))))

(defun ri-ruby-complete-method (str pred type)
  (let* ((cmd (cdr (or (assoc type '((nil . "TRY_COMPLETION")
				     (t   . "COMPLETE_ALL")))
		       '(lambda . "LAMBDA"))))
	 ;;(dog (message "ri-ruby-complete-method %s" cmd))
	 (result (ri-ruby-process-get-expr cmd str)))
    (if (and pred (listp result))
	(setq result (mapcar pred result)))
    result))

(defun ri-ruby-read-keyw ()
  (let* ((curr (current-word))
	 (match (ri-ruby-process-get-expr "LAMBDA" curr))
	 (default (if match curr nil))
	 (prompt (concat "method- or classname"
			 (if default (concat " (default " default ")") "")
			 ": "))
	 (keyw (completing-read prompt 'ri-ruby-complete-method
				nil t "" 'ri-ruby-history default))
	 (classes (ri-ruby-process-get-expr "CLASS_LIST" keyw))
	 (class (cond ((null classes) nil)
		      ((null (cdr classes)) (caar classes))
		      (t (completing-read (concat prompt keyw
						  " classname: ")
					  classes nil t)))))
    (list keyw class)))

(defun ri-ruby-method-with-class (meth classes)
  (if (null classes)
      meth
    (concat meth " [" (mapconcat 'car classes ", ") "]")))

(defun ri-ruby-complete-symbol ()
  "Completion on ruby-mode."
  (interactive)
  (let* ((curr (current-word))
         (keyw curr)
 	 (classes (ri-ruby-process-get-expr "CLASS_LIST_WITH_FLAG" keyw))
         (completion (try-completion curr 'ri-ruby-complete-method nil)))
    (cond ((eq completion t)
           (message "%s" (ri-ruby-method-with-class curr classes)))
	  ((null completion)
	   (message "Can't find completion for \"%s\"" curr)
	   (ding))
	  ((not (string= curr completion))
	   (delete-region (save-excursion (search-backward curr) (point))
                          (point))
	   (insert completion)
           (setq classes (ri-ruby-process-get-expr "CLASS_LIST_WITH_FLAG" completion))
           (message "%s" (ri-ruby-method-with-class completion classes)))
	  (t
	   (message "Making completion list...")
	   (with-output-to-temp-buffer "*Completions*"
 	     (display-completion-list
              (all-completions curr 'ri-ruby-complete-method)))
           (message "%s" (ri-ruby-method-with-class completion classes))))))

(defun test-ri-ruby-complete-symbol ()
  "Test of ri-ruby-complete-symbol."
  (interactive)
  (pop-to-buffer "*ruby completion test*")
  (ruby-mode)
  (erase-buffer)
  (goto-char (point-min))
  (insert "prin
object_id
intern
printf
# (kill-process \"ri-ruby-process\")
"))

(defun ri-ruby-show-args ()
  (interactive)
  (let* ((method (current-word))
         (info (ri-ruby-process-get-lines "DISPLAY_ARGS" method)))
    (when info
      (message "%s" info))))

;;;###autoload
(defun ri (keyw &optional class)
  "Execute `ri'."
  (interactive (ri-ruby-read-keyw))
  (let* ((method (if class (concat class "#" keyw) keyw))
	(info (ri-ruby-process-get-lines "DISPLAY_INFO" method)))
    (cond (info (ri-ruby-show-info method info))
	  ((null class))
	  (t (setq method (concat class "::" keyw))
	     (setq info (ri-ruby-process-get-lines "DISPLAY_INFO" method))
	     (if info (ri-ruby-show-info method info))))))

(defgroup ri-emacs nil
  "ri-emacs commands for users and programmers."
  :group 'help
  :prefix "ri-emacs")

(defcustom ri-emacs-method-face 'underline
  "*Face for method name in ri output, or nil for none."
  :group 'ri-emacs
  :type 'face)

(defun ri-display (string)
  (let ((info (ri-ruby-process-get-lines "DISPLAY_INFO" string)))
    (if info (ri-ruby-show-info string info)
      (message (format "No ri for %s" string)))))

(define-button-type 'ri-method
  'help-echo "mouse-2, RET: Display ri help on this method"
  'follow-link t
  'action (lambda (button)
	    (ri-display (button-get button 'ri-method))))

(defun ri-find-buttons ( )
  (goto-char (point-min))
  ;; The types of pages I know of so far is an instance method or a
  ;; class method.  In those cases, we find the class in the first
  ;; line and make a button for it.  The other searches are going to
  ;; fail.
  ;;
  ;; The other type of page I know of is a Module or a Class (which I
  ;; treat the same so far).  In this case, I want to make a button
  ;; for the subclass so we can easily walk up the tree.  I also need
  ;; to save off the original class or module.
  ;;
  ;; For Class and Module pages, we continue to scan down the page
  ;; looking for Includes, Class methods: and Instance Methods making
  ;; buttons for each of the entries under each of those sections.
  ;;
  ;; For the class and instance methods, the class or module that the
  ;; page is displaying has to be prepended to the method name with
  ;; either a "::" or a "#" in between.
  ;;
  ;; Ruby 1.9 formats the page different.  The first line is all -'s.
  ;; The second line has what use to be at the end of the first line
  (let* ((bol (progn
		(if (looking-at "^-+$")
		    (forward-line 1))
		(point)))
	 (eol (progn (forward-line 1) (point)))
	 (includes-start (re-search-forward "^Includes:" nil t))
	 (class-start  (re-search-forward "^Class methods:" nil t))
	 (instance-start (re-search-forward "^Instance methods:" nil t))
	 (page-end (point-max))
	 (class nil)
	 (parent-class nil)
	 (base-class nil)
	 (method nil)
	 search-end)
    (goto-char bol)
    ;; Not parsing the base class "< Foo" string yet
    (if (re-search-forward
	 " ?\\(\\(Module\\|Class\\): \\)?\\(\\(\\(\\([^#: ]+\\)\\(::\\|#\\)\\)*\\)\\([^: ]+\\)\\)\\( < \\([^ \r\n\t]+\\)\\)?[ \r\t\n]*$"
	 eol t)
	(progn
	  (if t
	      (progn
		;; "Class: " or "Module: " if present 
		(and ri-debug (message (format "match  1: '%s'" (match-string 1))))
		;; "Class" or "Module"
		(and ri-debug (message (format "match  2: '%s'" (match-string 2))))
		;; entire class, module, or method string
		(and ri-debug (message (format "match  3: '%s'" (match-string 3))))
		;; #3 with final segment removed but the # or :: still
		;; attached
		(and ri-debug (message (format "match  4: '%s'" (match-string 4))))
		;; The piece of the A::B::C:: string.  This is not
		;; useful that I can see.
		(and ri-debug (message (format "match  5: '%s'" (match-string 5))))
		;; #4 but with the :: or # removed
		(and ri-debug (message (format "match  6: '%s'" (match-string 6))))
		;; The final :: or #
		(and ri-debug (message (format "match  7: '%s'" (match-string 7))))
		;; The method name if a method was looked up.  If a
		;; class or module was looked up, this is just the
		;; final segment of what was looked up.
		(and ri-debug (message (format "match  8: '%s'" (match-string 8))))
		;; "< base class" if present
		(and ri-debug (message (format "match  9: '%s'" (match-string 9))))
		;; "base class" if present
		(and ri-debug (message (format "match 10: '%s'" (match-string 10))))))
 	  (if (match-string 1)
 	      (progn
 		(and ri-debug (message "have module"))
 		(setq class (match-string 3)))
 	    (and ri-debug (message "do not have module"))
 	    (setq method (match-string 8)))
	  ;; Icky but we need to trim off the last :: or #
	  (if (< (match-beginning 4) (match-end 4))
	      (setq parent-class (buffer-substring (match-beginning 4)
						   (match-beginning 7))))
	  (setq base-class (match-string 10))
	  (and ri-debug (message (format "base-class %s" base-class)))
 	  (and ri-debug (message (format "parent-class %s" parent-class)))
	  ;; Make a button for the parent class if any
	  (if (< (match-beginning 4) (match-end 4))
	      (make-button (match-beginning 4)
			   (match-beginning 7)
			   'type 'ri-method
			   'face ri-emacs-method-face
			   'ri-method parent-class))
	  ;; Make a button for the base class if any
	  (if base-class
	      (make-button (match-beginning 10)
			   (match-end 10)
			   'type 'ri-method
			   'face ri-emacs-method-face
			   'ri-method base-class))
 	  ;; If these match, then it must be a Module or a Class.  So
 	  ;; use the class as the containing class or module
 	  ;; name.
 	  (if includes-start
 	      (progn
 		(goto-char includes-start)
 		(setq search-end (or class-start instance-start page-end))
 		(while (re-search-forward " +\\([^, \n\r\t]+\\)" search-end t)
 		  (make-button (match-beginning 1)
 			       (match-end 1)
 			       'type 'ri-method
 			       'face ri-emacs-method-face
 			       'ri-method (match-string 1)))))
 	  (if class-start
 	      (progn
 		(goto-char class-start)
 		(setq search-end (or instance-start page-end))
 		(while (re-search-forward " +\\([^, \n\r\t]+\\)" search-end t)
 		  (make-button (match-beginning 1)
 			       (match-end 1)
 			       'type 'ri-method
 			       'face ri-emacs-method-face
 			       'ri-method  (concat class "::" (match-string 1))))))
 	  (if instance-start
 	      (progn
 		(goto-char instance-start)
 		(while (re-search-forward " +\\([^, \n\r\t]+\\)" nil t)
 		  (make-button (match-beginning 1)
 			       (match-end 1)
 			       'type 'ri-method
 			       'face ri-emacs-method-face
 			       'ri-method (concat class "#" (match-string 1)))))))
      (and ri-debug (message "total miss")))))


(defun ri-mode ()
  "Mode for viewing RI documentation."
  (kill-all-local-variables)
  (local-set-key (kbd "q") 'quit-window)
  (local-set-key (kbd "RET") 'ri-follow)
  (setq mode-name "RI")
  (setq major-mode 'ri-mode)
  (ri-find-buttons)
  (goto-char 1)
  (setq buffer-read-only t)
  (run-hooks 'ri-mode-hook))

(cond ((fboundp 'with-displaying-help-buffer) ; for XEmacs
       (defun ri-ruby-show-info (method info) 
	 (with-displaying-help-buffer
	  (lambda () (princ info))
	  (format "ri `%s'" method)
          (ri-mode))))
      (t                                ; for Emacs
       (defun ri-ruby-show-info (method info)
         (let ((b (get-buffer-create (format "*ri `%s'*" method))))
           (display-buffer b)
           (with-current-buffer b
	     (setq buffer-read-only nil)
             (buffer-disable-undo)
             (erase-buffer)
             (insert info)
             (goto-char 1)
             (ri-mode)))
         info)))
