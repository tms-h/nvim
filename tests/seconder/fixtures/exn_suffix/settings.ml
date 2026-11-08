open! Core

(* Settings come from the desk's key=value file, already parsed into a map. *)
let get_int (settings : string String.Map.t) key =
  match Map.find settings key with
  | Some v -> Int.of_string v
  | None -> failwithf "setting %s missing" key ()

let max_order_size settings = get_int settings "max_order_size"
let max_open_orders settings = get_int settings "max_open_orders"
