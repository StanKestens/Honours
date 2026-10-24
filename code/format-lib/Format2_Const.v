(** * Format2_Const.v

    Stage 2: Format1_Seq.v plus constants. [FConst c] matches exactly the
    bits [c] (e.g. an opcode); its value is [tt]. *)

From Stdlib Require Import List Bool.
Import ListNotations.

From FormatLib Require Import Bits.

(** ** Format descriptions *)

Inductive fmt : Type :=
| FBits  (n : nat)          (* field of exactly n bits *)
| FSeq   (f1 f2 : fmt)      (* f1 followed by f2 *)
| FConst (c : bits).        (* exactly the bits c *)

(* Type of the parsed value. *)
Fixpoint denote (f : fmt) : Type :=
  match f with
  | FBits _    => bits
  | FSeq f1 f2 => (denote f1 * denote f2)%type
  | FConst _   => unit
  end.

(* Every field has the right length. *)
Fixpoint wf (f : fmt) : denote f -> Prop :=
  match f with
  | FBits n    => fun v => length v = n
  | FSeq f1 f2 => fun p => wf f1 (fst p) /\ wf f2 (snd p)
  | FConst _   => fun _ => True
  end.

(** ** Parser and serializer *)

Fixpoint serialize (f : fmt) : denote f -> bits :=
  match f with
  | FBits _    => fun v => v
  | FSeq f1 f2 => fun p => serialize f1 (fst p) ++ serialize f2 (snd p)
  | FConst c   => fun _ => c
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
  | FConst c   =>
      match take_bits (length c) b with
      | None => None
      | Some (c', r) => if list_eq_dec bool_dec c' c then Some (tt, r) else None
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
  - (* FConst: TODO *) admit.
Admitted.

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
        *discriminate.
      +discriminate.
  - (* FConst: TODO *) admit.
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
  - (* FConst: TODO *) admit.
Admitted.

(** ** I-type as an instance *)

(* opcode (7) | rd (5) | funct3 (3) | rs1 (5) | imm (12) *)
Definition itype_fmt : fmt :=
  FSeq (FBits 7) (FSeq (FBits 5) (FSeq (FBits 3) (FSeq (FBits 5) (FBits 12)))).

(* The roundtrip of Parser.v as a special case. *)
Corollary itype_roundtrip : forall v, wf itype_fmt v ->
  parse itype_fmt (serialize itype_fmt v) = Some (v, []).
Proof.
  intros v H. rewrite <- (app_nil_r (serialize itype_fmt v)).
  apply parse_serialize. exact H.
Qed.

(** ** TODO

    - FConst cases of the three theorems.
    - Opcode of ADDI (0010011) as FConst in itype_fmt.
    - FAlt f1 f2 (choice): parse_serialize no longer holds in general.
      Which condition on f1, f2?
    - FDep f k, with k : denote f -> fmt (e.g. length fields): needs
      induction-recursion. *)
