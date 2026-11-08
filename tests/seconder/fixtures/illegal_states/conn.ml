open! Core

type t =
  { mutable connected : bool
  ; mutable socket : Unix.File_descr.t option
  }

let create () = { connected = false; socket = None }

let on_connect t fd =
  t.connected <- true;
  t.socket <- Some fd

let on_disconnect t =
  t.connected <- false;
  t.socket <- None

let socket_for_send t =
  match t.socket with
  | Some fd when t.connected -> Ok fd
  | _ -> error_s [%message "not connected"]
