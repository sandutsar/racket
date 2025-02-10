#lang racket/base
(require "wrap.rkt"
         "match.rkt"
         "known.rkt"
         "struct-type-info.rkt"
         "optimize.rkt"
         "infer-known.rkt"
         "unwrap-let.rkt"
         "lambda.rkt"
         "aim.rkt")

(provide find-definitions)

;; Record top-level functions and structure types, and returns
;;  (values knowns struct-type-info-or-#f)
(define (find-definitions v prim-knowns knowns imports mutated simples unsafe-mode? target
                          #:primitives [primitives #hasheq()] ; for `optimize?` mode
                          #:optimize? optimize?
                          #:compiler-query [compiler-query (lambda (v) #f)])
  (define (nothing) (values knowns #f))
  (match v
    [`(define-values ,ids ,rhs)
     (define new-rhs (unwrap-let rhs))
     (define (maybe-immediate-values)
       (define rhss
         (match new-rhs
           [`(values ,rhss ...) rhss]
           [`,_ (list new-rhs)]))
       (cond
         [(eqv? (length ids) (length rhss))
          (define cross-module-inline? (find-cross-module-inline? v))
          (values
           (for/fold ([knowns knowns]) ([id (in-list ids)]
                                        [rhs (in-list rhss)])
             (find-one-definition id rhs
                                  prim-knowns knowns imports mutated simples unsafe-mode? target
                                  #:primitives primitives
                                  #:optimize? optimize?
                                  #:compiler-query compiler-query
                                  #:cross-module-inline? cross-module-inline?))
           #f)]
         [else (nothing)]))
     (match `(,ids ,new-rhs)
       [`((,struct:s ,make-s ,s? ,acc/muts ...) ; pattern from `struct` or `define-struct`
          (let-values (((,struct: ,make ,? ,-ref ,-set!) ,rhs))
            (values ,struct:2
                    ,make2
                    ,?2
                    ,make-acc/muts ...)))
        (define info (and (wrap-eq? struct: struct:2)
                          (wrap-eq? make make2)
                          (wrap-eq? ? ?2)
                          (make-struct-type-info rhs prim-knowns knowns imports mutated)))
        (cond
          [info
           (define type (string->uninterned-symbol (symbol->string (unwrap make-s))))
           (let* ([knowns (hash-set knowns
                                    (unwrap make-s)
                                    (if (struct-type-info-pure-constructor? info)
                                        (known-struct-constructor (arithmetic-shift 1 (struct-type-info-field-count info)) type struct:s)
                                        a-known-constant))]
                  [authentic? (struct-type-info-authentic? info)]
                  [sealed? (struct-type-info-sealed? info)]
                  [knowns (hash-set knowns
                                    (unwrap s?)
                                    (known-struct-predicate 2 type struct:s authentic? sealed?))]
                  [knowns
                   (let* ([immediate-count (struct-type-info-immediate-field-count info)]
                          [parent-count (- (struct-type-info-field-count info)
                                           immediate-count)])
                     (define (ok-contract-expr? ctc)
                       (match ctc
                         [`(quote ,ctc) (or (string? ctc) (symbol? ctc) (not ctc))]
                         [`,_ (or (string? ctc) (not ctc))]))
                     (define (ok-error-config? more)
                       (match more
                         [`() #t]
                         [`(,ctc) (ok-contract-expr? ctc)]
                         [`(,ctc (quote ,realm)) (and (ok-contract-expr? ctc)
                                                      (symbol? realm))]
                         [`,_ #f]))
                     (for/fold ([knowns knowns]) ([id (in-list acc/muts)]
                                                  [maker (in-list make-acc/muts)])
                       (match maker
                         [`(,make ,ref-or-set ,pos (quote ,name) . ,more)
                          (or (and (ok-error-config? more)
                                   (exact-nonnegative-integer? pos)
                                   (pos . < . immediate-count)
                                   (symbol? name)
                                   (cond
                                     [(and (wrap-eq? make 'make-struct-field-accessor)
                                           (wrap-eq? ref-or-set -ref))
                                      (define immutable? (memv pos (or (struct-type-info-prefab-immutables info)
                                                                       (struct-type-info-non-prefab-immutables info)
                                                                       '())))
                                      (hash-set knowns (unwrap id) (known-field-accessor 2 type struct:s authentic? (+ parent-count pos)
                                                                                         immutable?))]
                                     [(and (wrap-eq? make 'make-struct-field-mutator)
                                           (wrap-eq? ref-or-set -set!))
                                      (hash-set knowns (unwrap id) (known-field-mutator 4 type struct:s authentic? (+ parent-count pos)))]
                                     [else knowns]))
                              knowns)]
                         [`,_ knowns])))])
             (values
              (hash-set knowns (unwrap struct:s) (known-struct-type type
                                                                    (struct-type-info-field-count info)
                                                                    (struct-type-info-pure-constructor? info)
                                                                    (struct-type-info-sealed? info)))
              info))]
          [else (nothing)])]
       [`((,struct:s ,make-s ,s? ,s-ref ,s-set!) ,rhs)
        (define info (make-struct-type-info rhs prim-knowns knowns imports mutated))
        (cond
          [info
           (define type (string->uninterned-symbol (symbol->string (unwrap make-s))))
           (values
            (let* ([knowns (hash-set knowns
                                     (unwrap make-s)
                                     (if (struct-type-info-pure-constructor? info)
                                         (known-constructor (arithmetic-shift 1 (struct-type-info-field-count info)) type)
                                         a-known-constant))]
                   [knowns (hash-set knowns
                                     (unwrap s?)
                                     (known-struct-predicate 2 type struct:s
                                                             (struct-type-info-authentic? info)
                                                             (struct-type-info-sealed? info)))])
              ;; For now, we don't try to track the position-consuming accessor or mutator
              (hash-set knowns (unwrap struct:s) (known-struct-type type
                                                                    (struct-type-info-field-count info)
                                                                    (struct-type-info-pure-constructor? info)
                                                                    (struct-type-info-sealed? info))))
            info)]
          [else (maybe-immediate-values)])]
       [`((,prop:s ,s? ,s-ref) (make-struct-type-property ,_ . ,rest))
        (define type (string->uninterned-symbol (symbol->string (unwrap prop:s))))
        (values
         (let* ([knowns (hash-set knowns (unwrap s-ref) (known-accessor 2 type))]
                [knowns (hash-set knowns (unwrap s?) (known-predicate 2 type))])
           ;; Check whether the property type has an immediate (or no) guard:
           (cond
             [(or (null? (unwrap rest))
                  (and (not (wrap-car rest))
                       (null? (unwrap (wrap-cdr rest)))))
              (hash-set knowns (unwrap prop:s) (known-struct-type-property/immediate-guard))]
             [else knowns]))
         #f)]
       [`,_ (maybe-immediate-values)])]
    [`,_ (nothing)]))

;; ----------------------------------------

(define (find-one-definition id rhs
                             prim-knowns knowns imports mutated simples unsafe-mode? target
                             #:primitives primitives
                             #:optimize? optimize?
                             #:compiler-query compiler-query
                             #:cross-module-inline? cross-module-inline?)
  (define new-rhs
    (if optimize?
        (let ([rhs (unwrap-let rhs)])
          (if (and (not (aim? target 'system)) ; more optimization matters in a cross-module context
                   (lambda? rhs))
              (optimize* rhs prim-knowns primitives knowns imports mutated unsafe-mode? target compiler-query)
              (optimize rhs prim-knowns primitives knowns imports mutated target compiler-query)))
        rhs))
  (define k
    (infer-known new-rhs id knowns prim-knowns imports mutated simples unsafe-mode? target
                 #:compiler-query compiler-query
                 #:defn (or (and cross-module-inline? 'inline) #t)))
  (if k
      (hash-set knowns (unwrap id) k)
      knowns))

(define (find-cross-module-inline? defn)
  (wrap-property defn 'compiler-hint:cross-module-inline))
