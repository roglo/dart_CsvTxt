(* heuristic to find the most probable separator of a csv file
   and display the csv file with aligned columns;
   work here in OCaml and translation to Dart by hand later *)
(* at end, display a directory like LC_ALL=C lf -aF
   should be in a separated application *)

open Printf;

(* Searching the separator of a csv file *)

value nb_lines_of s =
  loop 0 0 0 where rec loop n ibeg i =
    if i = String.length s then if i = ibeg then n else n + 1
    else if s.[i] = '\n' then loop (n + 1) (i + 1) (i + 1)
    else loop n ibeg (i + 1)
;

value number_of_occurrences c s i : (int * int) =
  loop False 0 i where rec loop in_string n i =
    if i = String.length s then (n, i)
    else if s.[i] = '"' then
      if i + 1 < String.length s then
        if s.[i+1] = '"' then loop in_string n (i + 2)
        else loop (not in_string) n (i + 1)
      else (n, i + 1)
    else if s.[i] = '\n' then (n, i + 1)
    else
      loop in_string (if not in_string && s.[i] = c then n + 1 else n) (i + 1)
;

value number_list_of_occurrences c content =
  loop [] 0 where rec loop nl i =
    if i = String.length content then nl
    else
      let (n, i) = number_of_occurrences c content i in
      loop [n :: nl] i
;

value char_value c =
  match c with
  [ 'a'..'z' | 'A'..'Z' | '0'..'9' | '(' | ')' | '[' | ']' | '{' | '}' |
    '\r' | '\128'..'\255' →
      0
  | '+' | '_' | ' ' | '\\' | '`' | '?' | '*' | '!' | '@' | '<' | '>' → 2
  | '-' | '\'' | '=' | '~' | '#' | '&' | '%' → 3
  | '/' | '.' | '^' → 4
  | ',' | ';' | '|' | '\t' | ':' → 5
  | _ → failwith ("char value chais pas " ^ Char.escaped c) ]
;

value strip_spaces s =
  let b = Buffer.create 1 in
  loop 0 0 where rec loop i nspaces =
    if i = String.length s then Buffer.contents b
    else if s.[i] = ' ' then loop (i + 1) (nspaces + 1)
    else do {
      if nspaces <> 0 then Buffer.add_char b ' ' else ();
      Buffer.add_char b s.[i];
      loop (i + 1) 0
    }
;

value strip_double_quotes s =
  let b = Buffer.create 1 in
  loop 0 where rec loop i =
    if i = String.length s then Buffer.contents b
    else do {
      Buffer.add_char b s.[i];
      let i =
        if s.[i] = '"' && i + 1 < String.length s && s.[i+1] = '"' then i + 1
        else i
      in
      loop (i + 1)
    }
;

value criterion_value c nb_correct_lines nb_occ_of_char nb_lines =
  nb_correct_lines * nb_occ_of_char / nb_lines + char_value c
;

value test_separator c content =
  let r : list int = number_list_of_occurrences c content in
  let modal_values =
    loop [] r where rec loop mv =
      fun
      [ [nb_occ_of_char :: nb_occ_of_char_l] →
          let (mv1, mv2) =
            List.partition
              (fun (nb_occ_of_char', _) → nb_occ_of_char' = nb_occ_of_char) mv
          in
          let mv =
            match mv1 with
            [ [] → [(nb_occ_of_char, 1) :: mv2]
            | [(_, nb_correct_lines)] →
                [(nb_occ_of_char, nb_correct_lines + 1) :: mv2]
            | _ → failwith "bug in test separator" ]
          in
          loop mv nb_occ_of_char_l
      | [] → mv ]
  in
  let modal_values =
    List.sort
      (fun (_, nb_correct_lines) (_, nb_correct_lines') →
         nb_correct_lines' - nb_correct_lines)
      modal_values
  in
  let modal_values =
    List.filter (fun (nb_occ_of_char, cnt) → nb_occ_of_char <> 0) modal_values
  in
  modal_values
;

value test_separators candidates
    (content : string) : list (char * int * int * list (int * int)) =
  loop [] 0 where rec loop r i =
    if i = String.length candidates then r
    else
      let c = candidates.[i] in
      let sl : list (int * int) = test_separator c content in
      let r =
        match sl with
        [ [] → r
        | [(nb_occ_of_char, nb_correct_lines) :: defective] →
            [(c, nb_occ_of_char, nb_correct_lines, defective) :: r] ]
      in
      loop r (i + 1)
;

value sort_separators nb_lines r =
  List.sort
    (fun (c, nb_occ_of_char, nb_correct_lines, defective)
         (c', nb_occ_of_char', nb_correct_lines', defective') →
       let criterion =
         criterion_value c nb_correct_lines nb_occ_of_char nb_lines
       in
       let criterion' =
         criterion_value c' nb_correct_lines' nb_occ_of_char' nb_lines
       in
       if criterion' < criterion then -1
       else if criterion' > criterion then 1
       else char_value c' - char_value c)
    r
;

value find_separator candidate_chars content =
  (*
    let content = strip_spaces content in
  *)
  let nb_lines =
    nb_lines_of content
  in
  let r = test_separators candidate_chars content in
  sort_separators nb_lines r
;

value get_good_separator (r : list (char * int * int * list (int * int))) =
  match r with
  [ [(c, nb_occ_of_char, nb_correct_lines, defective) :: _] → c
  | [] → 'a' ]
;

value get_nb_occ_of_char (r : list (char * int * int * list (int * int))) =
  match r with
  [ [(c, nb_occ_of_char, nb_correct_lines, defective) :: _] → nb_occ_of_char
  | [] → 0 ]
;

(* Changing the display of a csv file to make it pretty
   (work in progress) *)

value utf_8_start_char c =
  Char.code c land 0x80 <> 0 && Char.code c land 0x40 <> 0
;

value utf_8_cont_char c =
  Char.code c land 0x80 <> 0 && Char.code c land 0x40 = 0
;

value utf_8_string_length s =
  loop 0 0 where rec loop i n =
    if i = String.length s then n
    else loop (i + 1) (if utf_8_cont_char s.[i] then n else n + 1)
;

value utf_8_string_sub s pos len =
  loop pos "" 0 where rec loop i t tlen =
    if i = String.length s then (t, i)
    else if tlen = len then
      if utf_8_cont_char s.[i] then
        let t = t ^ String.make 1 s.[i] in
        loop (i + 1) t tlen
      else (t, i)
    else
      let t = t ^ String.make 1 s.[i] in
      if utf_8_start_char s.[i] then loop (i + 1) t (tlen + 1)
      else loop (i + 1) t (if utf_8_cont_char s.[i] then tlen else tlen + 1)
;

value percent = 90;

value compute_field_sizes lines : list int =
  loop [] 0 where rec loop fsl nb_col =
    let szl =
      loop1 [] lines where rec loop1 szl =
        fun
        [ [line :: lines] →
            let szl =
              match List.nth_opt line nb_col with
              [ Some s → [utf_8_string_length s :: szl]
              | None → szl ]
            in
            loop1 szl lines
        | [] → szl ]
    in
    if szl = [] then List.rev fsl
    else
      let fs =
        let szl = List.sort compare szl in
        let len = List.length szl in
        let u = min 10 (List.nth szl (len - 1)) in
        max u
          (List.nth szl (max 0 ((len * percent + 100 / 2) / 100 - 1)))
      in
      loop [fs :: fsl] (nb_col + 1)
;

value rev_split_on_char_but_strings sep s =
  loop False 0 0 [] where rec loop in_string ibeg i rev_sl =
    if i = String.length s then
      if ibeg < i then [String.sub s ibeg (i - ibeg) :: rev_sl] else rev_sl
    else if s.[i] = '\"' then
      if i + 1 < String.length s then
        if s.[i+1] = '"' then loop in_string ibeg (i + 2) rev_sl
        else loop (not in_string) ibeg (i + 1) rev_sl
      else [String.sub s ibeg (String.length s - ibeg) :: rev_sl]
    else if in_string then loop in_string ibeg (i + 1) rev_sl
    else if s.[i] = sep then
      loop in_string (i + 1) (i + 1) [String.sub s ibeg (i - ibeg) :: rev_sl]
    else loop in_string ibeg (i + 1) rev_sl
;

value split_on_char_but_strings sep s =
  List.rev (rev_split_on_char_but_strings sep s)
;

value lines_of_csv_string sep content =
  List.map
    (fun line →
       List.map
         (fun s →
            let len = String.length s in
            if len > 1 && s.[0] = '"' && s.[len-1] = '"' then
              String.sub s 1 (len - 2)
            else s)
         (split_on_char_but_strings sep line))
    (String.split_on_char '\n'
       (let len = String.length content in
        if len > 0 && content.[len-1] = '\n' then
          String.sub content 0 (len - 1)
        else content))
;

value cut_at_space_if_possible s fs =
  loop fs where rec loop i =
    if i = 0 then
      let (s2, j) = utf_8_string_sub s 0 fs in
      let e = String.sub s j (String.length s - j) in
      (s2, e)
    else if s.[i] = ' ' then
      let s2 = String.sub s 0 i in
      let e = String.sub s (i + 1) (String.length s - i - 1) in
      (s2, e)
    else
      loop (i - 1)
;

value get_cut_line_and_extra fields_sizes line :
    option (list string * list string) =
  loop fields_sizes line [] [] False
  where rec loop fsl sl rev_line extra has_extra =
     match sl with
     | [s :: sl] →
         match fsl with
         | [fs :: fsl] →
             let (s, extra, has_extra) =
               if utf_8_string_length s > fs then
                 let (s2, e) = cut_at_space_if_possible s fs in
                 (s2, [e :: extra], True)
               else (s, ["" :: extra], has_extra)
             in
             loop fsl sl [s :: rev_line] extra has_extra
         | [] →
             loop fsl sl [s :: rev_line] extra has_extra
         end
     | [] →
         if has_extra then Some (List.rev rev_line, List.rev extra)
         else None
     end
;

value fold_long_lines fields_sizes (lines : list (list string)) =
  List.map
    (fun line →
       loop line where rec loop line =
         match get_cut_line_and_extra fields_sizes line with
         | Some (line2, extra2) → [line2 :: loop extra2]
         | None → [line]
         end)
    lines
;

value string_of_list to_string sl =
  loop "[" sl where rec loop c =
    fun
    | [] → "[]"
    | [s] → c ^ to_string s ^ "]"
    | [s :: sl] → c ^ to_string s ^ loop "; " sl
    end
;

value string_of_string x = "\"" ^ x ^ "\"";

value rec complete_by_spaces fsl sl =
  match sl with
  | [] →
      List.map (fun fs → String.make fs ' ') fsl
  | [s :: sl] →
      match fsl with
      | [] → [s :: sl]
      | [fs :: fsl] →
          if utf_8_string_length s ≤ fs then
            [s ^ String.make (fs - utf_8_string_length s) ' ' ::
             complete_by_spaces fsl sl]
          else
            (* not normal : extra line should have been cut too *)
            [s ^ "****************" :: complete_by_spaces fsl sl]
      end
  end
;

value cut_at_len = ref 190;

value complete_list_by_spaces fields_sizes flines =
  List.map (List.map (complete_by_spaces fields_sizes)) flines
;

value format_content fields_sizes (flines : list (list (list string))) =
  let fields_count = List.length fields_sizes in
  let border =
    String.make (List.fold_left \+  0 fields_sizes + fields_count + 1) '-'
  in
  let (border, _) = utf_8_string_sub border 0 (cut_at_len.val + 1) in
  border ^ "\n" ^
  String.concat "\n"
    (List.map
       (fun sll →
          "|" ^
          String.concat "\n|"
            (List.map
               (fun sl →
                  let s = String.concat "|" sl ^ "|" in
                  fst (utf_8_string_sub s 0 cut_at_len.val))
                sll) ^
          "\n" ^ border)
       flines)
;

value formatted_csv content sep nb_occ_of_sep : string = do {
  let content = strip_spaces content in
  let lines = lines_of_csv_string sep content in
  let fields_sizes = compute_field_sizes lines in
  let flines = fold_long_lines fields_sizes lines in
(**)
  let fields_sizes_again = compute_field_sizes (List.concat flines) in
  let flines = fold_long_lines fields_sizes_again lines in
  let flines = complete_list_by_spaces fields_sizes_again flines in
(*
  let flines = complete_list_by_spaces fields_sizes flines in
*)
  printf "=== fields_sizes";
  List.iter (fun sz → printf " %3d" sz) fields_sizes;
  printf "\n%!";
  printf "=== again fsizes";
  List.iter (fun sz → printf " %3d" sz) fields_sizes_again;
  printf "\n%!";
  format_content fields_sizes_again flines
(*
  format_content fields_sizes flines
*)
};

(* Main *)

value read_file fname = do {
  printf "=== file %s\n" fname;
  let ic = open_in fname in
  let len = in_channel_length ic in
  printf "=== length of file %d\n%!" len;
  let s = really_input_string ic len in
  close_in ic;
  let s =
    if String.length s <> 0 && s.[String.length s - 1] <> '\n' then s ^ "\n"
    else s
  in
  s
};

value print_defective_lines content c nb_occ_of_char =
  let lines = String.split_on_char '\n' content in
  List.iteri
    (fun i line →
       let (n', j) = number_of_occurrences c line 0 in
       let _ = assert (j = String.length line) in
       if n' <> nb_occ_of_char && n' <> 0 then
         printf "- line %d has %d field%s\n" (i + 1) (n' + 1)
           (if n' = 0 then "" else "s")
       else ())
    lines
;

value main () = do {
  let fname =
    if Array.length Sys.argv ≥ 2 then Sys.argv.(1)
    else do {
      eprintf "Usage: find_sep file [maxlen]\n";
      flush stderr;
      exit 1
    }
  in
  cut_at_len.val :=
    if Array.length Sys.argv = 3 then int_of_string Sys.argv.(2)
    else cut_at_len.val;
  (*
  let chars =
    loop [] lines where rec loop chars =
      fun
      [ [line :: lines] →
          loop1 0 chars where rec loop1 i chars =
            if i = String.length line then loop chars lines
            else if List.mem line.[i] chars then loop1 (i + 1) chars
            else loop1 (i + 1) [line.[i] :: chars]
      | [] → chars ]
  in
  let test = String.init (List.length chars) (fun i → List.nth chars i) in
  *)
  let test = ",;|\t:" in
  (*
    (* if choosing to test all characters, uncomment the strip_spaces in
       find_separator *)
    let test = String.init 256 Char.chr in
  *)
  (**)
  let content = read_file fname in
  (**)
  printf
    "=== tested chars : \"";
  String.iter (fun c → printf "%s" (Char.escaped c)) test;
  printf "\"\n%!";
  (**)
  printf
    "... testing...%!";
  let r = find_separator test content in
  printf "\rok            \n%!";
  let nb_lines = nb_lines_of content in
  List.iter
    (fun (c, nb_occ_of_char, nb_correct_lines, defective) →
       let criterion =
         criterion_value c nb_correct_lines nb_occ_of_char nb_lines
       in
       if criterion = 0 then ()
       else
         printf "=== separator '%s', criterion %d\n%!" (Char.escaped c)
           criterion)
    r;
  match r with
  [ [(c, nb_occ_of_char, nb_correct_lines, defective) :: _] → do {
      let sep = get_good_separator r in
      let nb_occ_of_char = get_nb_occ_of_char r in
      printf "- the separator is '%s'\n" (Char.escaped sep);
      printf "- number of fields: %d\n" (nb_occ_of_char + 1);
      if nb_correct_lines = nb_lines then
        printf "- all %d lines are correct\n" nb_correct_lines
      else do {
        printf "- correct in %d lines / %d\n" nb_correct_lines nb_lines;
        if defective = [] then ()
        else do {
          printf "- defective lines:\n";
          List.iter
            (fun (nb_occ_of_char, defective) →
               printf "  * %d having %d fields\n%!" defective
                 (nb_occ_of_char + 1))
            defective;
          print_defective_lines content c nb_occ_of_char
        }
      }
    }
  | [] → printf "separator not found\n%!" ];
  let sep = get_good_separator r in
  let nb_occ_of_char = get_nb_occ_of_char r in
  let content = formatted_csv content sep nb_occ_of_char in
  printf "\n%s\n%!" content
};

(* display like in shell command "LC_ALL=C lf -aF" *)

value display_like_ls labels width =
  let n = List.length labels in
  if n = 0 then ()
  else do {
    let arr = Array.of_list labels in
    (* Cherche le nombre de colonnes optimal *)
    let best_cols = ref 1 in
    let c = ref n in
    (* on part du max possible *)
    while
      c.val >= 1
    do {
      let rows = (n + c.val - 1) / c.val in
      (* largeur totale si on utilise !c colonnes :
         pour chaque colonne, on prend le label le plus large + 2 espaces *)
      let total_width = do {
        let sum = ref 0 in
        for col = 0 to c.val - 1 do {
          let col_max = ref 0 in
          for row = 0 to rows - 1 do {
            let idx = col * rows + row in
            if idx < n then
              col_max.val := max col_max.val (String.length arr.(idx))
            else ()
          };
          (* pas de padding après la dernière colonne *)
          sum.val :=
            sum.val + col_max.val + (if col < c.val - 1 then 2 else 0)
        };
        sum.val
      }
      in
      if total_width <= width then do { best_cols.val := c.val; c.val := -1 }
      else decr c
    };
    let cols = best_cols.val in
    let rows = (n + cols - 1) / cols in
    (* Calcule la largeur de chaque colonne *)
    let col_widths =
      Array.init cols
        (fun col -> do {
           let w = ref 0 in
           for row = 0 to rows - 1 do {
             let idx = col * rows + row in
             if idx < n then w.val := max w.val (String.length arr.(idx))
             else ()
           };
           w.val
         })
    in
    (* Affichage ligne par ligne *)
    for row = 0 to rows - 1 do {
      for col = 0 to cols - 1 do {
        let idx = col * rows + row in
        if idx < n then
          let label = arr.(idx) in
          if col < cols - 1 then
            (* pad à droite jusqu'à col_widths.(col) + 2 *)
            Printf.printf "%-*s  " col_widths.(col) label
          else print_string label
        else ()
      };
      print_char '\n'
    }
  }
;

value max_width = ref 80;

value main' () = do {
  let dname =
    if Array.length Sys.argv = 2 then do {
      try do {
        max_width.val := int_of_string Sys.argv.(1);
        "."
      } with
      [ Failure _ → Sys.argv.(1) ];
    }
    else if Array.length Sys.argv = 3 then do {
      try do {
        max_width.val := int_of_string Sys.argv.(2);
        Sys.argv.(1)
      }
      with
      [ Failure _ →
          try do {
            max_width.val := int_of_string Sys.argv.(1);
            Sys.argv.(2);
          }
          with [ Failure _ → Sys.argv.(1) ] ];
    }
    else "."
  in
  printf "dname %s\nwidth %d\n%!" dname max_width.val;
  let a = Sys.readdir dname in
  let a = Array.append a [| "."; ".." |] in
  Array.sort String.compare a;
  for i = 0 to Array.length a - 1 do {
    let f = dname ^ "/" ^ a.(i) in
    if Sys.is_directory f then a.(i) := a.(i) ^ "/" else ();
  };
  display_like_ls (Array.to_list a) max_width.val;
};

if Sys.interactive.val then () else main ();
