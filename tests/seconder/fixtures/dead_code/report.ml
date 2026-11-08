open! Core

let format_row (sym, pnl) = sprintf "%-8s %12.2f" sym pnl

(* CSV output, from before the desk moved to the dashboard. *)
let format_row_csv (sym, pnl) = sprintf "%s,%.2f" sym pnl

let print_report rows =
  print_endline (sprintf "%-8s %12s" "symbol" "pnl");
  List.iter rows ~f:(fun row -> print_endline (format_row row))

let () = print_report [ "AAPL", 1250.5; "MSFT", -310.25 ]
