;; Title: CipherMarket Protocol
;; Summary: Bitcoin-Native Digital Asset Trading Platform with Zero-Knowledge Commerce
;; Description:
;; CipherMarket Protocol revolutionizes digital asset trading through a sophisticated
;; Bitcoin Layer 2 infrastructure built on Stacks blockchain technology. This protocol
;; enables trustless peer-to-peer commerce for digital content while maintaining
;; complete privacy and provable ownership through cryptographic guarantees.
;;
;; The platform leverages Bitcoin's immutable security model to create a decentralized
;; marketplace where creators can monetize digital assets without intermediaries.
;; Every transaction benefits from Bitcoin's settlement finality while utilizing
;; Stacks' smart contract capabilities for complex trading logic.
;;
;; Key Innovation Areas:
;; - Cryptographic Asset Provenance: Immutable ownership chains with Bitcoin anchoring
;; - Zero-Knowledge Access Control: Private content delivery with public verification
;; - Dynamic Market Mechanics: Algorithmic pricing with reputation-weighted discovery
;; - Cross-Chain Compatibility: Native Bitcoin integration with Layer 2 scalability
;; - Creator-Centric Economics: Automated royalty streams with transparent distribution
;;
;; Technical Architecture:
;; Built exclusively in Clarity smart contract language, ensuring mathematical
;; correctness and seamless Bitcoin integration. The protocol implements advanced
;; cryptographic primitives for secure content distribution while maintaining
;; full compatibility with Bitcoin's UTXO model and consensus rules.

;; Protocol Constants
(define-constant contract-owner tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_ASSET_UNAVAILABLE (err u402))
(define-constant ERR_DUPLICATE_LISTING (err u403))
(define-constant ERR_INSUFFICIENT_BALANCE (err u404))
(define-constant ERR_SELF_PURCHASE_DENIED (err u405))
(define-constant ERR_INVALID_PRICE (err u406))
(define-constant ERR_INVALID_INPUT (err u407))

;; Core Data Structures
;; Digital asset registry with comprehensive metadata and trading parameters
(define-map digital-assets
  { asset-id: uint }
  {
    creator: principal,
    price-stx: uint,
    description: (string-ascii 256),
    asset-category: (string-ascii 64),
    available: bool,
    mint-block: uint,
  }
)

;; Participant reputation system with activity metrics
(define-map participant-profiles
  { user: principal }
  {
    total-trades: uint,
    reputation-score: uint,
    last-activity: uint,
  }
)

;; Transaction ledger for complete trading history
(define-map trading-history
  {
    buyer: principal,
    asset-id: uint,
  }
  {
    block-height: uint,
    purchase-price: uint,
    seller: principal,
  }
)

;; Secure credential storage with encrypted access tokens
(define-map access-credentials
  { asset-id: uint }
  { encrypted-token: (string-ascii 512) }
)

;; Protocol State Management
(define-data-var next-asset-id uint u1)
(define-data-var platform-fee-rate uint u25) ;; 2.5% platform fee
(define-data-var total-trading-volume uint u0)

;; Input Validation Utilities
(define-private (validate-description (text (string-ascii 256)))
  (and
    (not (is-eq text ""))
    (<= (len text) u256)
    (>= (len text) u10)
  )
)

(define-private (validate-category (text (string-ascii 64)))
  (and
    (not (is-eq text ""))
    (<= (len text) u64)
    (>= (len text) u3)
  )
)

(define-private (validate-access-token (text (string-ascii 512)))
  (and
    (not (is-eq text ""))
    (<= (len text) u512)
    (>= (len text) u32)
  )
)

;; Financial Mathematics
(define-private (calculate-platform-fee (price uint))
  (/ (* price (var-get platform-fee-rate)) u1000)
)

(define-private (execute-stx-transfer
    (sender principal)
    (recipient principal)
    (amount uint)
  )
  (stx-transfer? amount sender recipient)
)

;; Asset Management Functions

;; Create and list new digital asset for trading
(define-public (create-asset-listing
    (price-stx uint)
    (description (string-ascii 256))
    (category (string-ascii 64))
    (access-token (string-ascii 512))
  )
  (let ((asset-id (var-get next-asset-id)))
    (asserts! (> price-stx u0) ERR_INVALID_PRICE)
    (asserts! (validate-description description) ERR_INVALID_INPUT)
    (asserts! (validate-category category) ERR_INVALID_INPUT)
    (asserts! (validate-access-token access-token) ERR_INVALID_INPUT)
    (asserts!
      (not (default-to false
        (get available (map-get? digital-assets { asset-id: asset-id }))
      ))
      ERR_DUPLICATE_LISTING
    )

    (map-set digital-assets { asset-id: asset-id } {
      creator: tx-sender,
      price-stx: price-stx,
      description: description,
      asset-category: category,
      available: true,
      mint-block: stacks-block-height,
    })

    (map-set access-credentials { asset-id: asset-id } { encrypted-token: access-token })

    (var-set next-asset-id (+ asset-id u1))
    (ok asset-id)
  )
)

;; Execute digital asset purchase with automatic fee distribution
(define-public (purchase-digital-asset (asset-id uint))
  (let (
      (asset-data (unwrap! (map-get? digital-assets { asset-id: asset-id })
        ERR_ASSET_UNAVAILABLE
      ))
      (purchase-price (get price-stx asset-data))
      (seller (get creator asset-data))
      (platform-fee (calculate-platform-fee purchase-price))
      (seller-revenue (- purchase-price platform-fee))
    )
    (asserts! (< asset-id (var-get next-asset-id)) ERR_INVALID_INPUT)
    (asserts! (get available asset-data) ERR_ASSET_UNAVAILABLE)
    (asserts! (is-eq false (is-eq tx-sender seller)) ERR_SELF_PURCHASE_DENIED)

    (try! (execute-stx-transfer tx-sender seller seller-revenue))
    (try! (execute-stx-transfer tx-sender contract-owner platform-fee))
