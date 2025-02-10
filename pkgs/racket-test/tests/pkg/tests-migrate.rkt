#lang racket/base
(require racket/file
         racket/format
         "shelly.rkt"
         "util.rkt")

(this-test-is-run-by-the-main-test)

(pkg-tests
 (with-fake-root
  (shelly-case
   "install package, copy to other, remove, then migrate"
   $ "raco pkg config --set catalogs http://localhost:9990"
   (hash-set! *index-ht-1* "pkg-b"
              (hasheq 'checksum
                      (file->string "test-pkgs/pkg-b-second.plt.CHECKSUM")
                      'source
                      "http://localhost:9997/pkg-b-second.plt"))
   (hash-set! *index-ht-1* "pkg-a"
              (hasheq 'checksum
                      (file->string "test-pkgs/pkg-a-first.plt.CHECKSUM")
                      'source
                      "http://localhost:9997/pkg-a-first.plt"))
   $ "raco pkg install -u --deps search-auto pkg-b" =exit> 0
   $ "raco pkg show -l -u -a" =stdout> #rx"Package\\[\\*=auto\\] +Checksum +Source\npkg-a\\* +[a-f0-9.]+    \\(catalog \"pkg-a\"\\)\npkg-b +[a-f0-9.]+ +\\(catalog \"pkg-b\"\\)\n"
   $ (~a "racket"
         " -e \"(require racket/file setup/dirs)\""
         " -e \"(copy-directory/files (build-path (find-system-path 'addon-dir) (get-installation-name))"
         "                            (build-path (find-system-path 'addon-dir) (symbol->string 'other)))\"")
   $ "raco pkg remove -u --auto pkg-b"
   $ "raco pkg show -l -u -a" =stdout> " [none]\n"
   $ "raco pkg migrate --dry-run -u other"
   $ "raco pkg show -l -u -a" =stdout> " [none]\n"
   $ "raco pkg migrate -u other"
   $ "raco pkg show -l -u -a" =stdout> #rx"Package\\[\\*=auto\\] +Checksum +Source\npkg-a\\* +[a-f0-9.]+    \\(catalog \"pkg-a\"\\)\npkg-b +[a-f0-9.]+ +\\(catalog \"pkg-b\"\\)\n"

   ;; Don't promote auto-installed. Our real interest is not having to promote auto-installed
   ;; in a wider scope, but we can partly test that by checking non-promote in user-scope.
   $ "raco pkg remove -u --demote pkg-b"
   $ "raco pkg show -l -u -a" =stdout> #rx"Package\\[\\*=auto\\] +Checksum +Source\npkg-a\\* +[a-f0-9.]+    \\(catalog \"pkg-a\"\\)\npkg-b\\* +[a-f0-9.]+ +\\(catalog \"pkg-b\"\\)\n"
   $ "raco pkg migrate -u other"
   $ "raco pkg show -l -u -a" =stdout> #rx"Package\\[\\*=auto\\] +Checksum +Source\npkg-a\\* +[a-f0-9.]+    \\(catalog \"pkg-a\"\\)\npkg-b\\* +[a-f0-9.]+ +\\(catalog \"pkg-b\"\\)\n"))

 (define git-exe (find-executable-path
                  (if (eq? 'windows (system-type)) "git.exe" "git")))
 (when git-exe
   (with-fake-root
    (shelly-begin
     (initialize-catalogs)

     (shelly-case
      "install from GIT source, copy to other, remove, then migrate"
      $ "raco pkg config --set catalogs http://localhost:9990"
      $ "raco pkg config --set git-checkout-credentials user:password"
      $ (~a "raco pkg install --type git-url -u --name pkg-git-URL "
            (hash-ref (hash-ref *index-ht-1* "pkg-git" ) 'source))
      $ "raco pkg show -l -u -a" =stdout> #rx"Package +Checksum +Source\npkg-git-URL +[a-f0-9.]+    \\(git \"http://localhost[^/]*/pkg-git-[^.]*\\.git\"\\)\n"
      $ (~a "racket"
            " -e \"(require racket/file setup/dirs)\""
            " -e \"(copy-directory/files (build-path (find-system-path 'addon-dir) (get-installation-name))"
            "                            (build-path (find-system-path 'addon-dir) (symbol->string 'other)))\"")
      $ "raco pkg remove -u --auto pkg-git-URL"
      $ "raco pkg show -l -u -a" =stdout> " [none]\n"
      $ "raco pkg migrate --dry-run -u other"
      $ "raco pkg show -l -u -a" =stdout> " [none]\n"
      $ "raco pkg migrate -u other"
      $ "raco pkg show -l -u -a" =stdout> #rx"Package +Checksum +Source\npkg-git-URL +[a-f0-9.]+    \\(git \"http://localhost[^/]*/pkg-git-[^.]*\\.git\"\\)\n"))))

 (with-fake-root
  (shelly-case
   "migrate --auto"
   $ "raco pkg config --set catalogs http://localhost:9990"
   (hash-set! *index-ht-1* "pkg-b"
              (hasheq 'checksum
                      (file->string "test-pkgs/pkg-b-second.plt.CHECKSUM")
                      'source
                      "http://localhost:9997/pkg-b-second.plt"))
   (hash-set! *index-ht-1* "pkg-a"
              (hasheq 'checksum
                      (file->string "test-pkgs/pkg-a-first.plt.CHECKSUM")
                      'source
                      "http://localhost:9997/pkg-a-first.plt"))
   $ "raco pkg install -u --deps search-auto pkg-b" =exit> 0
   $ "raco pkg show -l -u -a" =stdout> #rx"Package\\[\\*=auto\\] +Checksum +Source\npkg-a\\* +[a-f0-9.]+    \\(catalog \"pkg-a\"\\)\npkg-b +[a-f0-9.]+ +\\(catalog \"pkg-b\"\\)\n"
   $ (~a "racket"
         " -e \"(require racket/file setup/dirs)\""
         " -e \"(copy-directory/files (build-path (find-system-path 'addon-dir) (get-installation-name))"
         "                            (build-path (find-system-path 'addon-dir) (symbol->string 'other)))\"")
   $ "raco pkg uninstall -u --auto pkg-b"
   $ "raco pkg show -l -u -a" =stdout> " [none]\n"
   $ "raco pkg migrate --auto -u other"
   $ "raco pkg show -l -u -a" =stdout> #rx"Package\\[\\*=auto\\] +Checksum +Source\npkg-a\\* +[a-f0-9.]+    \\(catalog \"pkg-a\"\\)\npkg-b +[a-f0-9.]+ +\\(catalog \"pkg-b\"\\)\n")))
