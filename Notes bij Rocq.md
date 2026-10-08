
```rocq
    Definition app {m n} (xs : bv m) (ys : bv n) : bv (m + n) :=
      fold_right (fun m => bv (m + n)) (fun m => @cons (m + n)) ys xs.
    #[global] Arguments app : simpl never.
```


{m,n} - "impliciete parameters?" (not sure what this means, zijn dit gewoon vaste parameters die de functie moet krijgen)
(xs : bv m) (ys : bv n) - bitvectors van sizes m en n respectivly
```app {m n} (xs : bv m) (ys : bv n) : bv (m + n)``` lijkt te insinueren dat de hele functie ook direct getypeerd wordt als een nieuw element van bv (m+n)
```fold_right``` fold achtige functie (haskell) met :
- elke stap een functie ``` m => bv (m + n)```
- cons? not sure
- ys initial value
- xs to fold over

    