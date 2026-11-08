open! Core

let parse_port (s : string) : (int, string) Result.t =
  match Int.of_string_opt s with
  | None -> Error ("not a number: " ^ s)
  | Some p when p < 1 || p > 65535 -> Error (sprintf "port %d out of range" p)
  | Some p -> Ok p

let parse_endpoint (s : string) : (string * int, string) Result.t =
  match String.lsplit2 s ~on:':' with
  | None -> Error "expected host:port"
  | Some (host, port) ->
    (match parse_port port with
     | Error e -> Error ("bad endpoint " ^ s ^ ": " ^ e)
     | Ok port -> Ok (host, port))
