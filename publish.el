;;; publish.el --- Build Beamer PDF presentations from Org files -*- lexical-binding: t; -*-

;;; Commentary:

;; This script builds Beamer PDF presentations from Org-mode files using
;; org-beamer and LaTeX.  It's designed to be run both interactively in Emacs
;; and non-interactively as part of a build pipeline (e.g., Makefile, Nix).
;; Usage:
;;
;;   Interactive (from within Emacs):
;;     M-x build-presentation
;;     M-x build-presentation-direct
;;
;;   Non-interactive (command line):
;;     make build                                      # all presentations + index
;;     PRESENTATION=2026/09-se4FP make build           # one presentation, no index
;;     PRESENTATION=2026/09-se4FP emacs --batch --script publish.el
;;
;; Build Requirements:
;;   - Emacs with org-mode and ox-beamer
;;   - LaTeX distribution (TeX Live recommended) with:
;;     * lualatex or pdflatex
;;     * latexmk
;;     * Beamer document class
;;     * biblatex (for bibliography support)
;;   - citeproc-el package (for citation processing)
;;   - [Optional] Nix, but it makes all of the deps above irrelevant.
;;
;; Output:
;;   - PDF file(s) in either $(pwd)/public/ or $(pwd)/result
;;   - LaTeX intermediate files (cleaned up by org-latex-remove-logfiles)

;;; Code:

;; ==========================
;; DEPENDENCIES
;; ==========================

(require 'citeproc)
(require 'find-lisp)
(require 'ox-beamer)
(require 'ox-latex)
(require 'ox-publish)
(require 'seq)

;; ==========================
;; UTILITY FUNCTIONS
;; ==========================

(defun patch-list-with-prefix (prefix strings)
  "Prepend PREFIX to each string in STRINGS list."
  (mapcar (lambda (s) (concat prefix s)) strings))

;; ==========================
;; PATH CONFIGURATION
;; ==========================

(setq workspace-dir (file-name-as-directory (expand-file-name default-directory)))
(setq requested-presentation (getenv "PRESENTATION"))
(when (and requested-presentation (string-empty-p requested-presentation))
  (setq requested-presentation nil))

(defun presentation-directory (path)
  "Resolve PATH relative to `workspace-dir' as a directory name."
  (file-name-as-directory (expand-file-name path workspace-dir)))

(defun presentation-directories ()
  "Return directories below `workspace-dir' that contain a main.org file."
  (let ((files (directory-files-recursively workspace-dir "main\\.org\\'")))
    (sort
     (delete-dups
      (mapcar #'file-name-directory
              (seq-remove
               (lambda (file)
                 (string-match-p
                  "/\\(?:public\\|auto\\|result\\|\\.git\\)/" file))
               files)))
     #'string<)))

;; ==========================
;; LATEX CONFIGURATION
;; ==========================

(setq org-latex-pdf-process
      (list "latexmk -pdflatex='lualatex -shell-escape -interaction nonstopmode' -pdf -f %f"))

;; LaTeX compiler: can be "pdflatex", "lualatex", or "xelatex"
;; Note: This setting may be overridden by org-latex-pdf-process above
(setq org-latex-compiler "lualatex")

;; Automatically remove LaTeX auxiliary files after successful compilation
;; Keeps the build directory clean
(setq org-latex-remove-logfiles t)

;; Extensions of files to remove during cleanup
;; These are intermediate files created during LaTeX compilation
(setq org-latex-logfiles-extensions
      '("aux"
        "bcf"
        "blg"
        "fdb_latexmk"
        "fls"
        "figlist"
        "idx"
        "log"
        "nav"
        "out"
        "ptc"
        "run.xml"
        "snm"
        "toc"
        "vrb"
        "xdv"))

;; ==========================
;; BIBLIOGRAPHY CONFIGURATION
;; ==========================

(setq org-cite-export-processors
      '((latex biblatex)
        (moderncv basic)
        (html csl)
        (t csl)))

;; ==========================
;; BABEL CONFIGURATION
;; ==========================

;; Disable confirmation prompts when evaluating code blocks
(setq org-confirm-babel-evaluate nil)

;; Enable Babel support for various languages
;; Code blocks in these languages can be executed within Org documents
(org-babel-do-load-languages
 'org-babel-load-languages
 '((awk . t)
   (dot . t)
   (emacs-lisp . t)
   (eshell . t)
   (latex . t)
   (org . t)
   (shell . t)))

;; ==========================
;; ORG-PUBLISH CONFIGURATION
;; ==========================

(defun configure-presentation (directory)
  "Configure Org publishing for the presentation in DIRECTORY."
  (setq root-dir (file-name-as-directory (expand-file-name directory)))
  (setq tex-dir (expand-file-name "tex" root-dir))
  (setq public-dir (file-name-as-directory (expand-file-name "public" root-dir)))
  (setq org-cite-global-bibliography
        (let ((bibliography (expand-file-name "references.bib" root-dir)))
          (when (file-exists-p bibliography) (list bibliography))))
  (setq org-publish-project-alist
        `(("beamer-presentation"
           :base-directory ,root-dir
           :base-extension "org"
           :recursive nil
           :publishing-directory ,public-dir
           :publishing-function org-beamer-publish-to-pdf
           :section-numbers nil
           :with-toc nil
           :exclude-tags ("noexport")
           :auto-sitemap nil)))
  (message "SETTING PRESENTATION DIR: %s" root-dir))

;; ==========================
;; BUILD FUNCTIONS
;; ==========================

(defun build-presentation (&optional directory)
  "Build the Beamer presentation in DIRECTORY using org-publish."
  (interactive "DPresentation directory: ")
  (configure-presentation (or directory default-directory))
  (let ((default-directory root-dir)
        (index-path (expand-file-name "index.html" public-dir)))
    (condition-case err
        (progn
          (org-publish-project "beamer-presentation" t)
          ;; A single presentation output is intentionally PDF-only.
          (when (file-exists-p index-path)
            (delete-file index-path))
          (message "✓ Presentation built successfully: %s" root-dir)
          (directory-files public-dir t "\\.pdf\\'"))
      (error
       (message "✗ Error building %s: %s"
                root-dir (error-message-string err))
       ;; In non-interactive mode, exit with error code
       (when noninteractive
         (kill-emacs 1))
       nil))))

(defun build-presentation-direct ()
  "Build presentation directly from the current Org buffer.
The PDF will be created in the same directory as the .org file"
  (interactive)
  (if (derived-mode-p 'org-mode)
      (condition-case err
          (progn
            (org-beamer-export-to-pdf)
            (message "✓ Direct export completed!")
            t)
        (error
         (message "✗ Direct export failed: %s" (error-message-string err))
         (when noninteractive
           (kill-emacs 1))
         nil))
    (message "✗ Not in an org-mode buffer!")
    nil))

;; ==========================
;; FULL BUILD AND WEBSITE
;; ==========================

(defun presentation-link (directory pdf)
  "Return the relative output link for PDF built from DIRECTORY."
  (let ((relative-dir (file-relative-name directory workspace-dir)))
    (if (string= relative-dir "./")
        (file-name-nondirectory pdf)
      (concat (directory-file-name relative-dir) "/"
              (file-name-nondirectory pdf)))))

(defun build-website (output-dir links)
  "Write a minimal list-only index in OUTPUT-DIR for sorted LINKS."
  (let* ((sorted (sort links (lambda (left right) (string> left right))))
         (items (mapconcat
                 (lambda (link)
                   (format "    <li><a href=\"%s\">%s</a></li>" link link))
                 sorted "\n"))
         (index-path (expand-file-name "index.html" output-dir)))
    (with-temp-file index-path
      (insert (concat "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
                      "  <meta charset=\"UTF-8\">\n"
                      "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
                      "  <title>Presentations</title>\n</head>\n<body>\n  <ul>\n"
                      items "\n  </ul>\n</body>\n</html>\n")))
    (message "✓ index.html written to %s (%d PDF(s))" index-path (length links))))

(defun build-all-presentations ()
  "Build every presentation and collect them into the root public directory."
  (let ((staging-dir (make-temp-file "presentations-public-" t))
        (links nil)
        (directories (presentation-directories)))
    (unless directories
      (error "No presentation directories found below %s" workspace-dir))
    (dolist (directory directories)
      (dolist (pdf (build-presentation directory))
        (let* ((link (presentation-link directory pdf))
               (destination (expand-file-name link staging-dir)))
          (make-directory (file-name-directory destination) t)
          (copy-file pdf destination t)
          (push link links))))
    (let ((site-dir (expand-file-name "public" workspace-dir)))
      (when (file-directory-p site-dir)
        (delete-directory site-dir t))
      (copy-directory staging-dir site-dir nil nil t)
      (build-website site-dir links))
    (delete-directory staging-dir t)
    links))

;; ==========================
;; AUTO-EXECUTION
;; ==========================

;; When running as a non-interactive batch script (e.g., from Makefile),
;; automatically trigger the build process
(when noninteractive
  (if requested-presentation
      (build-presentation (presentation-directory requested-presentation))
    (build-all-presentations)))

;;; publish.el ends here
