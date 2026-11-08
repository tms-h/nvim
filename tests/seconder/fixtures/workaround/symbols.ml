open! Core
open! Async

(* Workaround: the venue's symbol file has no trailing newline and our
   vendored copy of Reader.file_lines drops a last line without one, so we
   read the whole file and split it ourselves. *)
let read_symbols path =
  let%map contents = Reader.file_contents path in
  String.split_lines contents |> List.filter ~f:(fun l -> not (String.is_empty l))
