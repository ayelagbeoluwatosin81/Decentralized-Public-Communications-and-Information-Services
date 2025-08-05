;; Citizen Feedback Collection Contract
;; Gathers public input on government services and policy proposals

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-FEEDBACK-NOT-FOUND (err u401))
(define-constant ERR-INVALID-STATUS (err u402))
(define-constant ERR-INVALID-INPUT (err u403))
(define-constant ERR-FEEDBACK-CLOSED (err u404))
(define-constant ERR-ALREADY-RESPONDED (err u405))

;; Feedback status constants
(define-constant STATUS-SUBMITTED u1)
(define-constant STATUS-UNDER-REVIEW u2)
(define-constant STATUS-RESPONDED u3)
(define-constant STATUS-RESOLVED u4)
(define-constant STATUS-CLOSED u5)

;; Feedback category constants
(define-constant CATEGORY-SERVICE-QUALITY u1)
(define-constant CATEGORY-POLICY-PROPOSAL u2)
(define-constant CATEGORY-INFRASTRUCTURE u3)
(define-constant CATEGORY-PUBLIC-SAFETY u4)
(define-constant CATEGORY-ENVIRONMENT u5)
(define-constant CATEGORY-BUDGET u6)
(define-constant CATEGORY-OTHER u7)

;; Priority levels
(define-constant PRIORITY-LOW u1)
(define-constant PRIORITY-MEDIUM u2)
(define-constant PRIORITY-HIGH u3)
(define-constant PRIORITY-URGENT u4)

;; Data Variables
(define-data-var next-feedback-id uint u1)
(define-data-var total-feedback-items uint u0)
(define-data-var response-time-target uint u604800) ;; 7 days in seconds

;; Data Maps
(define-map feedback-items
  { feedback-id: uint }
  {
    citizen: principal,
    title: (string-ascii 200),
    description: (string-utf8 2000),
    category: uint,
    priority: uint,
    status: uint,
    created-at: uint,
    updated-at: uint,
    assigned-to: (optional principal),
    response: (optional (string-utf8 2000)),
    response-time: (optional uint),
    satisfaction-rating: (optional uint),
    anonymous: bool,
    location: (optional (string-ascii 200)),
    contact-info: (optional (string-ascii 200)),
    attachments-count: uint
  }
)

(define-map government-responders
  { responder: principal }
  {
    name: (string-ascii 100),
    department: (string-ascii 100),
    role: (string-ascii 50),
    active: bool,
    feedback-handled: uint,
    average-response-time: uint
  }
)

(define-map feedback-categories
  { category: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 300),
    department: (string-ascii 100),
    auto-assign: bool,
    target-response-time: uint,
    active: bool
  }
)

(define-map feedback-responses
  { feedback-id: uint }
  {
    responder: principal,
    response-text: (string-utf8 2000),
    response-type: (string-ascii 50),
    created-at: uint,
    follow-up-required: bool,
    escalated: bool
  }
)

(define-map citizen-profiles
  { citizen: principal }
  {
    feedback-submitted: uint,
    feedback-resolved: uint,
    average-satisfaction: uint,
    preferred-contact: (string-ascii 50),
    notification-preferences: (string-ascii 100)
  }
)

(define-map feedback-analytics
  { period: (string-ascii 20) }
  {
    total-feedback: uint,
    resolved-feedback: uint,
    average-response-time: uint,
    satisfaction-score: uint,
    most-common-category: uint
  }
)

;; Public Functions

;; Submit new feedback
(define-public (submit-feedback (title (string-ascii 200)) (description (string-utf8 2000)) (category uint) (priority uint) (anonymous bool) (location (optional (string-ascii 200))) (contact-info (optional (string-ascii 200))))
  (let
    (
      (feedback-id (var-get next-feedback-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= category u1) (<= category u7)) ERR-INVALID-INPUT)
    (asserts! (and (>= priority u1) (<= priority u4)) ERR-INVALID-INPUT)

    (map-set feedback-items
      { feedback-id: feedback-id }
      {
        citizen: tx-sender,
        title: title,
        description: description,
        category: category,
        priority: priority,
        status: STATUS-SUBMITTED,
        created-at: current-time,
        updated-at: current-time,
        assigned-to: none,
        response: none,
        response-time: none,
        satisfaction-rating: none,
        anonymous: anonymous,
        location: location,
        contact-info: contact-info,
        attachments-count: u0
      }
    )

    (var-set next-feedback-id (+ feedback-id u1))
    (var-set total-feedback-items (+ (var-get total-feedback-items) u1))

    ;; Update citizen profile
    (update-citizen-profile tx-sender true false u0)

    (ok feedback-id)
  )
)

;; Assign feedback to responder
(define-public (assign-feedback (feedback-id uint) (responder principal))
  (let
    (
      (feedback-data (unwrap! (map-get? feedback-items { feedback-id: feedback-id }) ERR-FEEDBACK-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-government-responder tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-government-responder responder) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status feedback-data) STATUS-SUBMITTED) ERR-INVALID-STATUS)

    (map-set feedback-items
      { feedback-id: feedback-id }
      (merge feedback-data {
        assigned-to: (some responder),
        status: STATUS-UNDER-REVIEW,
        updated-at: current-time
      })
    )

    (ok true)
  )
)

;; Respond to feedback
(define-public (respond-to-feedback (feedback-id uint) (response-text (string-utf8 2000)) (response-type (string-ascii 50)) (follow-up-required bool))
  (let
    (
      (feedback-data (unwrap! (map-get? feedback-items { feedback-id: feedback-id }) ERR-FEEDBACK-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (response-time (- current-time (get created-at feedback-data)))
    )
    (asserts! (is-government-responder tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status feedback-data) STATUS-UNDER-REVIEW) ERR-INVALID-STATUS)
    (asserts! (> (len response-text) u0) ERR-INVALID-INPUT)

    ;; Store response
    (map-set feedback-responses
      { feedback-id: feedback-id }
      {
        responder: tx-sender,
        response-text: response-text,
        response-type: response-type,
        created-at: current-time,
        follow-up-required: follow-up-required,
        escalated: false
      }
    )

    ;; Update feedback item
    (map-set feedback-items
      { feedback-id: feedback-id }
      (merge feedback-data {
        status: STATUS-RESPONDED,
        response: (some response-text),
        response-time: (some response-time),
        updated-at: current-time
      })
    )

    ;; Update responder stats
    (update-responder-stats tx-sender response-time)

    (ok true)
  )
)

;; Rate feedback response
(define-public (rate-feedback-response (feedback-id uint) (rating uint))
  (let
    (
      (feedback-data (unwrap! (map-get? feedback-items { feedback-id: feedback-id }) ERR-FEEDBACK-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-eq (get citizen feedback-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status feedback-data) STATUS-RESPONDED) ERR-INVALID-STATUS)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-INPUT)

    (map-set feedback-items
      { feedback-id: feedback-id }
      (merge feedback-data {
        satisfaction-rating: (some rating),
        status: STATUS-RESOLVED,
        updated-at: current-time
      })
    )

    ;; Update citizen profile
    (update-citizen-profile tx-sender false true rating)

    (ok true)
  )
)

;; Close feedback item
(define-public (close-feedback (feedback-id uint) (closure-reason (string-ascii 200)))
  (let
    (
      (feedback-data (unwrap! (map-get? feedback-items { feedback-id: feedback-id }) ERR-FEEDBACK-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-government-responder tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq (get status feedback-data) STATUS-CLOSED)) ERR-FEEDBACK-CLOSED)
    (asserts! (> (len closure-reason) u0) ERR-INVALID-INPUT)

    (map-set feedback-items
      { feedback-id: feedback-id }
      (merge feedback-data {
        status: STATUS-CLOSED,
        updated-at: current-time
      })
    )

    (ok true)
  )
)

;; Add government responder
(define-public (add-government-responder (responder principal) (name (string-ascii 100)) (department (string-ascii 100)) (role (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len department) u0) ERR-INVALID-INPUT)

    (map-set government-responders
      { responder: responder }
      {
        name: name,
        department: department,
        role: role,
        active: true,
        feedback-handled: u0,
        average-response-time: u0
      }
    )

    (ok true)
  )
)

;; Add feedback category
(define-public (add-feedback-category (category uint) (name (string-ascii 100)) (description (string-ascii 300)) (department (string-ascii 100)) (target-response-time uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= category u1) (<= category u7)) ERR-INVALID-INPUT)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> target-response-time u0) ERR-INVALID-INPUT)

    (map-set feedback-categories
      { category: category }
      {
        name: name,
        description: description,
        department: department,
        auto-assign: false,
        target-response-time: target-response-time,
        active: true
      }
    )

    (ok true)
  )
)

;; Update citizen notification preferences
(define-public (update-notification-preferences (preferred-contact (string-ascii 50)) (notification-preferences (string-ascii 100)))
  (let
    (
      (existing-profile (map-get? citizen-profiles { citizen: tx-sender }))
    )
    (match existing-profile
      profile-data
        (map-set citizen-profiles
          { citizen: tx-sender }
          (merge profile-data {
            preferred-contact: preferred-contact,
            notification-preferences: notification-preferences
          })
        )
      (map-set citizen-profiles
        { citizen: tx-sender }
        {
          feedback-submitted: u0,
          feedback-resolved: u0,
          average-satisfaction: u0,
          preferred-contact: preferred-contact,
          notification-preferences: notification-preferences
        })
    )

    (ok true)
  )
)

;; Read-only functions

;; Get feedback item
(define-read-only (get-feedback-item (feedback-id uint))
  (map-get? feedback-items { feedback-id: feedback-id })
)

;; Get feedback response
(define-read-only (get-feedback-response (feedback-id uint))
  (map-get? feedback-responses { feedback-id: feedback-id })
)

;; Get government responder info
(define-read-only (get-government-responder (responder principal))
  (map-get? government-responders { responder: responder })
)

;; Check if user is government responder
(define-read-only (is-government-responder (user principal))
  (match (map-get? government-responders { responder: user })
    responder-data (get active responder-data)
    false
  )
)

;; Get citizen profile
(define-read-only (get-citizen-profile (citizen principal))
  (map-get? citizen-profiles { citizen: citizen })
)

;; Get feedback category info
(define-read-only (get-feedback-category (category uint))
  (map-get? feedback-categories { category: category })
)

;; Get total feedback count
(define-read-only (get-total-feedback-items)
  (var-get total-feedback-items)
)

;; Check if feedback is overdue
(define-read-only (is-feedback-overdue (feedback-id uint))
  (match (map-get? feedback-items { feedback-id: feedback-id })
    feedback-data
      (let
        (
          (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
          (created-time (get created-at feedback-data))
          (target-time (var-get response-time-target))
        )
        (and
          (not (is-eq (get status feedback-data) STATUS-RESOLVED))
          (not (is-eq (get status feedback-data) STATUS-CLOSED))
          (> (- current-time created-time) target-time)
        )
      )
    false
  )
)

;; Get feedback analytics
(define-read-only (get-feedback-analytics (period (string-ascii 20)))
  (map-get? feedback-analytics { period: period })
)

;; Private functions

;; Update citizen profile statistics
(define-private (update-citizen-profile (citizen principal) (submitted bool) (resolved bool) (rating uint))
  (let
    (
      (existing-profile (map-get? citizen-profiles { citizen: citizen }))
    )
    (match existing-profile
      profile-data
        (map-set citizen-profiles
          { citizen: citizen }
          (merge profile-data {
            feedback-submitted: (if submitted (+ (get feedback-submitted profile-data) u1) (get feedback-submitted profile-data)),
            feedback-resolved: (if resolved (+ (get feedback-resolved profile-data) u1) (get feedback-resolved profile-data)),
            average-satisfaction: (if (> rating u0) rating (get average-satisfaction profile-data))
          })
        )
      (map-set citizen-profiles
        { citizen: citizen }
        {
          feedback-submitted: (if submitted u1 u0),
          feedback-resolved: (if resolved u1 u0),
          average-satisfaction: rating,
          preferred-contact: "email",
          notification-preferences: "all"
        })
    )
  )
)

;; Update responder statistics
(define-private (update-responder-stats (responder principal) (response-time uint))
  (match (map-get? government-responders { responder: responder })
    responder-data
      (let
        (
          (handled-count (get feedback-handled responder-data))
          (current-avg (get average-response-time responder-data))
          (new-avg (/ (+ (* current-avg handled-count) response-time) (+ handled-count u1)))
        )
        (map-set government-responders
          { responder: responder }
          (merge responder-data {
            feedback-handled: (+ handled-count u1),
            average-response-time: new-avg
          })
        )
      )
    false
  )
)
