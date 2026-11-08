open! Core

type level =
  { price : int
  ; size : int
  }

type t =
  { bids : level list
  ; asks : level list
  }

let empty = { bids = []; asks = [] }

let add_bid t level =
  if level.size <= 0
  then t
  else (
    let bids =
      List.merge t.bids [ level ] ~compare:(fun a b -> Int.compare b.price a.price)
    in
    { t with bids })

let best_bid t = List.hd t.bids
