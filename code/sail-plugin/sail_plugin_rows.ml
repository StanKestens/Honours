(* sail_plugin_rows: print every clause of `encdec` and `encdec_compressed`
   as a bit pattern, in the order Sail itself uses.

   Output, one line per clause:
     <mapping> <index> <pattern> <lhs> [when <guard>]
   pattern: MSB first, 0/1 = literal bit, - = anything else (field or helper mapping).

   Milestone 1 only. NOT YET COMPILED. Written against the development Sail in
   Honours/sail (commit ef5dca5, 12 Nov 2026), installed with `opam pin add .`.
   The released libsail 0.20.3 uses DEF_aux/DEF_scattered/DEF_mapdef instead. *)

open Libsail
open Ast
open Ast_util

let targets = ["encdec"; "encdec_compressed"]

let clauses : (string * Type_check.tannot mapcl) list ref = ref []
let global_env : Type_check.Env.t option ref = ref None

(* Runs on the type-checked AST, before Sail's own rewrites. *)
let collect (ast : Type_check.typed_ast) _effects env =
  global_env := Some env;
  List.iter
    (fun (Def_aux (d, _)) ->
      match d with
      | Def_scattered (SD_aux (SD_mapcl (id, cl), _)) when List.mem (string_of_id id) targets ->
          clauses := (string_of_id id, cl) :: !clauses
      | Def_mapdef (MD_aux (MD_mapping (id, _, cls), _)) when List.mem (string_of_id id) targets ->
          List.iter (fun cl -> clauses := (string_of_id id, cl) :: !clauses) cls
      | _ -> ())
    ast.defs;
  clauses := List.rev !clauses

let fail mp msg = failwith (msg ^ ": " ^ string_of_mpat mp)

(* Width of a bitvector-typed mapping pattern, from its type annotation. *)
let width env mp =
  match Type_check.destruct_bitvector env (Type_check.typ_of_mpat mp) with
  | Some n -> (match Type_check.big_int_of_nexp n with Some w -> Z.to_int w | None -> fail mp "non-constant width")
  | None -> fail mp "not a bitvector"

(* "0b0110_011" / "0x7f" -> string of 0/1 of length w *)
let lit_bits mp lit w =
  let s = string_of_lit lit in
  let s = String.concat "" (String.split_on_char '_' s) in
  let n = String.length s in
  let bits =
    if n > 2 && String.sub s 0 2 = "0b" then String.sub s 2 (n - 2)
    else if n > 2 && String.sub s 0 2 = "0x" then
      String.concat ""
        (List.init (n - 2) (fun i ->
             let d = int_of_string ("0x" ^ String.make 1 s.[i + 2]) in
             String.init 4 (fun k -> if (d lsr (3 - k)) land 1 = 1 then '1' else '0')))
    else fail mp ("unexpected literal " ^ s)
  in
  if String.length bits <> w then fail mp "literal width mismatch";
  bits

let rec segments (MP_aux (aux, _) as mp) =
  match aux with MP_vector_concat mps -> List.concat_map segments mps | _ -> [mp]

let rec seg_string env (MP_aux (aux, _) as mp) =
  let w = width env mp in
  match aux with
  | MP_lit lit -> lit_bits mp lit w
  | MP_typ (inner, _) -> seg_string env inner
  | MP_id _ | MP_app _ | MP_vector_subrange _ -> String.make w '-'
  | _ -> fail mp "unsupported pattern form"

let split_mpexp (MPat_aux (aux, _)) =
  match aux with MPat_pat p -> (p, None) | MPat_when (p, g) -> (p, Some g)

let action _out _istate =
  let env = match !global_env with Some e -> e | None -> failwith "no environment" in
  let counter = Hashtbl.create 2 in
  List.iter
    (fun (name, MCL_aux (cl, _)) ->
      let i = try Hashtbl.find counter name with Not_found -> 0 in
      Hashtbl.replace counter name (i + 1);
      match cl with
      | MCL_bidir (l, r) ->
          let lhs, g1 = split_mpexp l in
          let rhs, g2 = split_mpexp r in
          let guard = match (g1, g2) with Some g, _ | None, Some g -> " when " ^ string_of_exp g | _ -> "" in
          let pat = String.concat "" (List.map (seg_string env) (segments rhs)) in
          Printf.printf "%s %d %s %s%s\n" name i pat (string_of_mpat lhs) guard
      | MCL_forwards _ | MCL_backwards _ -> Printf.printf "%s %d <forwards/backwards clause>\n" name i)
    !clauses

let _ =
  Target.register ~name:"rows" ~description:"print encdec clauses as bit patterns"
    ~pre_rewrites_hook:collect ~supports_runtime_config:true action
