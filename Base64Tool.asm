; THE COMMAND LINE PARAMS MUST BE SET LIKE THIS: 
;                   -e(or d) inputfilename.txt outputfilename.txt;   
;                    THE ";" AT THE END IS MANDATORY
; BOTH FILES MUST EXIST, THE PROGRAM WILL NOT CREATE THE OUTPUT FILE

.model large
include fisio.h
.stack 80h

.data
	input_file db 100 dup (?) ; will hold input file name 
	output_file db 100 dup (?) ; will hold output file name
	hand_in dw ? ; input file handler 
	hand_out dw ? ; output file handler
	buf dw 16 dup(2) ; reading and writing from file buffer
	rez_in dw ? ; result for open in_file macro
	rez_out dw ? ; result for open out_file macro
	OctCit dw ? ; read bytes
	OctScr dw ? ; written bytes 
    OctDeCit dw 3
    OctDeScr dw 4
    padding dw 0
    is_final_loop dw 1
    
	flag_encoding dw 652Dh ; "e-" in the registers the values will be inversed
	flag_decoding dw 642Dh ; "d-"
	flag_error db 'The flag can be -e for encoding or -d for decoding','$'
	eror_in db 'INPUT file error! Check if the file exists or the filename is correct. Or check the flag!', 13,10,'$'
    eror_out db 'OUTPUT file error! Check if the file exists or the filename is correct. Or check the flag!', 13,10,'$'
	
	b64_chars db 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/', 0h

.code 
start: 
; initialize data
	MOV AX, @data
	MOV DS, AX

; ====== ENCODE AND DECODE WORKFLOW ======

EncodeMacro MACRO

    encode_loop:
; read 3 bytes at a time from in_file
	MOV AH, 3fh
	MOV BX, hand_in
	LEA DX, buf
	MOV CX, 3
	INT 21h
	JC NOK
	MOV OctCit, AX
	MOV rez_in, 0
	JMP continue
NOK:
; error code in AX
	MOV rez_in, AX

continue:
    CMP OctCit, 0 ; check if reached the end of file 
    JZ encode_over

    CMP OctCit, 3 ; if there were less than 3 bytes read, this is the last loop
                  ; and continue with padding
    JE continue_no_padding
    call far ptr add_padding 

continue_no_padding:
	XOR SI, SI
; push 4 bytes to stack even though only 3 are needed
; because it's a multiple of register size
encode_prep_stack: 
	MOV AX, [buf+SI]
    PUSH AX
	INC SI 
    INC SI
	
	CMP SI, 4
	JE encode_bytes_read
	
	LOOP encode_prep_stack

encode_bytes_read: 

    call far ptr encoding_procedure ; push 4 more bytes after the variables already there (lines 64-67)

    call far ptr result_to_buf      ; puts encoded data (4 bytes) in the buffer

    CMP OctCit, 3 
    JE write
 
; if less than 3 bytes are read, we need to add padding 
; first add the padding to the buffer
; then write the buffer to the file
; this also marks the final loop 
    MOV is_final_loop, 0 

    MOV DX, 3D3Dh ;"=" "="
    MOV [buf+3], DX
    CMP OctCit, 1
    JNE write
    MOV [buf+2], DX
	
write:
	ScrieInFisier hand_out,buf,OctDeScr,OctScr,rez_out

    CMP is_final_loop, 0 
    JE encode_over
	
    JMP encode_loop

encode_over:
	InchideFisier hand_in,rez_in
	InchideFisier hand_out, rez_out
	exit_dos
ENDM    

; ==============

DecodeMacro MACRO
decode_loop:

	CitesteDinFisier hand_in,buf,4,OctCit,rez_in

    CMP OctCit, 0 
    JZ decode_over

; setup stack for B64Lookup
; every word on stack contain one byte for manipulation, discard the other one

	XOR SI, SI
decode_bytes_read:  
	MOV AX, [buf + SI]
    PUSH AX
    INC SI
    CMP SI, 4
    JNE decode_bytes_read

; decode:
    call far ptr B64Llookup 
    call far ptr decode
; result is in AX and BX

; write the decoded bytes to buffer
; we want to write the bytes to the buffer in the exact order in which they are in the registers
    MOV DL, AH
    MOV DH, AL
    MOV [buf], DX
    MOV DL, BH
    MOV DH, BL
    MOV [buf+2], DX 

; how many bytes to write in the file, considering how many bytes of padding we had
; 1 byte of padding => we will write only 2 bytes
; 2 bytes of padding => we will write only 1 byte
    XOR CX, CX
    MOV CX, 3
    SUB CX, padding ; if there were no bytes of padding, we will write 3 bytes
    MOV OctDeScr, cx   
	
	ScrieInFisier hand_out,buf,OctDeScr,OctScr,rez_out
	
	CMP OctCit, 4
	JB decode_over
	
	JMP decode_loop

decode_over:
	InchideFisier hand_in,rez_in
	InchideFisier hand_out, rez_out
	exit_dos

ENDM

; ====== START ======
; this is where the program execution actually starts

; read file names from command line 
	MOV BX, 85h ;85h is where the input filename starts in ES
    XOR AX, AX
	XOR SI, SI

; put the entire file name in input_file variable char by char until first space    
input_filename_read_loop: 
    MOV AH, ES:BX
    MOV [input_file + SI], AH
    INC BX
	INC SI
    MOV AH, ES:BX
    CMP AH, 20h ; 20h = space 
    JNZ input_filename_read_loop

	MOV input_file[SI], 0h  ; add the string terminator

; prepare for output filename read
	INC BX 
	XOR SI, SI
output_filename_read_loop:
	MOV AH, ES:BX 
    MOV [output_file + SI], AH
    INC BX
	INC SI
    MOV AH, ES:BX
    CMP AH, 3Bh ; ";" marks the end of the output filename
    JNZ output_filename_read_loop

	MOV output_file[SI], 0h ; adds the string terminator	 
	
    DeschideFisier input_file,0,hand_in,rez_in
	CMP rez_in, 0
	JNZ eroare_in
	
	DeschideFisier output_file,2,hand_out,rez_out
	CMP rez_out, 0
	JNZ eroare_out
	
	JMP check_flag
	
eroare_in:
	puts eror_in
	exit_dos
	
eroare_out:
	puts eror_out
	exit_dos

; check encode or decode flag
check_flag:
    XOR AX, AX
    MOV BX, 82h
    MOV AX, ES:BX ; move user flag input to AX register
	; the values are inversed: first it's the letter, then the "-"

    MOV DX, flag_decoding
    CMP DX, AX 
    JE set_decode 
	JMP check_encode ; skip decoding and continue to check if the encoding flag was used
	; otherwise run the following decoding instructions
	
set_decode:
    MOV OctDeCit, 4
    MOV OctDeScr, 3
    DecodeMacro	
	
check_encode:	
	MOV DX, flag_encoding
	CMP DX, AX
	JZ set_encode
	JMP finish ; if the flag was neither the encoding or the decoding one

set_encode:
	EncodeMacro	
	
; if the flag was not set correctly by the user, print a message and exit the program
finish:	
	puts flag_error
	exit_dos

; ====== PROCEDURES ======

; copy encoded result to buffer
result_to_buf PROC FAR 
    MOV SI, AX
    MOV AL, [b64_chars+SI]
    MOV SI, 0
    MOV [buf+SI], AX

    MOV SI, BX
    MOV BL, [b64_chars+SI]
    MOV SI, 1
    MOV [buf+SI], BX
    
    MOV SI, CX
    MOV CL, [b64_chars+si]
    MOV SI, 2
    MOV [buf+SI], CX

    MOV SI, DX
    MOV DL, [b64_chars+SI]
    MOV SI, 3
    MOV [buf+SI], DX

    RETF
result_to_buf ENDP
    
encoding_procedure PROC FAR 
    PUSH BP
    MOV BP, SP

	XOR AX, AX
	XOR BX, BX

; shift bytes with regard to adding 2 extra bits to their left
; AND with mask to get B64 corresponding index
    MOV AX, [BP + 8] 
    MOV DL, AH ; xchg al, ah to keep the order of the bytes
    MOV DH, AL
    MOV AX, DX   
    MOV BX, [BP + 6]   
    MOV CL, 10  
    SHR AX, CL      
    AND AX, 63
	PUSH AX ; 1st byte

    MOV AX, [BP + 8]   
    MOV DL, AH
    MOV DH, AL
    MOV AX, DX  
    MOV BX, [BP + 6] 
    MOV CL, 4
    SHR AX, CL
    AND AX, 63
	PUSH AX ; 2nd byte

    MOV AX, [BP + 8] 
    MOV DL, AH
    MOV DH, AL
    MOV AX, DX   
    MOV BX, [BP + 6] 
    MOV CL, 6
    SHR BX, CL
    AND BX, 3
    MOV CL, 2
    SHL AX, CL
    AND AX, 60
    ADD AX, BX
    AND AX, 63
	PUSH AX ; 3rd byte

    MOV AX, [BP + 8] 
    MOV DL, AH
    MOV DH, AL
    MOV AX, DX    
    MOV BX, [BP + 6] 
    AND BX, 63
	PUSH BX ; 4th byte

    POP DX ; 4th byte
    POP CX ; 3rd byte
    POP BX ; 2nd byte
    POP AX ; 1st byte

    POP BP
    RETF

encoding_procedure ENDP

add_padding PROC FAR
    MOV AX, 3
    MOV BX, OctCit
    SUB AX, BX

; add padding as needed
    MOV DX, 0
    MOV SI, 2
    MOV [buf+SI], DX ; add one "=" by default 
    CMP AX, 2  ; add the second "=" if needed
    JNE bye
    MOV SI, 1
    MOV [buf+SI], DX

bye:    
    RETF
add_padding ENDP

B64Llookup PROC FAR  
    PUSH BP
    MOV BP, SP

    MOV CX, 4
    MOV SI, 6
    XOR BX, BX
    XOR AX, AX ; will hold padding

; get the coresponding b64 value for each char
lookuploop: 
    MOV DX, [BP+SI]

    cmp DL, 61 ; "="
    JZ manage_padding
    
    cmp DL, 43 ; "+"
    JZ plus

    cmp DL, 47 ; "/"
    JZ slash

    cmp DL, 58
    JL get_num_val ; check if number

    cmp DL, 91
    JL get_uppercase

    cmp DL, 123
    JL get_lowercase

    manage_padding:
    MOV DL, 0
    INC AX 
    JMP resume

    plus:
    MOV DL, 62
    JMP resume

    slash:
    MOV DL, 63
    JMP resume

    get_num_val:
    ADD DL, 4
    JMP resume

    get_uppercase:
    SUB DL, 65
    JMP resume

    get_lowercase:
    SUB Dl, 71

resume: 
    MOV DH, 0
    MOV [BP+SI], DX
    ADD SI, 2
    LOOP lookuploop

    MOV padding, AX
    POP BP
    RETF

B64Llookup ENDP
    

decode PROC FAR
    PUSH BP
    MOV BP, SP

; shift bytes read, discarding every first 2 bits
    MOV AX, [BP+12]
    MOV CL, 10
    SHL AX, CL

; 1st byte
    MOV BX, [BP+10]
    MOV CL, 4
    SHL BX, CL
    ADD AX, BX 

; 2nd byte
    XOR BX, BX
    MOV BX, [BP+8]
    MOV CL, 2
    SHR BX, CL
    ADD AX, BX

; 3rd byte
    XOR BX, BX
    MOV BX, [BP+6]
    MOV CL, 8
    SHL BX, CL
    MOV DX, [BP+8]
    MOV CL, 14
    SHL DX, CL
    ADD BX, DX
; answer is in AX and BX

    POP BP 
    RETF

decode ENDP

end start    