#lang racket/base
(require racket/contract/base)

(define ((hash-duplicate-error name) key value1 value2)
  (error name "duplicate values for key ~e: ~e and ~e" key value1 value2))

(define (merge one two combine/key)
  (for/fold ([one one]) ([(k v) (in-hash two)])
    (hash-set one k (if (hash-has-key? one k)
                        (combine/key k (hash-ref one k) v)
                        v))))

(define (hash-union
         #:combine [combine #f]
         #:combine/key [combine/key
                        (if combine
                            (lambda (_ x y) (combine x y))
                            (hash-duplicate-error 'hash-union))]
         one . rest)
  (define one-empty (hash-clear one))
  (for/fold ([one one]) ([two (in-list rest)])
    (cond
      [(and (immutable? two)
            (< (hash-count one) (hash-count two))
            (equal? one-empty (hash-clear two)))
       (merge two one (λ (k a b) (combine/key k b a)))]
      [else (merge one two combine/key)])))

(define (hash-union!
         #:combine [combine #f]
         #:combine/key [combine/key
                        (if combine
                            (lambda (_ x y) (combine x y))
                            (hash-duplicate-error 'hash-union!))]
         one . rest)
  (for* ([two (in-list rest)] [(k v) (in-hash two)])
    (hash-set! one k (if (hash-has-key? one k)
                         (combine/key k (hash-ref one k) v)
                         v))))

(define (hash-intersect
         #:combine [combine #f]
         #:combine/key [combine/key
                        (if combine
                            (λ (_ x y) (combine x y))
                            (hash-duplicate-error 'hash-intersect))]
         one . rest)
  (define hashes (cons one rest))
  (define empty-h (hash-clear one)) ;; empty hash of same type as one
  (define (argmin f lst) ;; avoid racket/list to improve loading time
    (for/fold ([best (car lst)]
               [fbest (f (car lst))]
               #:result best)
              ([x (in-list lst)])
      (define fx (f x))
      (if (< fx fbest) (values x fx) (values best fbest))))
  (for/fold ([res empty-h])
            ([k (in-hash-keys (argmin hash-count hashes))])
    (if (for/and ([h (in-list hashes)]) (hash-has-key? h k))
        (hash-set res k
                  (for/fold ([v (hash-ref one k)])
                            ([hm (in-list rest)])
                    (combine/key k v (hash-ref hm k))))
        res)))

(define (hash-filter ht pred)
  (cond
    [(immutable? ht)
     (for/fold ([ht ht]) ([(k v) (in-immutable-hash ht)]
                          #:unless (pred k v))
       (hash-remove ht k))]
    [else
     (define new-ht (hash-copy-clear ht))
     (for ([(k v) (in-hash ht)] #:when (pred k v))
       (hash-set! new-ht k v))
     new-ht]))

(define (hash-filter-keys ht pred)
  (hash-filter ht (lambda (k _) (pred k))))

(define (hash-filter-values ht pred)
  (hash-filter ht (lambda (_ v) (pred v))))

(provide/contract
 [hash-union (->* [(and/c hash? immutable?)]
                  [#:combine
                   (-> any/c any/c any/c)
                   #:combine/key
                   (-> any/c any/c any/c any/c)]
                  #:rest (listof hash?)
                  (and/c hash? immutable?))]
 [hash-union! (->* [(and/c hash? (not/c immutable?))]
                   [#:combine
                    (-> any/c any/c any/c)
                    #:combine/key
                    (-> any/c any/c any/c any/c)]
                   #:rest (listof hash?)
                   void?)]
 [hash-intersect  (->* [(and/c hash? immutable?)]
                       [#:combine
                        (-> any/c any/c any/c)
                        #:combine/key
                        (-> any/c any/c any/c any/c)]
                       #:rest (listof hash?)
                       (and/c hash? immutable?))]
 [hash-filter (-> hash? procedure? hash?)]
 [hash-filter-values (-> hash? procedure? hash?)]
 [hash-filter-keys (-> hash? procedure? hash?)])
