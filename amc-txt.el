;;; amc-txt.el --- Major mode for editing auto-multipe-choice txt files  -*- lexical-binding: t; -*-

;; Copyright (C) 2019 Michal Sojka

;; Author: Michal Sojka <michal.sojka@cvut.cz>
;; Keywords: files

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

;; Usage: Put "(require 'amc-txt)" in your Emacs init file and put
;; either "# AMC-TXT" or "# -*- amc-txt -*-" at the first line your
;; AMC-TXT files. If you open an AMC-TXT file without the first
;; special line, you can activate this mode by "M-x amc-txt-mode".

;;; Code:

(defvar amc-txt-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "M-n") 'amc-txt-next-question)
    (define-key map (kbd "M-p") 'amc-txt-prev-question)
    (define-key map (kbd "M-N") 'amc-txt-next-group)
    (define-key map (kbd "M-P") 'amc-txt-prev-group)
    map))

(defconst amc-txt-question-re
  (rx line-start
      (* blank) (group-n 1 (or "*" "**"))
      (optional (group-n 2 "<" (*? any) ">"))
      (optional (group-n 3 "[" (*? any) "]"))
      (optional (group-n 4 "{" (*? any) "}"))
      (* blank) (group-n 5 (* any))))

(defconst amc-txt-group-re
  (rx line-start
      (* blank) "*" (any "(" ")")
      (optional (group-n 1 "[" (*? any) "]"))
      (* blank) (group-n 2 (* any))))

;; verbatim blocks are a bit complex to manage, because other
;; constructs (such as answers) may appear inside, but should be
;; ignored.  In order to ensure that, we:
;;
;;   - put verbatim blocks early in the search-based fontification
;;     rules so that other rules match later and do not override face.
;;
;;   - add amc-txt-font-lock-extend-verbatim to
;;     font-lock-extend-region-functions.
;;
;; There's still the problem of amc-txt-question-re being stopped too
;; early at an answer-like pattern inside a verbatim.

(defun amc-txt-search-verbatim-block (limit)
  "Search for the next verbatim block (search-based fontification)"
  (when (search-forward "[verbatim]" limit t)
    (let ((b (point)))
      (when (search-forward "[/verbatim]" limit t)
	(set-match-data (list b (match-beginning 0)))
	(point)))))

(defconst amc-txt-multiline-boundary-re
  (rx (or (seq line-start (* blank) (any "-+*#"))
	  buffer-end)))

(defun amc-txt-answer-re (type)
  "Return regular expression matching an answer.
TYPE is a string representing a set of charcters to distinguish
type of answer to match.  When '+', it matches correct answer,
when '-', incorrect answer, when '+-', it matches both."
  (rx-to-string `(seq line-start (* blank) (any ,type)
		      (optional (group-n 1 "[" (*? any) "]"))
		      (optional (group-n 2 "{" (*? any) "}"))
		      (* blank) (group-n 3 (* any)))))

(defun amc-txt-next (re &optional count)
  "Move to the next RE match.
COUNT specifies how many matches to move."
  (let ((saved (point)))
    (when (and
	   (looking-at-p re)
	   (or (eq count nil) (> count 0)))
      (forward-line 1))
    (if (re-search-forward re nil t count)
	(goto-char (match-beginning 0))
      (goto-char saved))))

(defun amc-txt-next-group (&optional count)
  "Move point to the begining of a next group.
Optional argument COUNT indicates how many groups to move.
Value nil is the same as 1."
  (interactive)
  (amc-txt-next amc-txt-group-re count))

(defun amc-txt-prev-group ()
  "Move point to the begining of the previous group."
  (interactive)
  (amc-txt-next-group -1))

(defun amc-txt-next-question (&optional count)
  "Move point to the begining of a next question.
Optional argument COUNT indicates how many questions to move.
Value nil is the same as 1."
  (interactive)
  (amc-txt-next amc-txt-question-re count))

(defun amc-txt-prev-question ()
  "Move point to the begining of the previous question."
  (interactive)
  (amc-txt-next-question -1))

(defun amc-txt-font-lock-extend-region ()
  "Move fontification boundaries to beginning of multiline constructs."
  (let ((changed nil))
    (goto-char font-lock-beg)
    (re-search-backward amc-txt-multiline-boundary-re nil t)
    (unless (eq font-lock-beg (point))
      (setq changed t font-lock-beg (point)))
    (goto-char font-lock-end)
    (re-search-forward amc-txt-multiline-boundary-re nil t)
    (unless (eq font-lock-end (match-beginning 0))
      (setq changed t font-lock-end (match-beginning 0)))
    changed))

(defun amc-txt-font-lock-extend-verbatim ()
  "Move fontification boundaries for verbatim construct."
  (goto-char font-lock-beg)
  (when (equal (get-text-property (point) 'face) 'amc-txt-verbatim)
    (setq font-lock-beg (min font-lock-beg (search-backward "[verbatim]"))
	  font-lock-end (max font-lock-end (search-forward "[/verbatim]")))
    t))

(defun amc-txt-font-lock-search (regex-start limit &optional invisible-groups)
  "Search for (potentionally multi-line) construct of AMC-TXT
syntax starting at match of REGEX-START and ending before start
of the next group, question or answer. The search is limited by
LIMIT. INVISIBLE-GROUPS is a list of matched groups that should
be made optionally invisible."
  (when (re-search-forward regex-start limit t)
    (when invisible-groups
      (remove-text-properties (match-beginning 0) (match-end 0) '(invisible nil))
      (dolist (group invisible-groups)
	(when (match-beginning group)
	  (put-text-property (match-beginning group) (match-end group) 'invisible 'amc-txt-option))))
    (let* ((qstart (match-beginning 0))
	   (qend (if (re-search-forward amc-txt-multiline-boundary-re limit t)
		     (match-beginning 0)
		   limit)))
      (goto-char qstart)
      (re-search-forward (concat regex-start (rx (group-n 99 (* anything)))) qend))))

(defun amc-txt-search-question (limit)
  "Search for question for fontification purposes."
  (catch 'found
    (while (amc-txt-font-lock-search amc-txt-question-re limit '(2 3 4))
      ;; Since the amc-txt-question-re can match the same text as
      ;; amc-txt-group-re, we return t only if we don't simultaneously
      ;; match a group. Without that, extra text after the group
      ;; start/end is highlighted as a question body.
      (unless (save-excursion (goto-char (match-beginning 0))
                              (looking-at-p amc-txt-group-re))
        (throw 'found t)))))

(defun amc-txt-search-answer-pos (limit)
  "Search for answer for fontification purposes."
  (amc-txt-font-lock-search (amc-txt-answer-re "+")  limit))

(defun amc-txt-search-answer-neg (limit)
  "Search for answer for fontification purposes."
  (amc-txt-font-lock-search (amc-txt-answer-re "-")  limit))

(defun amc-txt-toggle-hide-options ()
  "Toggle whether the question options are hidden or not."
  (interactive)
  (let* ((spec '(amc-txt-option . t))
	 (hidden (and (listp buffer-invisibility-spec)
		      (member spec buffer-invisibility-spec))))
    (funcall (if hidden 'remove-from-invisibility-spec 'add-to-invisibility-spec) spec)))

(defgroup amc-txt-mode ()
  "Major mode for editing AMC-TXT files."
  :group 'text)


(defface amc-txt-group
  '((((class color)) :foreground "DimGray"))
  "AMC group"
  :group 'amc-txt-mode)

(defface amc-txt-options
  '((((class color)) :foreground "DarkGray"))
  "AMC group, question or answer options"
  :group 'amc-txt-mode)

(defface amc-txt-question
  '((((class color) (min-colors 88) (background light)) :foreground "Black")
    (((class color) (min-colors 8)) :foreground "black"))
  "AMC question"
  :group 'amc-txt-mode)

(defface amc-txt-question-heading
  '((((class color) (min-colors 88) (background light)) :foreground "Blue1")
    (((class color) (min-colors 8)) :foreground "blue" :weight bold)
    (t :inverse-video t :weight bold))
  "AMC question heading"
  :group 'amc-txt-mode)

(defface amc-txt-correct
  '((((class color)) :foreground "DarkGreen"))
  "AMC correct answer"
  :group 'amc-txt-mode)

(defface amc-txt-wrong
  '((((class color)) :foreground "DarkRed"))
  "AMC wrong answer"
  :group 'amc-txt-mode)

(defface amc-txt-verbatim
  '((t :inherit shadow))
  "AMC verbatim block"
  :group 'amc-txt-mode)


(defmacro amc-txt-markup (start end &rest rest)
  "Helper macro for markup fontification."
  `(cons (rx (group-n 1 ,start) (group-n 3 (*? any))  (group-n 2 ,end))
	 '((1 'amc-txt-options t)
	   (2 'amc-txt-options t)
	   (3 ,@rest))))

(defvar amc-txt-mode-font-lock-keywords)
(setq amc-txt-mode-font-lock-keywords
      `(("^\s*#.*" . font-lock-comment-face)
	("^\s*\\(IncludeFile\\):\s*\\(.*\\)" . ((1 font-lock-keyword-face) (2 font-lock-string-face)))
	(,(rx line-start (* blank)
	      (group (or "Title" "Presentation" "Code" "Lang" "Font" "BoxColor"
			 "PaperSize" "AnswerSheetTitle" "AnswerSheetPresentation"
			 "AnswerSheetColumns" "CompleteMulti" "SeparateAnswerSheet"
			 "AutoMarks" "DefaultScoringM" "DefaultScoringS" "L-Question"
			 "L-None" "L-Name" "L-Student" "LaTeX" "LaTeX-Preambule"
			 "LaTeX-BeginDocument" "LaTeXEngine" "xltxtra" "ShuffleQuestions"
			 "Columns" "QuestionBlocks" "Arabic" "ArabicFont" "Disable"
			 "ManualDuplex" "SingleSided" "L-OpenText" "L-OpenReserved"
			 "CodeDigitsDirection" "PackageOptions" "NameFieldWidth"
			 "NameFieldLines" "NameFieldLinespace" "TitleWidth" "Pages"
			 "RandomSeed" "ShowGroupText")) ":" (* any))
	 . (1 font-lock-variable-name-face))
	("^\\([a-z0-9-]+\\):" . font-lock-warning-face) ; Invalid option
	(,amc-txt-group-re
	 . ((0 'amc-txt-group)
	    (1 'amc-txt-options t t)))
	(amc-txt-search-verbatim-block
	 . ((0 'amc-txt-verbatim t)))
	(amc-txt-search-question
	 . ((1 'amc-txt-question-heading)
	    (2 'amc-txt-options nil t)
	    (3 'amc-txt-options nil t)
	    (4 'amc-txt-options nil t)
	    (5 'amc-txt-question-heading)
            (99 'amc-txt-question keep))) ; see amc-txt-font-lock-search
	(amc-txt-search-answer-pos
	 . ((0 'amc-txt-correct)
	    (1 'amc-txt-options t t)
	    (2 'amc-txt-options t t)))
	(amc-txt-search-answer-neg
	 . ((0 'amc-txt-wrong)
	    (1 'amc-txt-options t t)
	    (2 'amc-txt-options t t)))
	(,(rx "[" (? "/") "verbatim" "]")
	 . (0 'amc-txt-options t))
	,(amc-txt-markup "[[" "]]" font-lock-keyword-face t)
	,(amc-txt-markup "[*" "*]" 'bold prepend)
	,(amc-txt-markup "[/" "/]" 'underline prepend)
	,(amc-txt-markup "[_" "_]" 'italic prepend)
	,(amc-txt-markup "[|" "|]" font-lock-variable-name-face prepend)
	,(amc-txt-markup "[==" "==]" '(t . (:height 1.5)) append)
	;; TODO: Follow
	))

(defun amc-txt-outline-level ()
  "Calculate outline level."
  (cond
   ((looking-at-p amc-txt-group-re) 1)
   ((looking-at-p amc-txt-question-re) 2)
   ((looking-at-p (amc-txt-answer-re "+-")) 3)))

;;;###autoload
(define-derived-mode amc-txt-mode text-mode "AMC-TXT"
  "Major mode for editing auto-multipe-choice plain text files
\\{text-mode-map}"
  (setq-local font-lock-defaults '(amc-txt-mode-font-lock-keywords t t))
  (setq-local comment-start "# ")
  (setq-local comment-end "")
  (setq-local outline-regexp "^\\*")
  (setq-local outline-level 'amc-txt-outline-level)
  (set 'buffer-invisibility-spec nil)
  ;; Set boundaries for fill-paragraph
  (setq-local paragraph-start "\f\\|^[-*+]\\|\\[/?verbatim]\\|[ \t]*$")
  (setq-local paragraph-separate "\\[/?verbatim]\\|[ \t\f]*$")

  ;; Add '+' to and remove some other characters from default value of adaptive-fill-regexp
  (setq-local adaptive-fill-regexp "[ \t]*\\([-+–#*·•‣⁃◦]+[ \t]*\\)*")

  (add-to-list 'font-lock-extend-region-functions 'amc-txt-font-lock-extend-verbatim)
  (add-to-list 'font-lock-extend-region-functions 'amc-txt-font-lock-extend-region))

;;;###autoload
(add-to-list 'magic-mode-alist
	     `(,(concat ".*" (regexp-opt '("AMC-TXT" "AMC::Filter"))) . amc-txt-mode))

(provide 'amc-txt)
;;; amc-txt.el ends here

;; Local Variables:
;; mode: emacs-lisp
;; End:
