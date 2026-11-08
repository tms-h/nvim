open! Core

(* Sum of the last [n] values added. *)
type t =
  { n : int
  ; values : int Queue.t
  ; mutable sum : int
  }

let create n = { n; values = Queue.create (); sum = 0 }

let add t x =
  Queue.enqueue t.values x;
  t.sum <- t.sum + x;
  if Queue.length t.values > t.n then t.sum <- t.sum - Queue.dequeue_exn t.values

let sum t = t.sum

let%expect_test "keeps the last n" =
  let t = create 2 in
  List.iter [ 1; 2; 3 ] ~f:(add t);
  print_s [%sexp (sum t : int)];
  [%expect {| 5 |}]
