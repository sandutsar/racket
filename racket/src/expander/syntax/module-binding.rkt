#lang racket/base
(require "../compile/serialize-property.rkt"
         "../compile/serialize-state.rkt"
         "full-binding.rkt"
         "../common/phase+space.rkt")

(provide make-module-binding
         module-binding-update
         module-binding?
         
         module-binding-module
         module-binding-phase
         module-binding-sym
         module-binding-nominal-module
         module-binding-nominal-phase+space
         module-binding-nominal-sym
         module-binding-nominal-require-phase+space-shift
         module-binding-extra-inspector
         module-binding-extra-nominal-bindings

         module-binding-maybe-intern
         
         deserialize-full-module-binding
         deserialize-simple-module-binding)

;; ----------------------------------------

(define (make-module-binding module phase sym
                             #:nominal-module [nominal-module module]
                             #:nominal-phase+space [nominal-phase+space phase]
                             #:nominal-sym [nominal-sym sym]
                             #:nominal-require-phase+space-shift [nominal-require-phase+space-shift 0]
                             #:frame-id [frame-id #f]
                             #:free=id [free=id #f]
                             #:extra-inspector [extra-inspector #f]
                             #:extra-nominal-bindings [extra-nominal-bindings null])
  (cond
   [(or frame-id
        free=id
        extra-inspector
        (not (and (eqv? nominal-phase+space phase)
                  (eq? nominal-sym sym)
                  (eqv? nominal-require-phase+space-shift 0)
                  (null? extra-nominal-bindings))))
    (full-module-binding frame-id
                         free=id
                         module phase sym
                         nominal-module nominal-phase+space nominal-sym
                         nominal-require-phase+space-shift
                         extra-inspector
                         extra-nominal-bindings)]
   [else
    (simple-module-binding module phase sym nominal-module)]))

(define (module-binding-update b
                               #:module [module (module-binding-module b)]
                               #:phase [phase (module-binding-phase b)]
                               #:sym [sym (module-binding-sym b)]
                               #:nominal-module [nominal-module (module-binding-nominal-module b)]
                               #:nominal-phase+space [nominal-phase+space (module-binding-nominal-phase+space b)]
                               #:nominal-sym [nominal-sym (module-binding-nominal-sym b)]
                               #:nominal-require-phase+space-shift [nominal-require-phase+space-shift (module-binding-nominal-require-phase+space-shift b)]
                               #:frame-id [frame-id (binding-frame-id b)]
                               #:free=id [free=id (binding-free=id b)]
                               #:extra-inspector [extra-inspector (module-binding-extra-inspector b)]
                               #:extra-nominal-bindings [extra-nominal-bindings (module-binding-extra-nominal-bindings b)])
  (make-module-binding module phase sym
                       #:nominal-module nominal-module
                       #:nominal-phase+space nominal-phase+space
                       #:nominal-sym nominal-sym
                       #:nominal-require-phase+space-shift nominal-require-phase+space-shift
                       #:frame-id frame-id
                       #:free=id free=id
                       #:extra-inspector extra-inspector
                       #:extra-nominal-bindings extra-nominal-bindings))

(define (module-binding? b)
  ;; must not overlap with `local-binding?`
  (or (simple-module-binding? b)
      (full-module-binding? b)))

;; See `identifier-binding` docs for information about these fields:
(struct full-module-binding full-binding (module phase sym
                                           nominal-module nominal-phase+space nominal-sym
                                           nominal-require-phase+space-shift
                                           extra-inspector ; preserves access to protected definitions
                                           extra-nominal-bindings)
  #:authentic
  #:transparent
  #:property prop:serialize
  (lambda (b ser-push! state)
    ;; Dropping the frame id may simplify the representation:
    (define simplified-b
      (if (full-binding-frame-id b)
          (module-binding-update b #:frame-id #f)
          b))
    (cond
      [(full-module-binding? simplified-b)
       (ser-push! 'tag '#:module-binding)
       (ser-push! (full-module-binding-module b))
       (define-values (sym phase)
         ((serialize-state-map-binding-symbol state) (full-module-binding-module b)
                                                     (full-module-binding-sym b)
                                                     (full-module-binding-phase b)))
       (ser-push! sym)
       (ser-push! phase)
       (ser-push! (full-module-binding-nominal-module b))
       (ser-push! (full-module-binding-nominal-phase+space b))
       (ser-push! (full-module-binding-nominal-sym b))
       (ser-push! (full-module-binding-nominal-require-phase+space-shift b))
       (ser-push! (full-binding-free=id b))
       (if (full-module-binding-extra-inspector b)
           (ser-push! 'tag '#:inspector)
           (ser-push! #f))
       (ser-push! (full-module-binding-extra-nominal-bindings b))]
      [else
       (ser-push! simplified-b)]))
  #:property prop:binding-shift-report
  (lambda (b bulk-shifts report-shifts)
    (report-shifts (full-module-binding-module b) bulk-shifts)
    (report-shifts (full-module-binding-nominal-module b) bulk-shifts)
    (for ([b (in-list (full-module-binding-extra-nominal-bindings b))])
      (when (binding-shift-report? b)
        ((binding-shift-report-ref b) b bulk-shifts report-shifts)))))

(struct simple-module-binding (module phase sym nominal-module)
  #:authentic
  #:transparent
  #:property prop:serialize
  (lambda (b ser-push! state)
    (ser-push! 'tag '#:simple-module-binding)
    (ser-push! (simple-module-binding-module b))
    (define-values (sym phase)
      ((serialize-state-map-binding-symbol state) (simple-module-binding-module b)
                                                  (simple-module-binding-sym b)
                                                  (simple-module-binding-phase b)))
    (ser-push! sym)
    (ser-push! phase)
    (ser-push! (simple-module-binding-nominal-module b)))
  #:property prop:binding-shift-report
  (lambda (b bulk-shifts report-shifts)
    (report-shifts (simple-module-binding-module b) bulk-shifts)
    (report-shifts (simple-module-binding-nominal-module b) bulk-shifts)))

(define (deserialize-full-module-binding module sym phase
                                         nominal-module
                                         nominal-phase+space
                                         nominal-sym
                                         nominal-require-phase+space-shift
                                         free=id
                                         extra-inspector
                                         extra-nominal-bindings)
  (make-module-binding module phase sym
                       #:nominal-module nominal-module
                       #:nominal-phase+space (intern-phase+space nominal-phase+space)
                       #:nominal-sym nominal-sym
                       #:nominal-require-phase+space-shift (intern-phase+space-shift nominal-require-phase+space-shift)
                       #:free=id free=id
                       #:extra-inspector extra-inspector
                       #:extra-nominal-bindings extra-nominal-bindings))

(define (deserialize-simple-module-binding module sym phase nominal-module)
  (simple-module-binding module phase sym nominal-module))

;; ----------------------------------------

(define (module-binding-to-intern? v)
  (or (module-binding? v) (full-module-binding? v)))

;; Binding resolution might or might not use cache, so we need to intern
;; for serialization to make the result deterministic
(define (module-binding-maybe-intern v interns map-binding-symbol mpi->index)
  (define key
    (cond
      [(simple-module-binding? v)
       (define-values (sym phase)
         (map-binding-symbol (simple-module-binding-module v)
                             (simple-module-binding-sym v)
                             (simple-module-binding-phase v)))
       (list (mpi->index (simple-module-binding-module v))
             phase
             sym
             (mpi->index (simple-module-binding-nominal-module v)))]
      [(full-module-binding? v)
       (define-values (sym phase)
         (map-binding-symbol (full-module-binding-module v)
                             (full-module-binding-sym v)
                             (full-module-binding-phase v)))
       (list (mpi->index (full-module-binding-module v))
             phase
             sym
             (mpi->index (full-module-binding-nominal-module v))
             (full-module-binding-nominal-phase+space v)
             (full-module-binding-nominal-sym v)
             (full-module-binding-nominal-require-phase+space-shift v)
             (full-module-binding-extra-inspector v)
             (for/list ([b (full-module-binding-extra-nominal-bindings v)])
               (or (module-binding-maybe-intern b interns map-binding-symbol mpi->index)
                   b)))]))
  (define new-v (hash-ref interns key #f))
  (cond
    [(not new-v)
     (hash-set! interns key v)
     #f]
    [(eq? new-v v) #f]
    [else new-v]))

;; ----------------------------------------

(define (module-binding-module b)
  (if (simple-module-binding? b)
      (simple-module-binding-module b)
      (full-module-binding-module b)))

(define (module-binding-phase b)
  (if (simple-module-binding? b)
      (simple-module-binding-phase b)
      (full-module-binding-phase b)))

(define (module-binding-sym b)
  (if (simple-module-binding? b)
      (simple-module-binding-sym b)
      (full-module-binding-sym b)))

(define (module-binding-nominal-module b)
  (if (simple-module-binding? b)
      (simple-module-binding-nominal-module b)
      (full-module-binding-nominal-module b)))
       
(define (module-binding-nominal-phase+space b)
  (if (simple-module-binding? b)
      (simple-module-binding-phase b)
      (full-module-binding-nominal-phase+space b)))

(define (module-binding-nominal-sym b)
  (if (simple-module-binding? b)
      (simple-module-binding-sym b)
      (full-module-binding-nominal-sym b)))

(define (module-binding-nominal-require-phase+space-shift b)
  (if (simple-module-binding? b)
      0
      (full-module-binding-nominal-require-phase+space-shift b)))

(define (module-binding-extra-inspector b)
  (if (simple-module-binding? b)
      #f
      (full-module-binding-extra-inspector b)))

(define (module-binding-extra-nominal-bindings b)
  (if (simple-module-binding? b)
      null
      (full-module-binding-extra-nominal-bindings b)))
