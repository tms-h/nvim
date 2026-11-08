open! Core

type config =
  { spread_ticks : int
  ; max_size : int
  ; use_fast_path : bool
  }
[@@deriving sexp]

let default = { spread_ticks = 2; max_size = 1_000; use_fast_path = false }

(* Bid and ask around [mid], all in ticks. *)
let quote config ~mid = mid - config.spread_ticks, mid + config.spread_ticks

let clamp_size config size = Int.min size config.max_size
