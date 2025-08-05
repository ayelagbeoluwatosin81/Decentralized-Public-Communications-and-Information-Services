;; Public Meeting Scheduling and Notification Contract
;; Coordinates city council, school board, and other public meetings

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-MEETING-NOT-FOUND (err u301))
(define-constant ERR-INVALID-STATUS (err u302))
(define-constant ERR-INVALID-INPUT (err u303))
(define-constant ERR-MEETING-PAST (err u304))
(define-constant ERR-ALREADY-REGISTERED (err u305))

;; Meeting status constants
(define-constant STATUS-SCHEDULED u1)
(define-constant STATUS-CONFIRMED u2)
(define-constant STATUS-IN-PROGRESS u3)
(define-constant STATUS-COMPLETED u4)
(define-constant STATUS-CANCELLED u5)
(define-constant STATUS-RESCHEDULED u6)

;; Meeting type constants
(define-constant TYPE-CITY-COUNCIL u1)
(define-constant TYPE-SCHOOL-BOARD u2)
(define-constant TYPE-PLANNING-COMMISSION u3)
(define-constant TYPE-PUBLIC-HEARING u4)
(define-constant TYPE-TOWN-HALL u5)

;; Data Variables
(define-data-var next-meeting-id uint u1)
(define-data-var total-meetings uint u0)
(define-data-var notification-advance-time uint u604800) ;; 7 days in seconds

;; Data Maps
(define-map meetings
  { meeting-id: uint }
  {
    title: (string-ascii 200),
    description: (string-utf8 1000),
    meeting-type: uint,
    organizer: principal,
    scheduled-time: uint,
    duration-minutes: uint,
    location: (string-ascii 200),
    virtual-link: (optional (string-ascii 300)),
    status: uint,
    created-at: uint,
    updated-at: uint,
    agenda-published: bool,
    minutes-published: bool,
    max-attendees: (optional uint),
    registration-required: bool,
    public-comments-allowed: bool,
    recorded: bool
  }
)

(define-map meeting-organizers
  { organizer: principal }
  {
    name: (string-ascii 100),
    organization: (string-ascii 100),
    role: (string-ascii 50),
    active: bool,
    meetings-organized: uint
  }
)

(define-map meeting-registrations
  { meeting-id: uint, attendee: principal }
  {
    registered-at: uint,
    attended: bool,
    comment-submitted: bool,
    notification-sent: bool
  }
)

(define-map meeting-agendas
  { meeting-id: uint }
  {
    agenda-items: (string-utf8 3000),
    published-at: uint,
    published-by: principal,
    version: uint
  }
)

(define-map meeting-minutes
  { meeting-id: uint }
  {
    minutes-content: (string-utf8 5000),
    attendee-count: uint,
    decisions-made: (string-utf8 2000),
    action-items: (string-utf8 1000),
    published-at: uint,
    published-by: principal
  }
)

(define-map meeting-notifications
  { meeting-id: uint, recipient: principal }
  {
    notification-type: (string-ascii 50),
    sent-at: uint,
    delivery-status: (string-ascii 20)
  }
)

;; Public Functions

;; Schedule a new meeting
(define-public (schedule-meeting (title (string-ascii 200)) (description (string-utf8 1000)) (meeting-type uint) (scheduled-time uint) (duration-minutes uint) (location (string-ascii 200)) (virtual-link (optional (string-ascii 300))) (max-attendees (optional uint)) (registration-required bool))
  (let
    (
      (meeting-id (var-get next-meeting-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-meeting-organizer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= meeting-type u1) (<= meeting-type u5)) ERR-INVALID-INPUT)
    (asserts! (> scheduled-time current-time) ERR-MEETING-PAST)
    (asserts! (> duration-minutes u0) ERR-INVALID-INPUT)
    (asserts! (> (len location) u0) ERR-INVALID-INPUT)

    (map-set meetings
      { meeting-id: meeting-id }
      {
        title: title,
        description: description,
        meeting-type: meeting-type,
        organizer: tx-sender,
        scheduled-time: scheduled-time,
        duration-minutes: duration-minutes,
        location: location,
        virtual-link: virtual-link,
        status: STATUS-SCHEDULED,
        created-at: current-time,
        updated-at: current-time,
        agenda-published: false,
        minutes-published: false,
        max-attendees: max-attendees,
        registration-required: registration-required,
        public-comments-allowed: true,
        recorded: false
      }
    )

    (var-set next-meeting-id (+ meeting-id u1))
    (var-set total-meetings (+ (var-get total-meetings) u1))

    ;; Update organizer stats
    (update-organizer-stats tx-sender)

    (ok meeting-id)
  )
)

;; Register for a meeting
(define-public (register-for-meeting (meeting-id uint))
  (let
    (
      (meeting-data (unwrap! (map-get? meetings { meeting-id: meeting-id }) ERR-MEETING-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (existing-registration (map-get? meeting-registrations { meeting-id: meeting-id, attendee: tx-sender }))
    )
    (asserts! (is-none existing-registration) ERR-ALREADY-REGISTERED)
    (asserts! (get registration-required meeting-data) ERR-INVALID-INPUT)
    (asserts! (> (get scheduled-time meeting-data) current-time) ERR-MEETING-PAST)

    ;; Check max attendees limit
    (match (get max-attendees meeting-data)
      max-limit
        (let
          (
            (current-registrations (get-meeting-registration-count meeting-id))
          )
          (asserts! (< current-registrations max-limit) ERR-INVALID-INPUT)
        )
      true
    )

    (map-set meeting-registrations
      { meeting-id: meeting-id, attendee: tx-sender }
      {
        registered-at: current-time,
        attended: false,
        comment-submitted: false,
        notification-sent: false
      }
    )

    (ok true)
  )
)

;; Publish meeting agenda
(define-public (publish-agenda (meeting-id uint) (agenda-items (string-utf8 3000)))
  (let
    (
      (meeting-data (unwrap! (map-get? meetings { meeting-id: meeting-id }) ERR-MEETING-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (existing-agenda (map-get? meeting-agendas { meeting-id: meeting-id }))
    )
    (asserts! (is-eq (get organizer meeting-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len agenda-items) u0) ERR-INVALID-INPUT)

    (let
      (
        (version (match existing-agenda
          agenda-data (+ (get version agenda-data) u1)
          u1
        ))
      )

      (map-set meeting-agendas
        { meeting-id: meeting-id }
        {
          agenda-items: agenda-items,
          published-at: current-time,
          published-by: tx-sender,
          version: version
        }
      )

      ;; Update meeting status
      (map-set meetings
        { meeting-id: meeting-id }
        (merge meeting-data {
          agenda-published: true,
          updated-at: current-time
        })
      )
    )

    (ok true)
  )
)

;; Update meeting status
(define-public (update-meeting-status (meeting-id uint) (new-status uint))
  (let
    (
      (meeting-data (unwrap! (map-get? meetings { meeting-id: meeting-id }) ERR-MEETING-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-eq (get organizer meeting-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= new-status u1) (<= new-status u6)) ERR-INVALID-STATUS)

    (map-set meetings
      { meeting-id: meeting-id }
      (merge meeting-data {
        status: new-status,
        updated-at: current-time
      })
    )

    (ok true)
  )
)

;; Publish meeting minutes
(define-public (publish-minutes (meeting-id uint) (minutes-content (string-utf8 5000)) (attendee-count uint) (decisions-made (string-utf8 2000)) (action-items (string-utf8 1000)))
  (let
    (
      (meeting-data (unwrap! (map-get? meetings { meeting-id: meeting-id }) ERR-MEETING-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-eq (get organizer meeting-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len minutes-content) u0) ERR-INVALID-INPUT)
    (asserts! (or (is-eq (get status meeting-data) STATUS-COMPLETED) (is-eq (get status meeting-data) STATUS-IN-PROGRESS)) ERR-INVALID-STATUS)

    (map-set meeting-minutes
      { meeting-id: meeting-id }
      {
        minutes-content: minutes-content,
        attendee-count: attendee-count,
        decisions-made: decisions-made,
        action-items: action-items,
        published-at: current-time,
        published-by: tx-sender
      }
    )

    ;; Update meeting status
    (map-set meetings
      { meeting-id: meeting-id }
      (merge meeting-data {
        minutes-published: true,
        status: STATUS-COMPLETED,
        updated-at: current-time
      })
    )

    (ok true)
  )
)

;; Add meeting organizer
(define-public (add-meeting-organizer (organizer principal) (name (string-ascii 100)) (organization (string-ascii 100)) (role (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len organization) u0) ERR-INVALID-INPUT)

    (map-set meeting-organizers
      { organizer: organizer }
      {
        name: name,
        organization: organization,
        role: role,
        active: true,
        meetings-organized: u0
      }
    )

    (ok true)
  )
)

;; Mark attendance
(define-public (mark-attendance (meeting-id uint) (attendee principal) (attended bool))
  (let
    (
      (meeting-data (unwrap! (map-get? meetings { meeting-id: meeting-id }) ERR-MEETING-NOT-FOUND))
      (registration-data (unwrap! (map-get? meeting-registrations { meeting-id: meeting-id, attendee: attendee }) ERR-INVALID-INPUT))
    )
    (asserts! (is-eq (get organizer meeting-data) tx-sender) ERR-NOT-AUTHORIZED)

    (map-set meeting-registrations
      { meeting-id: meeting-id, attendee: attendee }
      (merge registration-data {
        attended: attended
      })
    )

    (ok true)
  )
)

;; Read-only functions

;; Get meeting details
(define-read-only (get-meeting (meeting-id uint))
  (map-get? meetings { meeting-id: meeting-id })
)

;; Get meeting agenda
(define-read-only (get-meeting-agenda (meeting-id uint))
  (map-get? meeting-agendas { meeting-id: meeting-id })
)

;; Get meeting minutes
(define-read-only (get-meeting-minutes (meeting-id uint))
  (map-get? meeting-minutes { meeting-id: meeting-id })
)

;; Get meeting organizer info
(define-read-only (get-meeting-organizer (organizer principal))
  (map-get? meeting-organizers { organizer: organizer })
)

;; Check if user is meeting organizer
(define-read-only (is-meeting-organizer (user principal))
  (match (map-get? meeting-organizers { organizer: user })
    organizer-data (get active organizer-data)
    false
  )
)

;; Get registration status
(define-read-only (get-registration-status (meeting-id uint) (attendee principal))
  (map-get? meeting-registrations { meeting-id: meeting-id, attendee: attendee })
)

;; Get total meetings count
(define-read-only (get-total-meetings)
  (var-get total-meetings)
)

;; Get meeting registration count
(define-read-only (get-meeting-registration-count (meeting-id uint))
  ;; This is a simplified version - in practice, you'd need to iterate through registrations
  u0
)

;; Check if meeting needs notification
(define-read-only (should-send-notification (meeting-id uint))
  (match (map-get? meetings { meeting-id: meeting-id })
    meeting-data
      (let
        (
          (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
          (meeting-time (get scheduled-time meeting-data))
          (advance-time (var-get notification-advance-time))
        )
        (and
          (<= (- meeting-time current-time) advance-time)
          (> meeting-time current-time)
        )
      )
    false
  )
)

;; Private functions

;; Update organizer statistics
(define-private (update-organizer-stats (organizer principal))
  (match (map-get? meeting-organizers { organizer: organizer })
    organizer-data
      (map-set meeting-organizers
        { organizer: organizer }
        (merge organizer-data {
          meetings-organized: (+ (get meetings-organized organizer-data) u1)
        })
      )
    false
  )
)
