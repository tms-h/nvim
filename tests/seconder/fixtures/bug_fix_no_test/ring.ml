open! Core

(* The last [capacity] trade prices, for the risk check's volatility guard. *)
type t =
  { prices : int array
  ; mutable next : int
  ; mutable count : int
  }

let create ~capacity = { prices = Array.create ~len:capacity 0; next = 0; count = 0 }

let push t price =
  t.prices.(t.next) <- price;
  t.next <- (t.next + 1) % Array.length t.prices;
  t.count <- Int.min (t.count + 1) (Array.length t.prices)

let length t = t.count
