open! Core

type book =
  { mutable best_bid : int
  ; mutable best_ask : int
  }

(* Both run on every market-data packet. *)
let[@zero_alloc] mid t = (t.best_bid + t.best_ask) / 2

let[@zero_alloc] spread_label t = sprintf "%d/%d" t.best_bid t.best_ask
