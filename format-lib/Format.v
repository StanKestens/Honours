(** * Format.v

    Generic version of rv32-decode/Parser.v. Instead of writing a parser
    and a serializer for every instruction format, a format is described
    as a value of type [fmt]. [parse] and [serialize] are defined by
    recursion on that description, so the roundtrip properties only have
    to be proven once, for every format. *)

From Stdlib Require Import List.
Import ListNotations.

Definition bits := list bool.

(** ** take_bits (from Parser.v) *)

Fixpoint take_bits (n : nat) (b : bits) : option (bits * bits) :=
  match n with
  | 0 => Some ([], b)
  | S n' =>
      match b with
      | [] => None
      | x :: b' =>
          match take_bits n' b' with
          | Some (f, r) => Some (x :: f, r)
          | None => None
          end
      end
  end.

Lemma take_bits_app n f r : length f = n -> take_bits n (f ++ r) = Some (f, r).
Proof.
  intros H. subst n.
  induction f as [| x f IH].
  - reflexivity.
  - simpl. rewrite IH. reflexivity.
Qed.

Lemma take_bits_split n b f r : take_bits n b = Some (f, r) -> b = f ++ r.
Proof.
  revert b f r.
  induction n as [| n IH]; intros b f r H.
  - simpl in H. injection H as <- <-. reflexivity.
  - destruct b as [| x b].
    + simpl in H. discriminate H.
    + simpl in H. destruct (take_bits n b) as [[f' r'] |] eqn:E.
      * injection H as <- <-. simpl. f_equal. apply IH. exact E.
      * discriminate H.
Qed.

(* On success take_bits returns exactly n bits. Needed for parse_wf. *)
Theorem parsing_keeps_length : forall n b f r,
take_bits n b = Some(f, r) -> length f = n.
Proof.
  intros n.
  induction n as [| n IH].
  - simpl. intros b f r H. injection H as Hf Hr. rewrite <- Hf. simpl. reflexivity.
  - intros b f r H. simpl in H. destruct b as [| x b'].
    + discriminate H.
    + destruct (take_bits n b') as [[f0 r0] |] eqn:E1.
      * apply IH in E1. injection H as Hf Hr. 
        rewrite <- Hf. rewrite (length_cons f0 x). 
        rewrite E1. reflexivity.
      * discriminate H. 
Qed.

(** ** Format descriptions *)

(* Since fmt is an Inductive, we get pattern matching and an induction
   principle (fmt_ind) for free. *)
Inductive fmt : Type :=
| FBits (n : nat)          (* field of exactly n bits *)
| FSeq  (f1 f2 : fmt).     (* f1 followed by f2 *)

(* The type of what you get back when parsing f. Note that this maps a
   value to a type. *)
Fixpoint denote (f : fmt) : Type :=
  match f with
  | FBits _    => bits
  | FSeq f1 f2 => (denote f1 * denote f2)%type
  end.

Compute denote (FSeq (FBits 5) (FBits 3)).  (* = (bits * bits) *)

(* A value is well-formed if every field has the length the format asks for. *)
Fixpoint wf (f : fmt) : denote f -> Prop :=
  match f with
  | FBits n    => fun v => length v = n   (* here v : bits *)
  | FSeq f1 f2 => fun p => wf f1 (fst p) /\ wf f2 (snd p)
  end.

(** ** Parser and serializer *)

Fixpoint serialize (f : fmt) : denote f -> bits :=
  match f with
  | FBits _    => fun v => v
  | FSeq f1 f2 => fun p => serialize f1 (fst p) ++ serialize f2 (snd p)
  end.

Fixpoint parse (f : fmt) (b : bits) : option (denote f * bits) :=
  match f with
  | FBits n    => take_bits n b
  | FSeq f1 f2 =>
      match parse f1 b with
      | None => None
      | Some (v1, b1) =>
          match parse f2 b1 with
          | None => None
          | Some (v2, b2) => Some ((v1, v2), b2)
          end
      end
  end.

(** ** Correctness *)

(* Every well-formed value is read back correctly, whatever follows it. *)
Theorem parse_serialize : forall f v r,
  wf f v -> parse f (serialize f v ++ r) = Some (v, r).
Proof.
  intros f v.
  induction f.
  - simpl. apply (take_bits_app n v).
  - simpl. intros r H. destruct H as [H1 H2]. destruct v as [v1 v2]. simpl. 
  rewrite app_assoc_reverse_deprecated. 
  rewrite IHf1. rewrite IHf2. reflexivity. apply H2. apply H1.
Qed.

(* No bits get lost: the input is the serialized value followed by the rest. *)
Theorem serialize_parse : forall f b v r,
  parse f b = Some (v, r) -> b = serialize f v ++ r.
Proof.
  intros f.
  induction f.
  - intros b v r H. simpl. simpl in H. apply (take_bits_split n b v r  H).
  - simpl. intros b v. 
    destruct (parse f1 b) as [[v3 b1] |] eqn:E1. 
      +destruct (parse f2 b1) as [[v4 b2] |] eqn:E2.  
        *intros r. destruct v as [v1 v2]. intros H. injection H. simpl. 
        apply IHf1 in E1. apply IHf2 in E2. intros H1 H2 H3. rewrite <- H3 . 
        rewrite <- H1. rewrite app_assoc_reverse_deprecated. rewrite <- H2. rewrite <- E2. rewrite <- E1.
        reflexivity. 
      (* TODO: the cases where parse f1 or parse f2 fails *)
Admitted.

(* Whatever the parser returns is well-formed. *)
Theorem parse_wf : forall f b v r,
  parse f b = Some (v, r) -> wf f v.
Proof.
  intros f.
  induction f.
  - intros b v r. simpl. apply parsing_keeps_length.
  - intros b v r. simpl. destruct (parse f1 b) as [[v1 b1] |] eqn:E1.
   + destruct (parse f2 b1) as [[v2 b2] |] eqn:E2.
    * intros H. destruct v as [v1' v2']. 
    split. simpl. apply IHf1 in E1. 
    injection H as Hv1 Hv2 Hr.
    rewrite Hv1 in E1. apply E1. injection H as Hv1 Hv2 Hr. simpl. rewrite <- Hv2. apply IHf2 in E2. apply E2.
    * discriminate.
   + discriminate.
Qed. 

(** ** I-type as an instance *)

(* opcode (7) | rd (5) | funct3 (3) | rs1 (5) | imm (12) *)
Definition itype_fmt : fmt :=
  FSeq (FBits 7) (FSeq (FBits 5) (FSeq (FBits 3) (FSeq (FBits 5) (FBits 12)))).

(* The roundtrip from Parser.v, now as a direct consequence of parse_serialize. *)
Corollary itype_roundtrip : forall v, wf itype_fmt v ->
  parse itype_fmt (serialize itype_fmt v) = Some (v, []).
Proof.
  intros v H. rewrite <- (app_nil_r (serialize itype_fmt v)).
  apply parse_serialize. exact H.
Qed.

(** ** TODO

    - Constants: [FConst (c : bits)], a field that has to be exactly [c]
      (e.g. the ADDI opcode 0010011). denote is [unit], parse fails when
      the bits don't match ([list_eq_dec Bool.bool_dec]).
    - Choice: [FAlt (f1 f2 : fmt)] with a [sum] as denote: try f1, and if
      that fails, f2 (I-type or R-type ...). parse_serialize no longer
      holds in general; find a counterexample and the condition on f1 and
      f2 that makes it true again (non-malleability, EverParse §2).
    - Dependent fields, e.g. a length field that determines the size of
      the next field: [FDep (f : fmt) (k : denote f -> fmt)]. Rocq rejects
      this (induction-recursion), so it needs a workaround. Narcissus
      §2-3; discuss with Devriese. *)
