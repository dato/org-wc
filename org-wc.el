;; org-wc.el
;;
;; Count words in org mode trees.
;; Shows word count per heading line, summed over sub-headings.
;; Aims to be fast, so doesn't check carefully what it's counting.  ;-)
;;
;; Simon Guest, 23/4/11
;;
;; Implementation based on:
;; - Paul Sexton's word count posted on org-mode mailing list 21/2/11.
;; - clock overlays

(defun org-in-heading-line ()
  "Is point in a line starting with `*'?"
  (equal (char-after (point-at-bol)) ?*))

(defun org-word-count (beg end)
  "Report the number of words in the Org mode buffer or selected region."
  (interactive "r")
  (unless mark-active
    (setf beg (point-min)
          end (point-max)))
  (let ((wc (org-word-count-aux beg end)))
    (message (format "%d words in %s." wc
                     (if mark-active "region" "buffer")))))

(defun org-word-count-aux (beg end)
  "Report the number of words in the selected region.
Ignores: heading lines,
         blocks,
         comments,
         drawers.
LaTeX macros are counted as 1 word."

  (let ((wc 0)
        (block-begin-re "^#\\\+BEGIN")
        (block-end-re "^#\\+END")
        (latex-macro-regexp "\\\\[A-Za-z]+\\(\\[[^]]*\\]\\|\\){\\([^}]*\\)}")
        (drawers-re (concat "^[ \t]*:\\("
                            (mapconcat 'regexp-quote org-drawers "\\|")
                            "\\):[ \t]*$"))
        (drawers-end-re "^[ \t]*:END:"))
    (save-excursion
      (goto-char beg)
      (while (< (point) end)
        (cond
         ;; Ignore heading lines.
         ((org-in-heading-line)
          (forward-line))
         ;; Ignore blocks.
         ((looking-at block-begin-re)
          (re-search-forward block-end-re))
         ;; Ignore comments.
         ((org-in-commented-line)
          (forward-line))
         ;; Ignore drawers.
         ((looking-at drawers-re)
          (re-search-forward drawers-end-re nil t))
         ;; Count latex macros as 1 word, ignoring their arguments.
         ((save-excursion
            (backward-char)
            (looking-at latex-macro-regexp))
          (goto-char (match-end 0))
          (setf wc (+ 2 wc)))
         (t
          (progn
            (re-search-forward "\\w+\\W*")
            (incf wc))))))
    wc))

(defun org-wc-count-subtrees ()
  "Count words in each subtree, putting result as the property :org-wc on that
heading."
  (interactive)
  (remove-text-properties (point-min) (point-max)
                          '(:org-wc t))
  (save-excursion
    (goto-char (point-max))
    (while (outline-previous-heading)
      (org-narrow-to-subtree)
      (let ((wc (org-word-count-aux (point-min) (point-max))))
        (put-text-property (point) (point-at-eol) :org-wc wc)
        (goto-char (point-min))
        (widen)))))

(defun org-wc-display (beg end total-only)
  "Show subtree word counts in the entire buffer.
With prefix argument, only show the total wordcount for the buffer or region
in the echo area.

Use \\[org-wc-remove-overlays] to remove the subtree times.

Ignores: heading lines,
         blocks,
         comments,
         drawers.
LaTeX macros are counted as 1 word."
  (interactive "r\nP")
  (org-wc-remove-overlays)
  (unless total-only
    (let (wc p)
      (org-wc-count-subtrees)
      (save-excursion
        (goto-char (point-min))
        (while (or (and (equal (setq p (point)) (point-min))
                        (get-text-property p :org-wc))
                   (setq p (next-single-property-change
                            (point) :org-wc)))
          (goto-char p)
          (when (setq wc (get-text-property p :org-wc))
            (org-wc-put-overlay wc (funcall outline-level))))
        ;; Arrange to remove the overlays upon next change.
        (when org-remove-highlights-with-change
          (org-add-hook 'before-change-functions 'org-wc-remove-overlays
                        nil 'local)))))
  (if mark-active
      (org-word-count beg end)
    (org-word-count (point-min) (point-max))))

(defvar org-wc-overlays nil)
(make-variable-buffer-local 'org-wc-overlays)

(defun org-wc-put-overlay (wc &optional level)
  "Put an overlays on the current line, displaying word count.
If LEVEL is given, prefix word count with a corresponding number of stars.
This creates a new overlay and stores it in `org-wc-overlays', so that it
will be easy to remove."
  (let* ((c 60)
         (l (if level (org-get-valid-level level 0) 0))
         (off 0)
         ov tx)
    (org-move-to-column c)
    (unless (eolp) (skip-chars-backward "^ \t"))
    (skip-chars-backward " \t")
    (setq ov (make-overlay (1- (point)) (point-at-eol))
          tx (concat (buffer-substring (1- (point)) (point))
                     (make-string (+ off (max 0 (- c (current-column)))) ?.)
                     (org-add-props (format "%s" (number-to-string wc))
                         (list 'face 'org-wc-overlay))
                     ""))
    (if (not (featurep 'xemacs))
        (overlay-put ov 'display tx)
      (overlay-put ov 'invisible t)
      (overlay-put ov 'end-glyph (make-glyph tx)))
    (push ov org-wc-overlays)))

(defun org-wc-remove-overlays (&optional beg end noremove)
  "Remove the occur highlights from the buffer.
BEG and END are ignored.  If NOREMOVE is nil, remove this function
from the `before-change-functions' in the current buffer."
  (interactive)
  (unless org-inhibit-highlight-removal
    (mapc 'delete-overlay org-wc-overlays)
    (setq org-wc-overlays nil)
    (unless noremove
      (remove-hook 'before-change-functions
                   'org-wc-remove-overlays 'local))))

(provide 'org-wc)
