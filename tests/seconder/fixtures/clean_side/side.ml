open! Core

type t =
  | Buy
  | Sell
[@@deriving sexp, compare, equal]

let flip = function
  | Buy -> Sell
  | Sell -> Buy

let sign = function
  | Buy -> 1
  | Sell -> -1

let%expect_test "flip is its own inverse and sign follows" =
  List.iter [ Buy; Sell ] ~f:(fun s ->
    print_s [%sexp (s : t), (equal s (flip (flip s)) : bool), (sign s : int)]);
  [%expect {|
    (Buy true 1)
    (Sell true -1) |}]
