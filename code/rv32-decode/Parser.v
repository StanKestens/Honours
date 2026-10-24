(** * Parser.v: een simpele parser voor RISC-V I-type instructies

    Een instructie is 32 bits. Bij een I-type instructie (zoals ADDI)
    zijn die bits verdeeld in vijf velden. We lezen ze vanaf bit 0:

        opcode (7 bits) | rd (5) | funct3 (3) | rs1 (5) | imm (12)

    We stellen bits voor als een lijst van booleans, met bit 0 eerst.
    We schrijven een parser en een serializer, en bewijzen twee dingen:
      1. parse (serialize i) = Some i     (roundtrip)
      2. parse b = Some i  ->  serialize i = b   (er gaan geen bits verloren) *)

From Stdlib Require Import List.
Import ListNotations.

Definition bits := list bool.

(** ** n bits afnemen *)

(** [take_bits n b] neemt de eerste n bits van b en geeft ook de rest terug.
    Zijn er niet genoeg bits, dan faalt het (None). *)
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

(** Als f precies n bits lang is, dan geeft take_bits n (f ++ r) terug: f en r. *)
Lemma take_bits_app n f r : length f = n -> take_bits n (f ++ r) = Some (f, r).
Proof.
  intros H. subst n.
  induction f as [| x f IH].
  - reflexivity. (** lege lijst : take_bits (length []) ([] ++ r) = Some ([], r)*)
  - simpl. rewrite IH. reflexivity.
Qed.

(** Alle bits afnemen: geen rest. *)
Lemma take_bits_all n f : length f = n -> take_bits n f = Some (f, []).
Proof.
  intros H. rewrite <- (app_nil_r f) at 1. apply take_bits_app. exact H.
Qed.

(** Omgekeerd: als take_bits slaagt, dan was b gewoon f gevolgd door r. *)
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

(** ** Instructie, parser en serializer *)

Inductive itype := ITYPE (opcode rd funct3 rs1 imm : bits).

(** Een instructie is van de juiste vorm als elk veld de juiste length heeft *)
Definition wf (i : itype) : Prop :=
  match i with
  | ITYPE o d f s m =>
      length o = 7 /\ length d = 5 /\ length f = 3 /\ length s = 5 /\ length m = 12
  end.

(** De serializer plakt de velden achter elkaar. *)
Definition serialize (i : itype) : bits :=
  match i with
  | ITYPE o d f s m => o ++ d ++ f ++ s ++ m
  end.

(** De parser neemt de velden een voor een af. Na het laatste veld
    mag er niets meer over zijn: een instructie is precies 32 bits. *)
Definition parse (b : bits) : option itype :=
  match take_bits 7 b with
  | None => None
  | Some (o, b1) =>
  match take_bits 5 b1 with
  | None => None
  | Some (d, b2) =>
  match take_bits 3 b2 with
  | None => None
  | Some (f, b3) =>
  match take_bits 5 b3 with
  | None => None
  | Some (s, b4) =>
  match take_bits 12 b4 with
  | None => None
  | Some (m, rest) =>
      match rest with
      | [] => Some (ITYPE o d f s m)
      | _ => None
      end
  end end end end end.

(** ** Stellingen *)

(** Roundtrip: een goed gevormde instructie serializeren en weer parsen
    geeft dezelfde instructie terug. *)
Theorem parse_serialize i : wf i -> parse (serialize i) = Some i.
Proof.
  destruct i as [o d f s m]. cbn [wf serialize]. intros (Ho & Hd & Hf & Hs & Hm).
  unfold parse.
  rewrite (take_bits_app 7 o _ Ho).  cbv beta iota.
  rewrite (take_bits_app 5 d _ Hd).  cbv beta iota.
  rewrite (take_bits_app 3 f _ Hf).  cbv beta iota.
  rewrite (take_bits_app 5 s _ Hs).  cbv beta iota.
  rewrite (take_bits_all 12 m Hm).   cbv beta iota.
  reflexivity.
Qed.

(** Omgekeerd: als de parser slaagt, geeft serializeren precies de
    oorspronkelijke bits terug. De parser gooit dus geen bits weg. *)
Theorem serialize_parse b i : parse b = Some i -> serialize i = b.
Proof.
  intros H. unfold parse in H.
  destruct (take_bits 7 b)  as [[o b1] |] eqn:E1; cbv beta iota in H; [| discriminate H].
  destruct (take_bits 5 b1) as [[d b2] |] eqn:E2; cbv beta iota in H; [| discriminate H].
  destruct (take_bits 3 b2) as [[f b3] |] eqn:E3; cbv beta iota in H; [| discriminate H].
  destruct (take_bits 5 b3) as [[s b4] |] eqn:E4; cbv beta iota in H; [| discriminate H].
  destruct (take_bits 12 b4) as [[m rest] |] eqn:E5; cbv beta iota in H; [| discriminate H].
  destruct rest as [| x rest]; cbv beta iota in H; [| discriminate H].
  injection H as <-. cbn [serialize].
  apply take_bits_split in E1. apply take_bits_split in E2.
  apply take_bits_split in E3. apply take_bits_split in E4.
  apply take_bits_split in E5.
  subst. rewrite app_nil_r. reflexivity.
Qed.

(** ** Voorbeeld

    [addi x1, x0, 5]: opcode 19, rd 1, funct3 0, rs1 0, imm 5.
    Elk veld staat hier met bit 0 eerst. 19 = 1 + 2 + 16, dus 1,1,0,0,1,0,0. *)

Definition b (l : list nat) : bits := map (Nat.eqb 1) l.   (* schrijfhulp: 1 = true *)

Definition addi_bits : bits :=
  b [1;1;0;0;1;0;0;  1;0;0;0;0;  0;0;0;  0;0;0;0;0;  1;0;1;0;0;0;0;0;0;0;0;0].

Example parse_addi :
  parse addi_bits = Some (ITYPE (b [1;1;0;0;1;0;0]) (b [1;0;0;0;0]) (b [0;0;0])
                                (b [0;0;0;0;0]) (b [1;0;1;0;0;0;0;0;0;0;0;0])).
Proof. reflexivity. Qed.

(** Te weinig bits: de parser faalt. *)
Example parse_too_short : parse (b [1;0;1]) = None.
Proof. reflexivity. Qed.
