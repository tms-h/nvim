(** One side of the book: price levels, best first. *)

type level =
  { price : int
  ; size : int
  }

(** Invariant: [bids] is sorted by price descending, [asks] by price
    ascending, and no level has [size <= 0]. *)
type t =
  { bids : level list
  ; asks : level list
  }

val empty : t
val add_bid : t -> level -> t
val best_bid : t -> level option
