(* Fills from the venue's drop copy. *)

type fill =
  { order_id : int
  ; symbol : string
  ; price : Price.t
  ; size : int
  }

(* Drop fills we have already booked: the venue resends them after a reconnect. *)
let dedup ~(booked : fill list) (incoming : fill list) =
  List.filter (fun f -> not (List.exists (fun b -> b = f) booked)) incoming

let booked_size fills = List.fold_left (fun acc f -> acc + f.size) 0 fills
