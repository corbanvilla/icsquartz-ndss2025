(*#-#-#-#-#-#-#-#-#-#---Declaration---#-#-#-#-#-#-#-#-#-#-#-#-#*)

VAR_GLOBAL CONSTANT
	NETWORK_BUFFER_LONG_SIZE : UINT := 4095;
END_VAR


(*#-#-#-#-#-#-#-#-#-#---Declaration---#-#-#-#-#-#-#-#-#-#-#-#-#*)

TYPE
	NW_BUF_LONG  : ARRAY[0..NETWORK_BUFFER_LONG_SIZE] OF BYTE;
END_TYPE


(*#-#-#-#-#-#-#-#-#-#---Declaration---#-#-#-#-#-#-#-#-#-#-#-#-#*)

TYPE XML_CONTROL :
STRUCT
	COMMAND : WORD;
	WATCHDOG : TIME;
	START_POS : UINT;
	STOP_POS : UINT;
	COUNT : UINT;
	TYP : INT;
	LEVEL : UINT;
	PATH : STRING(STRING_LENGTH);
	ELEMENT : STRING(STRING_LENGTH);
	ATTRIBUTE : STRING(STRING_LENGTH);
	VALUE : STRING(STRING_LENGTH);
	BLOCK1_START : UINT;
	BLOCK1_STOP : UINT;
	BLOCK2_START : UINT;
	BLOCK2_STOP : UINT;
END_STRUCT
END_TYPE


(*#-#-#-#-#-#-#-#-#-#---Declaration---#-#-#-#-#-#-#-#-#-#-#-#-#*)

FUNCTION_BLOCK XML_READER
VAR_IN_OUT
	CTRL : XML_CONTROL;
	BUF : NW_BUF_LONG;
END_VAR
VAR
	index :	INT;
	index2 : INT;
	stop : INT;
	mode : INT;
	command : WORD;
	c :	BYTE;
	s1 : INT;
	e1 : INT;
	path_overflow : BOOL;
	empty_tag : BOOL;
	s_code : STRING(10);
	e_code : STRING(10);
	watchdog : TON;

	(*LOG_MSG : LOG_MSG;
	_debug_enable : BOOL := TRUE;*)

END_VAR

(*

version 1.2      10. May 2010
programmer   ks
tested by       ks

XML_READER enables the serial parsing and evaluation of XML elements in a buffer
*)

(*#-#-#-#-#-#-#-#-#-#---Implementation---#-#-#-#-#-#-#-#-#-#-#-#-#*)

(*

TYPE
00 = UNKNOWN
01 = ELEMENT (STANDARD)
02 = CLOSE ELEMENT 
03 = TEXT
04 = ATTRIBUTE
05 = ELEMENT (PROCESSING INSTRUCTION)

12 = !CDATA
13 = !COMMENT
14 = !DTD ELEMENT (Document Type Declarations)

98 = WATCHDOG
99 = END

For Type 02, no block data is output!

*)

(* ---------- Init -------------- *)
IF BIT_OF_DWORD(WORD_TO_DWORD(CTRL.COMMAND),15) THEN
	COMMAND := CTRL.COMMAND;
	CTRL.COMMAND := WORD#0;

	index := UINT_TO_INT(CTRL.START_POS);
	stop := UINT_TO_INT(CTRL.STOP_POS);
	mode := 100;
	path_overflow := FALSE;

	CTRL.TYP := 0;
	CTRL.COUNT := UINT#00;
	CTRL.LEVEL := UINT#00;
	CTRL.ATTRIBUTE := '';
	CTRL.ELEMENT := '';
	CTRL.PATH := '';
	CTRL.VALUE := '';

	WATCHDOG.PT := CTRL.WATCHDOG;
END_IF;

(*----------------------------------------------- *)

IF index < 0 THEN RETURN;END_IF;

CTRL.BLOCK1_START := UINT#0;
CTRL.BLOCK1_STOP := UINT#0;
CTRL.BLOCK2_START := UINT#0;
CTRL.BLOCK2_STOP := UINT#0;

WATCHDOG(IN:=FALSE); (* Timer stoppen *)

WHILE (TRUE) DO

	(* -------------- WATCHDOG ------------------ *)
	(* CTRL.WATCHDOG is a timeout (in seconds) *)
	WATCHDOG(IN:=CTRL.WATCHDOG > T#0s);
	IF WATCHDOG.Q THEN
		CTRL.TYP := 98;
    		(*####################  DEBUG-MESSAGE  ###################################*)
    		(*IF _debug_enable THEN
      			LOG_CL.NEW_MSG := 'WATCHDOG:';
      			LOG_MSG();
    		END_IF;*)
    		(*########################################################################*)
			(* Exit here on timeout *)
			// printf('Exiting on watchdog timeout$N');
		RETURN;
	END_IF;

	(* -------------- PARSING END ------------------ *)
	IF index > stop THEN
		CTRL.COUNT := CTRL.COUNT + UINT#1;
		CTRL.TYP := 99;
    		(*####################  DEBUG-MESSAGE  ###################################*)
    		(*IF _debug_enable THEN
      			LOG_CL.NEW_MSG := 'EX: #T:~1 #C:~2 #P:~6 #L:~7';
      			LOG_CL.PRINTF[1] := INT_TO_STRING(CTRL.TYP);
      			LOG_CL.PRINTF[2] := UINT_TO_STRING(CTRL.COUNT);
      			LOG_CL.PRINTF[6] := CTRL.PATH;
      			LOG_CL.PRINTF[7] := UINT_TO_STRING(CTRL.LEVEL);
      			LOG_MSG();
    		END_IF;*)
    		(*########################################################################*)
		mode  := 0; (* Schritt ruecksetzen *)
		index := 0; (* Abarbeitung stoppen *)
		// printf('(index > stop) -> done parsing$N');
		RETURN;
	END_IF;

	CASE mode OF

	100: (* ---------- ELEMENT SECTION ------------------ *)
		// printf('Made it to case:100$N');
		(* search begin of element *)
		s1 := 0;
		e1 := 0;
		WHILE (index <= stop) DO
			(* Look for where the tag begins *)
			IF BUF[INDEX]=BYTE#60 THEN (* '<' TagBegin *)
				index := index + 1;
				C := BUF[index];
				(* Look for where the term begins *)
				IF C = BYTE#47 THEN (* '/' TagTerm *)
					mode := 300; (* End Element Section *)
				(* Unknown section *)
				ELSIF C = BYTE#33 THEN (* '!' for Special Section *)
					index := index + 1;
					mode := 500;
				ELSE
					s1 := index;
				END_IF;
				EXIT;
			END_IF;
			index := index + 1;
		END_WHILE;

		(* analyse element *)
		CTRL.TYP := 0; (* Clear TYP *)
		IF s1 > 0 THEN
			WHILE (index <= stop AND e1 = 0) DO
				c := BUF[index];
				(* whitespace character = Element with Attributes *)
				IF c <= BYTE#32 THEN
					(* search next printable character *)
					index2 := index;
					WHILE (index2 <= stop) AND (BUF[index2] <= BYTE#32) DO
						index2 := index2 + 1;
					END_WHILE;
					IF BUF[index2] = BYTE#47 THEN (* check for empty element '/' *)
						index := index2;
						e1 := index - 2;
						CTRL.TYP := 1; (* structure-element *)
						mode := 300;   (* Close Element *)
						EXIT;
					END_IF;

					e1 := index - 1;
					CTRL.TYP := 1; (* Element with Attribute *)
					mode := 400;

				ELSIF c = BYTE#62 THEN (* '>' TagEnd *)

					(* check for empty element <xx/> *)
					index2 := index - 1;
					IF BUF[index2] = BYTE#47 THEN (* TagTerm '/' *)
						e1 := index2 - 1;
						CTRL.TYP := 1;
						EMPTY_TAG := TRUE; (* EMPTY TAG Mode *)
						mode := 200; (* TEXT Element *)
						EXIT;
					END_IF;

					e1 := index - 1;
					index2 := index + 1;

					(* examine subsequent element *)
					WHILE (index2 <= stop) DO
						c := BUF[index2];
						IF c = BYTE#60 THEN (* '<' TagBegin *)

							index2 := index2 + 1; (* unfortunately can't be done differently in PCWORX! *)
							c := BUF[index2];
							index2 := index2 - 1;
							IF c = BYTE#47 THEN (* TagTerm '/' *)
								empty_tag := TRUE;
								mode := 200; (* TEXT Element *)
							ELSE
								mode := 100; (* Element *)
							END_IF;
							CTRL.TYP := 1; (* structure-element *)
							EXIT;
						ELSIF c > BYTE#32  THEN (* Printable-Character *)
							CTRL.TYP := 1; (* element with text *)
							mode := 200;
							EXIT;
						END_IF;
						index2 := index2 + 1;
					END_WHILE;
				END_IF;
				index := index + 1;
			END_WHILE;
		END_IF;

		(* New element found *)
		IF CTRL.TYP > 0 THEN

			(* Special check for Processing Instruction (PI) *)
			IF BUF[s1] = BYTE#63 THEN (* '?' for Processing Instruction *)
				s1 := s1 + 1; (* skip leading '?' *)
				CTRL.TYP := 5;
			END_IF;
			CTRL.BLOCK1_START := INT_TO_UINT(s1);
			CTRL.BLOCK1_STOP  := INT_TO_UINT(e1);
			CTRL.ELEMENT := BUFFER_TO_STRING(PT:=ADR(BUF),SIZE:=INT_TO_UINT(stop + 1),START:=CTRL.BLOCK1_START,STOP:=CTRL.BLOCK1_STOP);
			CTRL.COUNT := CTRL.COUNT + UINT#1;
			CTRL.LEVEL := CTRL.LEVEL + UINT#1;

			IF path_overflow = FALSE THEN
				(* Monitor string length *)
				IF LEN(CTRL.PATH) + LEN(CTRL.ELEMENT) + 1 > 250 THEN
					path_overflow := TRUE;
					CTRL.PATH := 'OVERFLOW';
				ELSE
					CTRL.PATH := CONCAT(CTRL.PATH,'/');
					CTRL.PATH  := CONCAT(CTRL.PATH,CTRL.ELEMENT);
				END_IF;
			END_IF;

			IF BIT_OF_DWORD(WORD_TO_DWORD(COMMAND),CTRL.TYP) THEN
						(*####################  DEBUG-MESSAGE  ###################################*)
						(*IF _debug_enable THEN
							LOG_CL.NEW_MSG := 'EL: #T:~1 #C:~2 #E:~3 #P:~6 #L:~7';
							LOG_CL.PRINTF[1] := INT_TO_STRING(CTRL.TYP);
							LOG_CL.PRINTF[2] := UINT_TO_STRING(CTRL.COUNT);
							LOG_CL.PRINTF[3] := CTRL.ELEMENT;
							LOG_CL.PRINTF[6] := CTRL.PATH;
							LOG_CL.PRINTF[7] := UINT_TO_STRING(CTRL.LEVEL);
							LOG_MSG();
						END_IF;*)
						(*########################################################################*)
				RETURN;
			END_IF;
		END_IF;

	200: (* ---------- TEXT SECTION ------------------ *)
		// printf('Made it to case:200$N');
		CTRL.VALUE := '';
		IF empty_tag = FALSE THEN
			s1 := index;
			(* search for '<' EndTag *)
			WHILE (index <= stop) AND (BUF[index] <> BYTE#60) DO
				index := index + 1;
			END_WHILE;

			(* Store where the text ends *)
			E1 := index - 1;
			CTRL.BLOCK1_START := INT_TO_UINT(s1);
			CTRL.BLOCK1_STOP  := INT_TO_UINT(e1);
			(* Save extracted text *)
			CTRL.VALUE := BUFFER_TO_STRING(PT:=ADR(BUF),SIZE:=INT_TO_UINT(stop + 1),START:=CTRL.BLOCK1_START,STOP:=CTRL.BLOCK1_STOP);
			// printf('Saved TEXT value: %s$N', ADR(CTRL.VALUE));
		END_IF;

		empty_tag := FALSE;
		mode := 300; (* -> NEXT-JOB: END ELEMENT *)
		CTRL.COUNT := CTRL.COUNT + UINT#1;
		CTRL.TYP := 3;

		IF BIT_OF_DWORD(WORD_TO_DWORD(command),CTRL.TYP) THEN
      			(*####################  DEBUG-MESSAGE  ###################################*)
      			(*IF _debug_enable THEN
        				LOG_CL.NEW_MSG := 'TE: #T:~1 #C:~2 #E:~3 #V:~4 #P:~6 #L:~7';
        				LOG_CL.PRINTF[1] := INT_TO_STRING(CTRL.TYP);
        				LOG_CL.PRINTF[2] := UINT_TO_STRING(CTRL.COUNT);
        				LOG_CL.PRINTF[3] := CTRL.ELEMENT;
        				LOG_CL.PRINTF[4] := CTRL.VALUE;
        				LOG_CL.PRINTF[6] := CTRL.PATH;
        				LOG_CL.PRINTF[7] := UINT_TO_STRING(CTRL.LEVEL);
        				LOG_MSG();
      			END_IF;*)
      			(*########################################################################*)
			RETURN;
		END_IF;

	300: (* ---------- END ELEMENT SECTION ------------------ *)
		// printf('Made it to case:300$N');
		WHILE (index <= stop) DO
			c := BUF[index];
			(* Look for the end of the tag *)
			IF c = BYTE#62 THEN (* '>' TagEnd *)
				index := index + 1;
				s1 := FINDB(str1:=CTRL.PATH,str2:='/');
				IF path_overflow = FALSE THEN
					IF s1 > 1 THEN
						CTRL.ELEMENT := RIGHT(CTRL.PATH,LEN(CTRL.PATH) - s1);
						CTRL.PATH := LEFT(CTRL.PATH,s1 - 1);
					ELSE
						CTRL.ELEMENT := RIGHT(CTRL.PATH,LEN(CTRL.PATH) - 1);
						CTRL.PATH :='';
					END_IF;
				END_IF;

				CTRL.LEVEL := CTRL.LEVEL - UINT#1;
				CTRL.COUNT := CTRL.COUNT + UINT#1;
				CTRL.TYP := 2;
				mode := 100;

				IF BIT_OF_DWORD(WORD_TO_DWORD(COMMAND),CTRL.TYP) THEN
         	 				(*####################  DEBUG-MESSAGE  ###################################*)
          				(*IF _debug_enable THEN
            					LOG_CL.NEW_MSG := 'CE: #T:~1 #C:~2 #E:~3 #P:~6 #L:~7';
            					LOG_CL.PRINTF[1] := INT_TO_STRING(CTRL.TYP);
            					LOG_CL.PRINTF[2] := UINT_TO_STRING(CTRL.COUNT);
            					LOG_CL.PRINTF[3] := CTRL.ELEMENT;
            					LOG_CL.PRINTF[6] := CTRL.PATH;
            					LOG_CL.PRINTF[7] := UINT_TO_STRING(CTRL.LEVEL);
            					LOG_MSG();
          				END_IF;*)
          				(*########################################################################*)
					RETURN;
				ELSE
					EXIT;
				END_IF;
			END_IF;
			index := index + 1;
		END_WHILE;

	400: (* ---------- ATTRIBUTE SECTION ------------------ *)
		// printf('Made it to case:400$N');
		(* search first normal charakter *)
		WHILE (index <= stop AND BUF[index] <= BYTE#32) DO
			index := index + 1;
		END_WHILE;

		(* begin Attribe name *)
		e1 := 0;
		s1 := index;
		(* search end of Attrib Name '=' *)
		WHILE (index <= stop) DO
			IF BUF[index] = BYTE#61 THEN (* '=' Equals *)
				e1 := index - 1;
				EXIT;
			END_IF;
			index := index + 1;
		END_WHILE;

		IF e1 > 0 THEN
			(* Attribute Name *)
			CTRL.BLOCK1_START := INT_TO_UINT(s1);
			CTRL.BLOCK1_STOP  := INT_TO_UINT(e1);
			CTRL.ATTRIBUTE := BUFFER_TO_STRING(PT:=ADR(BUF),SIZE:=INT_TO_UINT(STOP + 1),START:=CTRL.BLOCK1_START,STOP:=CTRL.BLOCK1_STOP);
			(* search end of Attrib Value '=' *)
			index := index + 2;
			e1 := 0;
			s1 := INDEX;
			WHILE (index <= stop AND e1 = 0) DO
				c := BUF[index];
				IF c = BYTE#34 OR c = BYTE#39 THEN (* " OR ' Equals *)
					e1 := index - 1;
				END_IF;
				index := index + 1;
			END_WHILE;

			IF e1 > 0 THEN
				(* Value *)
				CTRL.BLOCK2_START := INT_TO_UINT(s1);
				CTRL.BLOCK2_STOP  := INT_TO_UINT(e1);

				(* For empty "" (quotes), the start is greater than the stop, and thus becomes an empty string. *)
				CTRL.VALUE := BUFFER_TO_STRING(PT:=ADR(BUF),SIZE:=INT_TO_UINT(stop + 1),START:=CTRL.BLOCK2_START,STOP:=CTRL.BLOCK2_STOP);
				(* search next non white space charakter *)
				WHILE (index <= stop AND BUF[index] <= BYTE#32) DO
					index := index + 1;
				END_WHILE;

					c := BUF[index];
					(* TagEnd '>' *)
					IF c = BYTE#62 THEN
						index := index + 1;
						index2 := index;

					(* search next non white space charakter *)
					WHILE (index <= stop AND BUF[index] <= BYTE#32) DO
						index := index + 1;
					END_WHILE;

					IF BUF[index] = BYTE#60 THEN (* TagBegin '<' *)
						mode := 100; (* -> NEXT-JOB: ELEMENT-SECTION *)
					ELSE
						index := index2;
						mode := 200; (* -> NEXT-JOB: TEXT-SECTION *)
					END_IF;

				ELSIF c = BYTE#47 OR c = BYTE#63 THEN (* TagTerm '/' OR '?' end Processing Instruction *)
					mode := 300; (* -> NEXT-JOB: END ELEMENT *)
				ELSE
					mode := 400; (* -> NEXT-JOB: ATTRIBUTE-SECTION *)
				END_IF;

				CTRL.COUNT := CTRL.COUNT + UINT#1;
				CTRL.TYP := 4;
				IF BIT_OF_DWORD(WORD_TO_DWORD(command),CTRL.TYP) THEN
          				(*####################  DEBUG-MESSAGE  ###################################*)
          				(*IF _debug_enable THEN
            					LOG_CL.NEW_MSG := 'AT: #T:~1 #C:~2 #E:~3 #A:~4 #V:~5 #P:~6 #L:~7';
            					LOG_CL.PRINTF[1] := INT_TO_STRING(CTRL.TYP);
            					LOG_CL.PRINTF[2] := UINT_TO_STRING(CTRL.COUNT);
            					LOG_CL.PRINTF[3] := CTRL.ELEMENT;
            					LOG_CL.PRINTF[4] := CTRL.ATTRIBUTE;
            					LOG_CL.PRINTF[5] := CTRL.VALUE;
            					LOG_CL.PRINTF[6] := CTRL.PATH;
            					LOG_CL.PRINTF[7] := UINT_TO_STRING(CTRL.LEVEL);
            					LOG_MSG();
          				END_IF;*)
          				(*########################################################################*)
					RETURN;
				END_IF;
			END_IF;
		END_IF;

	500: (* ---------- SPECIAL DATA SECTION (Document Type Declarations) ---------- *)
		// printf('Made it to case:500$N');

		CTRL.TYP := 0;
		s1 := 0;
		index2 := 11;

		WHILE (s1 = 0) DO
			index2 := index2 + 1;
			CTRL.TYP := index2;

			CASE index2 OF
			12: (* CDATA *)
				s_code := '[CDATA[';
				e_code := ']]>';
			13: (* COMMENT *)
				s_code := '--';
				e_code := '-->';
			14: (* ANY DTD *)
				e_code := '';
				s1 := index;
				EXIT;
			END_CASE;

			e1 := LEN(s_code);
			IF BUFFER_SEARCH(PT:=ADR(BUF),SIZE:=INT_TO_UINT(index + e1),STR:=S_CODE,POS:=index,IGN:=FALSE) = INDEX THEN
				s1 := index + e1;
			END_IF;
		END_WHILE;

		CTRL.BLOCK1_START := INT_TO_UINT(s1);
		IF LEN(e_code) > 0 THEN
			(* search for end identifier *)
			e1 := BUFFER_SEARCH(PT:=ADR(BUF),SIZE:=INT_TO_UINT(stop + 1),STR:=e_code,POS:=index,IGN:=FALSE);
			CTRL.BLOCK1_STOP := INT_TO_UINT(e1 - 1);
			index := e1 + LEN(e_code); (* naechstes element *)
		ELSE
			(* search '>' EndTag*)
			index2 := 1; (* <> pair counter *)
			WHILE (index <= stop AND index2 > 0) DO
				c := BUF[index];
				IF c = BYTE#60 THEN (* '<' TagBegin *)
					index2 := index2 + 1;
				ELSIF c = BYTE#62 THEN (* '>' TagEnd   *)
					index2 := index2 - 1;
				ELSIF c = BYTE#34 OR c = BYTE#39 THEN (* " Double Quote OR ' Single Quote *)
					index := index + 1;
					WHILE (index <= stop) DO
						c := BUF[index];
						IF c = BYTE#34 OR c = BYTE#39 THEN (* " Double Quote OR ' Single Quote *)
							EXIT;
						END_IF;
						index := index + 1;
					END_WHILE;
				END_IF;
				index := index + 1;
			END_WHILE;
			CTRL.BLOCK1_STOP := INT_TO_UINT(index - 2);
		END_IF;

		CTRL.VALUE := BUFFER_TO_STRING(PT:=ADR(BUF),SIZE:=INT_TO_UINT(stop + 1),START:=CTRL.BLOCK1_START,STOP:=CTRL.BLOCK1_STOP);
		CTRL.COUNT := CTRL.COUNT + UINT#1;
		mode := 100; (* -> NEXT-JOB: ELEMENT *)

		IF BIT_OF_DWORD(WORD_TO_DWORD(command),CTRL.TYP) THEN
      			(*####################  DEBUG-MESSAGE  ###################################*)
      			(*IF _debug_enable THEN
        				LOG_CL.NEW_MSG := 'DTD: #T:~1 #C:~2 #S:~3 #E:~4 #V:~5 #P:~6 #L:~7';
        				LOG_CL.PRINTF[1] := INT_TO_STRING(CTRL.TYP);
        				LOG_CL.PRINTF[2] := UINT_TO_STRING(CTRL.COUNT);
        				LOG_CL.PRINTF[3] := UINT_TO_STRING(CTRL.BLOCK1_START);
        				LOG_CL.PRINTF[4] := UINT_TO_STRING(CTRL.BLOCK1_STOP);
        				LOG_CL.PRINTF[5] := CTRL.VALUE;
        				LOG_CL.PRINTF[6] := CTRL.PATH;
        				LOG_CL.PRINTF[7] := UINT_TO_STRING(CTRL.LEVEL);
        				LOG_MSG();
      			END_IF;*)
      			(*########################################################################*)
			RETURN;
		END_IF;

	END_CASE;
END_WHILE;


(* revision history
ks	18. oct. 2008	rev 1.0
	original version

ks	20. oct. 2009	rev 1.1
	Networkbuffer und Buffer-funktionen auf Basis 0

ks	10. mai. 2010	rev 1.2
	stringlänge maximal 250 zeichen

*)

END_FUNCTION_BLOCK

(*#-#-#-#-#-#-#-#-#-#---Declaration---#-#-#-#-#-#-#-#-#-#-#-#-#*)

PROGRAM PLC_PRG
VAR
    BUF : NW_BUF_LONG;
    XML_READER: XML_READER;
    XML_CONTROL: XML_CONTROL;
END_VAR

XML_READER(CTRL:=XML_CONTROL, BUF:=BUF);

END_PROGRAM
