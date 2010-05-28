;;; -*- coding: utf-8; mode: emacs-lisp; indent-tabs-mode: nil -*-
;;; hatena-group-keyword-mode.el --- Emacs interface to Hatena Group Keyword Writer

;; Copyright (C) 2009 Hiroshige Umino
;; Author: Hiroshige Umino <yaotti@gmail.com>
;; Keywords: blog, hatena, はてな

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation; either version 2, or (at your
;; option) any later version.

;; This file is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; * hatena-group-keyword-mode.elについて

;; このパッケージは，「はてなグループキーワードライター」をEmacsから使えるよう
;; にし，はてなグループのキーワードを簡単に更新するためのメジャーモー
;; ド，hatena-group-keyword-modeを提供します．hatena-group-keyword-modeは，
;; html-helper-modeの派生モードとして定義されていますので，
;; html-helper-modeが提供する各種機能も利用できます．
;;
;; なお，このプログラムはsimple-hatena-mode.el(http://coderepos.org/share/wiki/SimpleHatenaMode)を参考にさせてもらっています．


;;; Code:

;;;; * Version

(defconst hatena-group-keyword-version "0.16"
  "hatena-group-keyword-mode.elのヴァージョン．")

(defun hatena-group-keyword-version ()
  "hatena-group-keyword-mode.elのヴァージョンを表示する．"
  (interactive)
  (let ((version-string
         (format "hatena-group-keyword-mode-v%s" hatena-group-keyword-version)))
    (if (interactive-p)
        (message "%s" version-string)
      version-string)))

;;;; * ユーザによるカスタマイズが可能な設定

(defgroup hatena-group-keyword nil
  "はてグキーワードライターをEmacsから使うためのメジャーモード")

;; カスタマイズ変数
(defcustom hatena-group-keyword-bin "hgk.pl"
  "*はてグキーワードライターのパスを指定する．"
  :type '(file :must-match t)
  :group 'hatena-group-keyword)

(defcustom hatena-group-keyword-root "~/.hatena/keywords"
  "*はてグキーワードライターのデータを置くディレクトリのルートを指
定する．"
  :type 'directory
  :group 'hatena-group-keyword)

(defcustom hatena-group-keyword-default-id nil
  "*hgk.plで使うデフォルトのはてなidを指定する．
このidを変更するには，hatena-group-keyword-change-default-idを実行する．"
  :type '(restricted-sexp :match-alternatives
                          (stringp 'nil))
  :group 'hatena-group-keyword)

(defcustom hatena-group-keyword-default-group nil
  "*デフォルトグループ名を指定する．"
  :type '(restricted-sexp :match-alternatives
                          (stringp 'nil))
  :group 'hatena-group-keyword)

(defcustom hatena-group-keyword-option-debug-flag nil
  "*はてグキーワードライターを，デバッグモードで実行するか否かを指
定するフラグ．

はてグキーワードライター実行時に，-dオプションとしてわたされ，また，
その場合，実行結果をバッファに表示する．

デバッグモードをオン/オフするには，
hatena-group-keyword-toggle-debug-modeを実行する．"
  :type 'boolean
  :group 'hatena-group-keyword)

(defcustom hatena-group-keyword-option-cookie-flag t
  "*はてグキーワードライターのログインに，cookieを利用するかどうか
を指定するフラグ．

実行時に，-cオプションとして使われる．"
  :type 'boolean
  :group 'hatena-group-keyword)

(defcustom hatena-group-keyword-process-buffer-name "*HatenaGroupKeyword*"
  "はてなキーワードライターを実行するプロセスのバッファ名．"
  :type 'string
  :group 'hatena-group-keyword)

;; キーバインド
(setq hatena-group-keyword-mode-map (make-keymap))

(define-key hatena-group-keyword-mode-map (kbd "C-c C-v") 'hatena-group-keyword-version)
(define-key hatena-group-keyword-mode-map (kbd "C-c C-p") 'hatena-group-keyword-submit)
(define-key hatena-group-keyword-mode-map (kbd "C-c C-i") 'hatena-group-keyword-change-default-id)
(define-key hatena-group-keyword-mode-map (kbd "C-c C-g") 'hatena-group-keyword-change-default-group)
(define-key hatena-group-keyword-mode-map (kbd "C-c C-d") 'hatena-group-keyword-toggle-debug-mode)
(define-key hatena-group-keyword-mode-map (kbd "C-c C-e") 'hatena-group-keyword-exit)

;; フック
(defcustom hatena-group-keyword-mode-hook nil
  "hatena-group-keyword-mode開始時のフック．"
  :type 'hook
  :group 'hatena-group-keyword)
(defcustom hatena-group-keyword-before-submit-hook nil
  "キーワードを投稿する直前のフック"
  :type 'hook
  :group 'hatena-group-keyword)
(defcustom hatena-group-keyword-after-submit-hook nil
  "キーワードを投稿した直後のフック"
  :type 'hook
  :group 'hatena-group-keyword)

;; フォントロック

(defvar hatena-group-keyword-font-lock-keywords nil)
(defvar hatena-group-keyword-slag-face 'hatena-group-keyword-slag-face)
(defvar hatena-group-keyword-subtitle-face 'hatena-group-keyword-subtitle-face)
(defvar hatena-group-keyword-inline-face 'hatena-group-keyword-inline-face)
(defvar hatena-group-keyword-markup-face 'hatena-group-keyword-markup-face)
(defvar hatena-group-keyword-link-face 'hatena-group-keyword-link-face)

(defface hatena-group-keyword-slag-face
  '((((class color) (background light)) (:foreground "IndianRed"))
    (((class color) (background dark)) (:foreground "wheat")))
  "小見出しの*タイムスタンプorスラッグ*部分のフェイス．")

(defface hatena-group-keyword-subtitle-face
  '((((class color) (background light)) (:foreground "DarkOliveGreen"))
    (((class color) (background dark)) (:foreground "wheat")))
  "小見出しのフェイス．")

(defface hatena-group-keyword-inline-face
  '((((class color) (background light)) (:foreground "MediumBlue" :bold t))
    (((class color) (background dark)) (:foreground "wheat" :bold t)))
  "id記法や[keyword:Emacs]等のface")

(defface hatena-group-keyword-markup-face
  '((((class color) (background light)) (:foreground "DarkOrange" :bold t))
    (((class color) (background dark)) (:foreground "IndianRed3" :bold t)))
  "はてなのマークアップのフェイス．")

(defface hatena-group-keyword-link-face
  '((((class color) (background light)) (:foreground "DeepPink"))
    (((class color) (background dark)) (:foreground "wheat")))
  "リンクのフェイス．")

;;;; * 実装

(eval-when-compile
  (require 'cl)
  (require 'derived)
  (require 'font-lock)
  (require 'html-helper-mode))


(defconst hatena-group-keyword-filename-regex
  "/\\([^/]+\\)/\\([^/]+\\)\.txt"
  "キーワードファイルの正規表現．マッチした場合，以下のインデックスによ
りファイル情報を取得できる．

  0. マッチした全体
  1. グループ名
  2. キーワード名")

;; はてなグループ名の正規表現
;; > http://g.hatena.ne.jp/group?mode=append
;; > （アルファベットで始まり，アルファベットか数字で終わる3文字以上，
;; > 24文字以内の半角英数字）
;; と書かれているが「-」も使える．
(defconst hatena-group-keyword-group-regex
  "^[A-z][\-A-z0-9]+[A-z0-9]$"
  "")

;; hatena-group-keyword-modeを，html-helper-modeの派生モードとして定義する．
(define-derived-mode hatena-group-keyword-mode html-helper-mode "Hatena Group Keyword"
  "はてなグループキーワードライターを，Emacsから利用するためのインタフェイ
スを提供するモード．

設定方法や使い方については，以下を参照のこと．
"

  ;; 現在開いているバッファの情報
  (make-local-variable 'hatena-group-keyword-local-current-buffer-info)
  ;;   (make-local-variable 'hatena-group-keyword-local-current-buffer-id)
  ;;   (make-local-variable 'hatena-group-keyword-local-current-buffer-type)
  (make-local-variable 'hatena-group-keyword-local-current-buffer-group)
  ;;   (make-local-variable 'hatena-group-keyword-local-current-buffer-year)
  ;;   (make-local-variable 'hatena-group-keyword-local-current-buffer-month)
  ;;   (make-local-variable 'hatena-group-keyword-local-current-buffer-day)

  (if (string-match hatena-group-keyword-filename-regex (buffer-file-name))
      (progn
        (setq hatena-group-keyword-local-current-buffer-info
              (match-string 0 (buffer-file-name)))
        (setq hatena-group-keyword-local-current-buffer-group
              (match-string 1 (buffer-file-name)))
        (setq hatena-group-keyword-local-current-buffer-keyword
              (match-string 2 (buffer-file-name)))
        (hatena-group-keyword-update-modeline))
    (error "Current buffer isn't related to Hatena::Diary Writer data file"))

  ;; フォントロック
  (font-lock-add-keywords
   'hatena-group-keyword-mode
   (list
    (list  "^\\(\\*[*a-zA-Z0-9_-]*\\)\\(.*\\)$"
           '(1 hatena-group-keyword-slag-face t)
           '(2 hatena-group-keyword-subtitle-face t))
    ;; 必ず[]で囲まれていなければならないもの
    (list "\\[[*a-zA-Z0-9_-]+\\(:[^\n]+\\)+\\]"
          '(0 hatena-group-keyword-inline-face t))
    ;; 必ずしも[]で囲まれていなくてもよいもの
    (list "\\[?\\(id\\|a\\|b\\|d\\|f\\|g\\|graph\\|i\\|idea\\|map\\|question\\|r\\|isbn\\|asin\\)\\(:[a-zA-Z0-9_+:-]+\\)+\\]?"
          '(0 hatena-group-keyword-inline-face t))
    (list  "^\\(:\\)[^:\n]+\\(:\\)"
           '(1 hatena-group-keyword-markup-face t)
           '(2 hatena-group-keyword-markup-face t))
    (list  "^\\([-+]+\\)"
           '(1 hatena-group-keyword-markup-face t))
    (list  "\\(((\\).*\\())\\)"
           '(1 hatena-group-keyword-markup-face t)
           '(2 hatena-group-keyword-markup-face t))
    (list  "^\\(>>\\|<<\\|><!--\\|--><\\|>|?[^|]*|\\||?|<\\|=====?\\)"
           '(1 hatena-group-keyword-markup-face t))
    (list  "\\(s?https?://\[-_.!~*'()a-zA-Z0-9;/?:@&=+$,%#\]+\\)"
           '(1 hatena-group-keyword-link-face t))))
  (font-lock-mode 1)

  (use-local-map hatena-group-keyword-mode-map)
  (run-hooks 'hatena-group-keyword-mode-hook)
  )

;; はてグキーワードライターのデータにhatena-group-keyword-modeを適用する
;;
;; - ~/.hatena/keywords/group-name/KEYWORD.txt
;;
;; というファイルを開いたら，hatena-group-keyword-modeにする
(add-to-list 'auto-mode-alist
             (cons (concat ".hatena/keywords"
                           hatena-group-keyword-filename-regex)
                   'hatena-group-keyword-mode))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 

;;;; * コマンド

(defun hatena-group-keyword (group keyword)
  "指定されたグループ用キーワードファイルを開く．"
  (interactive
   (let* ((group
           (if hatena-group-keyword-default-group
               hatena-group-keyword-default-group
             (hatena-group-keyword-internal-completing-read-group)))
          (keyword
           (hatena-group-keyword-internal-completing-read-keyword group)))
     (list group keyword)))
  (hatena-group-keyword-safe-find-file (expand-file-name
                                        (format "%s/%s/%s"
                                                hatena-group-keyword-root
                                                group
                                                keyword)))
  (hatena-group-keyword-mode)
  )

(defun hatena-group-keyword-change-default-group ()
  "現在のデフォルトグループを変更する．"
  (interactive)
  (setq hatena-group-keyword-default-group
        (hatena-group-keyword-internal-completing-read-group))
  (message "Change current default group to %s"
           hatena-group-keyword-default-group))

(defun hatena-group-keyword-submit ()
  "はてなグループのキーワードを投稿する．"
  (interactive)
  (let ((keyword-file (file-name-nondirectory (buffer-file-name))))
    (hatena-group-keyword-internal-do-submit keyword-file)))

(defun hatena-group-keyword-toggle-debug-mode ()
  "デバッグモードをオン/オフする．"
  (interactive)
  (setq hatena-group-keyword-option-debug-flag
        (not hatena-group-keyword-option-debug-flag))
  (message "%s %s"
           "Debug mode"
           (if hatena-group-keyword-option-debug-flag
               "on" "off")))



;;;; * 内部関数

(defun hatena-group-keyword-safe-find-file (filename)
  "新しいヴァージョンのhtml-helper-modeは，デフォルトでスケルトン
を作ってウザいので，阻止する．"
  (let ((html-helper-build-new-buffer nil))
    (find-file filename)))

(defun hatena-group-keyword-internal-list-directories (dir)
  "dir下にあるディレクトリをリストにして返す。"
  (let ((dir-list nil))
    (dolist (file (directory-files dir t "^[^\.]") dir-list)
      (if (file-directory-p file)
          (progn
            (string-match "\\([^/]+\\)/?$" file)
            (setq dir-list (cons (match-string 1 file) dir-list)))))
    ))

(defun hatena-group-keyword-internal-list-files (dir)
  "dir下にあるファイルを，拡張子を除いてリストにして返す。"
  (let ((dir-list nil))
    (dolist (file (directory-files dir t "^[^\.]") dir-list)
      (if (file-regular-p file)
          (progn
            (string-match "\\([^/]+\\)/?$" file)
            (setq dir-list (cons (match-string 1 file) dir-list)))))
    ))

(defun hatena-group-keyword-internal-completing-read-group ()
  "dir以下からグループ名を抽出し，補完入力させる．"
  (completing-read
   "Group: " (mapcar 'list
                     (hatena-group-keyword-internal-list-directories
                      hatena-group-keyword-root))
   nil t))

(defun hatena-group-keyword-internal-completing-read-keyword (group)
  "dir以下からキーワード名を抽出し，補完入力させる．"
  (let ((new-keyword (read-string "New Keyword (or type return): ")))
    (if (string= new-keyword "")
        (completing-read
         "Existing Keyword: " (mapcar 'list
                                      (hatena-group-keyword-internal-list-files
                                       (concat hatena-group-keyword-root "/" group)))
         nil t)
      (format "%s.txt" new-keyword))))

(defun hatena-group-keyword-internal-do-submit (keyword-file &optional flag)
  "はてなグループへキーワードを投稿する．"
  (let ((max-mini-window-height 10)   ; hgk.plが表示するメッセージを，
                                        ; echoエリアに表示させるため．
        (thisdir (file-name-directory (buffer-file-name)))
        (filename (replace-regexp-in-string "\\([][ *<>]\\)" "\\\\\\1" keyword-file)))
    (message filename)
    (run-hooks 'hatena-group-keyword-before-submit-hook)
    (when (buffer-modified-p)
      (save-buffer))
    (message "%s" "Now posting...")
    (let* ((buffer (get-buffer-create hatena-group-keyword-process-buffer-name))
           (proc (get-buffer-process buffer)))
      (if (and
           proc
           (eq (process-status proc) 'run))
          (if (yes-or-no-p (format "A %s process is running; kill it?"
                                   (process-name proc)))
              (progn
                (interrupt-process proc)
                (sit-for 1)
                (delete-process proc))
            (error nil)))
      (with-current-buffer buffer
        (progn
          (erase-buffer)
          (buffer-disable-undo (current-buffer))
          (setq default-directory thisdir)))
      (make-comint-in-buffer
       "hatena-group-keyword-submit" buffer shell-file-name nil
       shell-command-switch (hatena-group-keyword-internal-build-command filename flag))
      (set-process-sentinel
       (get-buffer-process buffer)
       '(lambda (process signal)
          (if (string= signal "finished\n")
              (let ((max-mini-window-height 10))
                (display-message-or-buffer (process-buffer process))
                (run-hooks 'hatena-group-keyword-after-submit-hook))))))))

(defun hatena-group-keyword-internal-build-command (keyword-file flag)
  "実行可能なコマンド文字列を作成する．"
  (let ((flag-list (list flag)))
    (if hatena-group-keyword-option-debug-flag  (setq flag-list (cons "-d" flag-list)))
    (if hatena-group-keyword-option-cookie-flag (setq flag-list (cons "-c" flag-list)))
    (hatena-group-keyword-internal-join
     " "
     (cons hatena-group-keyword-bin
           (append (hatena-group-keyword-internal-build-option-list-from-alist) flag-list (cons keyword-file nil))
           ))))

(defun hatena-group-keyword-internal-build-option-list-from-alist ()
  "引数を取るオプションのリストを作成する．"
  (let ((opts nil))
    (dolist (pair
             `(("-u" . ,hatena-group-keyword-default-id)
               ("-g" . ,hatena-group-keyword-local-current-buffer-group))
             opts)
      (if (cdr pair)
          (setq opts (append opts (list (car pair) (cdr pair))))))))

(defun hatena-group-keyword-internal-join (sep list)
  "車輪の再発明なんだろうけど，見つからなかったのでjoin実装"
  (if (<= (length list) 1)
      (car list)
    (concat (car list) sep (hatena-group-keyword-internal-join sep (cdr list)))))

(defun hatena-group-keyword-update-modeline ()
  "モードラインの表示を更新する"
  (let ((id
         (concat
          (if hatena-group-keyword-local-current-buffer-group
              (format "g:%s:" hatena-group-keyword-local-current-buffer-group)
            "")
          ;;(format "id:%s" hatena-group-keyword-local-current-buffer-id)
          )))
    (setq mode-name (format "Hatena Group Keyword [%s]" id))
    (force-mode-line-update)))

(provide 'hatena-group-keyword-mode)

;;; hatena-group-keyword-mode.el ends here
