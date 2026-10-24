(** * Bits.v

    Bit strings and [take_bits], shared by all stages of the format library. *)

From Stdlib Require Import List.
Import ListNotations.

Definition bits := list bool.

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
