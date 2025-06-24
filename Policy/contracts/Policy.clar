;; Protection Shield Protocol Smart Contract
;; Implements shield management, damage claims processing, and fee handling

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-SHIELD-EXISTS (err u101))
(define-constant ERR-SHIELD-NOT-FOUND (err u102))
(define-constant ERR-INSUFFICIENT-FEE (err u103))
(define-constant ERR-SHIELD-EXPIRED (err u104))
(define-constant ERR-INVALID-DAMAGE-CLAIM (err u105))
(define-constant ERR-DAMAGE-CLAIM-ALREADY-PROCESSED (err u106))

;; Data structures
(define-map protection-shields
    { shield-id: uint, guardian: principal }
    {
        protection-limit: uint,
        maintenance-fee: uint,
        activation-height: uint,
        expiration-height: uint,
        is-operational: bool
    }
)

(define-map damage-claims
    { damage-id: uint, shield-id: uint }
    {
        compensation-amount: uint,
        incident-report: (string-ascii 256),
        claim-status: (string-ascii 20),
        is-resolved: bool,
        shield-id: uint
    }
)

;; Storage variables
(define-data-var next-shield-id uint u1)
(define-data-var next-damage-id uint u1)
(define-data-var protocol-admin principal tx-sender)
(define-data-var total-fees-collected uint u0)
(define-data-var total-compensation-paid uint u0)

;; Administrative functions
(define-public (set-protocol-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get protocol-admin)) ERR-NOT-AUTHORIZED)
        (var-set protocol-admin new-admin)
        (ok true)
    )
)

;; Shield management functions
(define-public (create-protection-shield (protection-limit uint) (maintenance-fee uint) (shield-duration uint))
    (let
        (
            (shield-id (var-get next-shield-id))
            (activation-height burn-block-height)
            (expiration-height (+ burn-block-height shield-duration))
        )
        (asserts! (> protection-limit u0) (err u107))
        (asserts! (> maintenance-fee u0) (err u108))
        (asserts! (> shield-duration u0) (err u109))
        
        (map-insert protection-shields
            { shield-id: shield-id, guardian: tx-sender }
            {
                protection-limit: protection-limit,
                maintenance-fee: maintenance-fee,
                activation-height: activation-height,
                expiration-height: expiration-height,
                is-operational: true
            }
        )
        
        (var-set next-shield-id (+ shield-id u1))
        (ok shield-id)
    )
)

(define-public (pay-maintenance-fee (shield-id uint))
    (let
        (
            (shield (unwrap! (get-shield shield-id) ERR-SHIELD-NOT-FOUND))
            (fee-amount (get maintenance-fee shield))
        )
        (asserts! (unwrap! (is-shield-operational shield-id) ERR-SHIELD-NOT-FOUND) ERR-SHIELD-EXPIRED)
        (try! (stx-transfer? fee-amount tx-sender (var-get protocol-admin)))
        (var-set total-fees-collected (+ (var-get total-fees-collected) fee-amount))
        (ok true)
    )
)

;; Damage claims processing functions
(define-public (submit-damage-claim (shield-id uint) (compensation-amount uint) (incident-report (string-ascii 256)))
    (let
        (
            (damage-id (var-get next-damage-id))
            (shield (unwrap! (get-shield shield-id) ERR-SHIELD-NOT-FOUND))
        )
        (asserts! (unwrap! (is-shield-operational shield-id) ERR-SHIELD-NOT-FOUND) ERR-SHIELD-EXPIRED)
        (asserts! (<= compensation-amount (get protection-limit shield)) ERR-INVALID-DAMAGE-CLAIM)
        
        (map-insert damage-claims
            { damage-id: damage-id, shield-id: shield-id }
            {
                compensation-amount: compensation-amount,
                incident-report: incident-report,
                claim-status: "PENDING",
                is-resolved: false,
                shield-id: shield-id
            }
        )
        
        (var-set next-damage-id (+ damage-id u1))
        (ok damage-id)
    )
)

(define-public (process-damage-claim (damage-id uint) (shield-id uint) (approved bool))
    (let
        (
            (damage-claim (unwrap! (get-damage-claim damage-id shield-id) ERR-INVALID-DAMAGE-CLAIM))
            (shield-guardian (unwrap! (get-shield-guardian shield-id) ERR-SHIELD-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (var-get protocol-admin)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get is-resolved damage-claim)) ERR-DAMAGE-CLAIM-ALREADY-PROCESSED)
        
        (if approved
            (begin
                (try! (stx-transfer? (get compensation-amount damage-claim) (var-get protocol-admin) shield-guardian))
                (var-set total-compensation-paid (+ (var-get total-compensation-paid) (get compensation-amount damage-claim)))
                (map-set damage-claims
                    { damage-id: damage-id, shield-id: shield-id }
                    (update-claim-data damage-claim { claim-status: "APPROVED", is-resolved: true })
                )
                (ok true)
            )
            (begin
                (map-set damage-claims
                    { damage-id: damage-id, shield-id: shield-id }
                    (update-claim-data damage-claim { claim-status: "REJECTED", is-resolved: true })
                )
                (ok true)
            )
        )
    )
)

;; Read-only functions
(define-read-only (get-shield (shield-id uint))
    (map-get? protection-shields { shield-id: shield-id, guardian: tx-sender })
)

(define-read-only (get-damage-claim (damage-id uint) (shield-id uint))
    (map-get? damage-claims { damage-id: damage-id, shield-id: shield-id })
)

(define-read-only (get-shield-guardian (shield-id uint))
    (let ((shield-key { shield-id: shield-id, guardian: tx-sender }))
        (match (map-get? protection-shields shield-key)
            shield (ok tx-sender)
            ERR-SHIELD-NOT-FOUND
        )
    )
)

(define-read-only (is-shield-operational (shield-id uint))
    (match (get-shield shield-id)
        shield (ok (and
            (get is-operational shield)
            (<= burn-block-height (get expiration-height shield))
        ))
        ERR-SHIELD-NOT-FOUND
    )
)

(define-read-only (get-contract-stats)
    {
        total-fees-collected: (var-get total-fees-collected),
        total-compensation-paid: (var-get total-compensation-paid),
        next-shield-id: (var-get next-shield-id),
        next-damage-id: (var-get next-damage-id),
        protocol-admin: (var-get protocol-admin)
    }
)

;; Helper functions
(define-private (update-claim-data (claim-data {
        compensation-amount: uint,
        incident-report: (string-ascii 256),
        claim-status: (string-ascii 20),
        is-resolved: bool,
        shield-id: uint
    }) 
    (updates {
        claim-status: (string-ascii 20),
        is-resolved: bool
    }))
    {
        compensation-amount: (get compensation-amount claim-data),
        incident-report: (get incident-report claim-data),
        claim-status: (get claim-status updates),
        is-resolved: (get is-resolved updates),
        shield-id: (get shield-id claim-data)
    }
)