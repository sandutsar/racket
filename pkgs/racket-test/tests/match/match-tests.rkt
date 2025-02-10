(module match-tests racket/base
  (require racket/match rackunit
           (for-syntax racket/base))
  
  (provide match-tests)

  (define regexp-tests
    (test-suite "Tests for regexp and pregexp"
      (test-case "regexp"
        ;; string
        (check-false
         (match "banana"
           [(regexp "(na){2}") #t]
           [_ #f]))
        ;; #rx
        (check-false
         (match "banana"
           [(regexp #rx"(na){2}") #t]
           [_ #f]))
        ;; #px
        (check-true
         (match "banana"
           [(regexp #px"(na){2}") #t]
           [_ #f]))
        ;; byte string
        (check-false
         (match #"banana"
           [(regexp #"(na){2}") #t]
           [_ #f]))
        ;; #rx#
        (check-false
         (match #"banana"
           [(regexp #rx#"(na){2}") #t]
           [_ #f]))
        ;; #px#
        (check-true
         (match #"banana"
           [(regexp #px#"(na){2}") #t]
           [_ #f])))

      (test-case "regexp side-effect"
        (define cnt 0)

        (check-true
         (match "banana"
           [(regexp (begin (set! cnt (add1 cnt)) "nan")) #t]
           [_ #f]))
        (check-equal? cnt 1)

        (check-false
         (match "banana"
           [(regexp (begin (set! cnt (add1 cnt)) "inf")) #t]
           [_ #f]))
        (check-equal? cnt 2))

      (test-case "pregexp"
        ;; string
        (check-true
         (match "banana"
           [(pregexp "(na){2}") #t]
           [_ #f]))
        ;; #rx
        (check-exn exn:fail:contract?
                   (λ ()
                     (match "banana"
                       [(pregexp #rx"(na){2}") #t]
                       [_ #f])))
        ;; #px
        (check-true
         (match "banana"
           [(pregexp #px"(na){2}") #t]
           [_ #f]))
        ;; byte string
        (check-true
         (match #"banana"
           [(pregexp #"(na){2}") #t]
           [_ #f]))
        ;; #rx#
        (check-exn exn:fail:contract?
                   (λ ()
                     (match #"banana"
                       [(pregexp #rx#"(na){2}") #t]
                       [_ #f])))
        ;; #px#
        (check-true
         (match #"banana"
           [(pregexp #px#"(na){2}") #t]
           [_ #f])))

      (test-case "pregexp side-effect"
        (define cnt 0)

        (check-true
         (match "banana"
           [(pregexp (begin (set! cnt (add1 cnt)) "nan")) #t]
           [_ #f]))
        (check-equal? cnt 1)

        (check-false
         (match "banana"
           [(pregexp (begin (set! cnt (add1 cnt)) "inf")) #t]
           [_ #f]))
        (check-equal? cnt 2))))

  (define option-tests
    (test-suite "Tests for clause options"
      (test-case "#:do and #:when"
        (define (f xs)
          (match xs
            [(list a b)
             #:do [(define sum (+ a b))
                   (define sum^2 (* sum sum))]
             #:when (< sum^2 50)
             #:do [(define sum^2+1 (add1 sum^2))]
             sum^2+1]
            [_ 'no-match]))

        (check-equal? (f (list 3 4)) 50)
        (check-equal? (f (list 4 4)) 'no-match))

      (test-case "=> scope"
        (define (f xs)
          (match xs
            [(list a b)
             (=> exit)
             #:do [(when (= a b)
                     (exit))]
             a]
            [_ 'no-match]))

        (check-equal? (f (list 5 5)) 'no-match)
        (check-equal? (f (list 5 6)) 5))

      (test-case "define/match"
        (define/match (f xs)
          [((list a b))
           #:do [(define sum (+ a b))
                 (define sum^2 (* sum sum))]
           #:when (< sum^2 50)
           #:do [(define sum^2+1 (add1 sum^2))]
           sum^2+1]
          [(_) 'no-match])

        (check-equal? (f (list 3 4)) 50)
        (check-equal? (f (list 4 4)) 'no-match))

      (test-case "match*"
        (define (f xs)
          (match* (xs)
            [((list a b))
             #:do [(define sum (+ a b))
                   (define sum^2 (* sum sum))]
             #:when (< sum^2 50)
             #:do [(define sum^2+1 (add1 sum^2))]
             sum^2+1]
            [(_) 'no-match]))

        (check-equal? (f (list 3 4)) 50)
        (check-equal? (f (list 4 4)) 'no-match))))
  
  (define match-expander-tests
    (test-suite
     "Tests for define-match-expander"
     (test-case "Trivial expander"
                     (let ()
                       (define-match-expander bar
                         (lambda (x) #'_)
                         (lambda (stx)
                           (syntax-case stx ()
                             [(_ x ...) #'(+ x ...)]
                             [_
                              (identifier? stx)
                              #'+])))
                       (check = 4 (match 3 [(app add1 x) x])) ; other stuff still works
                       (check-true (match 3 [(bar) #t])) ; (bar) matches anything
                       (check = 12 (bar 3 4 5))
                       (check = 12 (apply bar '(3 4 5))))) ; bar works like +     
     ))
  
 
  
  (define simple-tests 
    (test-suite
     "Some Simple Tests"
     (test-case "Trivial"
                     (check = 3 (match 3 [x x])))
     (test-case "app pattern"
                     (check = 4 (match 3 [(app add1 y) y])))
     (test-case "struct patterns"
                     (let ()
                       (define-struct point (x y))
                       (define (origin? pt)
                         (match pt
                           ((struct point (0 0)) #t)
                           (_ #f)))
                       (check-true (origin? (make-point 0 0)))
                       (check-false (origin? (make-point 1 1)))))
     (test-case "empty hash-table pattern bug"
       (check-equal? (match #hash((1 . 2))
                       [(hash-table) "empty"]
                       [_ "non-empty"])
                     "non-empty")
       (check-equal? (match #hash()
                       [(hash-table) "empty"]
                       [_ "non-empty"])
                     "empty"))
     ))
  
  (define nonlinear-tests
    (test-suite 
     "Non-linear patterns"
     (test-case "Very simple"
                     (check = 3 (match '(3 3) [(list a a) a])))
     (test-case "Fails"
                     (check-exn exn:misc:match? (lambda () (match '(3 4) [(list a a) a]))))
     (test-case "Use parameter"
                     (parameterize ([match-equality-test eq?])
                       (check = 5 (match '((3) (3)) [(list a a) a] [_ 5]))))
     (test-case "Uses equal?"
                     (check equal? '(3) (match '((3) (3)) [(list a a) a] [_ 5])))))
    
  
  (define doc-tests
    (test-suite 
     "Tests from Help Desk Documentation"
     (test-case "match-let"
                     (check = 6 (match-let ([(list x y z) (list 1 2 3)]) (+ x y z))))
     #;
     (test-case "set! pattern"
                     (let ()
                       (define x (list 1 (list 2 3)))
                       (match x [(_ (_ (set! setit)))  (setit 4)])
                       (check-equal? x '(1 (2 4)))))
     (test-case "lambda calculus"
                     (let ()
                       (define-struct Lam (args body))
                       (define-struct Var (s))
                       (define-struct Const (n))
                       (define-struct App (fun args))
                       
                       (define parse
                         (match-lambda
                           [(and s (? symbol?) (not 'lambda))
                            (make-Var s)]
                           [(? number? n)
                            (make-Const n)]
                           [(list 'lambda (and args (list (? symbol?) ...) (not (? repeats?))) body)
                            (make-Lam args (parse body))]
                           [(list f args ...)
                            (make-App
                             (parse f)
                             (map parse args))]
                           [x (error 'syntax "invalid expression")]))
                       
                       (define repeats?
                         (lambda (l)
                           (and (not (null? l))
                                (or (memq (car l) (cdr l)) (repeats? (cdr l))))))
                       
                       (define unparse
                         (match-lambda
                           [(struct Var (s)) s]
                           [(struct Const (n)) n]
                           [(struct Lam (args body)) `(lambda ,args ,(unparse body))]
                           [(struct App (f args)) `(,(unparse f) ,@(map unparse args))]))
                       
                       (check equal? '(lambda (x y) x) (unparse (parse '(lambda (x y) x))))))
     
     (test-case "counter : match-define"
                     (let ()
                       (match-define (list inc value reset)
                         (let ([val 0])
                           (list
                            (lambda () (set! val (add1 val)))
                            (lambda () val)
                            (lambda () (set! val 0)))))
                       (inc)
                       (inc)
                       (check =  2 (value))
                       (inc)
                       (check = 3 (value))
                       (reset)
                       (check =  0 (value))))

     ))

  (define match-tests
    (test-suite "Tests for match.rkt"
      regexp-tests
      option-tests
      doc-tests
      simple-tests
      nonlinear-tests
      match-expander-tests))
  )
