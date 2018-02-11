        include Win64API.inc

        .DATA

;---------------------
; EQUATES 
;---------------------

MAX_RAM             EQU     1024                            ;Maximum size of emulated CPU's RAM
INVALID_HANDLE      EQU     -1                              ;CreateFile returns this value if it failed
_CR                 EQU     0Dh                             ;Carriage return character
_LF                 EQU     0Ah                             ;Line Feed (new line) character
NULL_PTR            EQU     0
ERROR               EQU     1                               ;return code indicating an error occurred
READ_FILE_ERROR     EQU     0                               ;ReadFile will return 0 if an error occurred

;---------------------
;variables
;---------------------

errMsgFileOpen      byte    "ERROR:  Unable to open input file", _CR, _LF

filename            byte    "machine.bin", NULL            ;file name must be null terminated

programBuffer       byte    MAX_RAM dup (0)                 ;max size of RAM 1K

returnCode          dword   0                               ;used to return program status back to OS

bytesWritten        dword   0
BytesRead           dword   0                               ;number of bytes read from file will be stored here
fileHandle          qword   0                               ;handle to file containing program
fileSize            dword   0                               ;size of file
hStdOut             qword   0                               ;handle to the standard output
hStdIn              qword   0                               ;handle to the standard input

Registers           byte    6 dup(0ffh)                        ;Array used to emulate 8 bit registers 
NumCharsWritten     dword   0                                   ;number of characters written to console
stdout              qword   0                                   ;handle to the standard output console
;*********************
;Comparison bytes
;*********************

ADDInstruction		equ		11h
SUBInstruction		equ		22h
XORInstruction		equ		44h
LOADInstruction		equ		05h
LOADRInstruction	equ		55h
STOREInstruction	equ		06h
STORRInstruction	equ		66h		
OUTInstruction		equ		0CCh
JNZInstruction		equ		0AAh
HALTInstruction		equ		0FFh

                    .CODE

Main                Proc

                    sub     rsp,40                          ;shadow memory and align stack
                                                            ;32 bytes for shadow memory
                                                            ; 8 bytes to align stack

                    ;*********************************
                    ; Get Handle to Standard output
                    ;*********************************
                    mov     ecx,STD_OUTPUT_HANDLE           ;pass handle to get in ecx
                    call    GetStdHandle                    ;call Windows API
                    mov     hStdOut,rax                     ;save returned handle

                    ;*********************************
                    ; Get Handle to Standard input
                    ;*********************************
                    mov     ecx,STD_INPUT_HANDLE            ;pass handle to get in ecx
                    call    GetStdHandle                    ;call Windows API
                    mov     hStdIn,rax                      ;save returned handle

                    ;*********************************
                    ; Open existing file for Reading
                    ;*********************************
                    mov     rcx,offset fileName             ;name of file to open
                    mov     rdx,GENERIC_READ                ;
                    mov     r8,FILE_SHARE_NONE              ;file sharing - NONE
                    mov     r9,NULL_PTR                     ;
                    mov     qword ptr [rsp+32],OPEN_EXISTING            ;file must exist
                    mov     qword ptr [rsp+40],FILE_ATTRIBUTE_NORMAL    ;file attribute - normal
                    mov     qword ptr [rsp+48],NULL_PTR                 ;
                    call    CreateFileA
                    cmp     eax,INVALID_HANDLE              ;was open successful?
                    je      OpenError                       ;No....Display error and Exit
                    mov     fileHandle,rax                  ;Yes...then save file handle

                    ;********************************************
                    ; Determine the size of the file (in bytes)
                    ;********************************************
                    mov     rcx,fileHandle                  ;handle of open file
                    mov     rdx,NULL_PTR                    ;
                    call    GetFileSize                     ;Windows API function - returns file size
                    mov     fileSize, eax

                    ;********************************************
                    ; Make sure the size of the file doesn't 
                    ; exceed our buffer size. If it does then exit
                    ;********************************************
                    cmp     fileSize,LENGTHOF programBuffer ;Is file size greater than our buffer?
                    jc      ReadFromFile                    ;no...then read the entire file into our buffer
                    mov     returnCode,ERROR                ;yes..set return code to error
                    jmp     CloseFile                       ;     and exit

                    ;****************************************
                    ; Read the entire file into emulator RAM
                    ;****************************************
ReadFromFile:
                    mov     rcx,fileHandle                  ;handle to the file to read
                    mov     rdx,offset programBuffer        ;where to put data read
                    mov     r8d,fileSize                    ;number of bytes to read
                    mov     r9,offset bytesRead             ;returns bytes read in this variable
                    xor     rax,rax                         ;last parameter is 0
                    mov     [rsp+32],rax                    ;parameters > 4 are passed on the stack
                    call    ReadFile                        ;read the entire file into programBuffer
                    cmp     eax,READ_FILE_ERROR             ;was read successful?
                    jne     RunProgram                      ;Yes..then execute the program
                    mov     returnCode,ERROR                ;no...set return code to error
                                                            ;     and close file and exit
                    ;*********************************
                    ; Close the file
                    ;*********************************
CloseFile:
                    mov     rcx,fileHandle                  ;pass in handle to the file to close
                    call    CloseHandle
                    jmp     Finish

OpenError:
                    ;Let user know there was an error opening the file
                    mov     rcx,hStdOut                     ;1st parameter - handle of where to send message
                    mov     rdx,OFFSET errMsgFileOpen       ;2nd parameter - message to display
                    mov     r8,LENGTHOF errMsgFileOpen      ;3rd parameter - number of characters to display
                    mov     r9,OFFSET bytesWritten          ;4th parameter - pointer where bytes written will be stored
                    xor     rax,rax                         ;last parameter is 0
                    mov     [rsp+32],rax                    ;parameters > 4 are passed on the stack
                    call    WriteConsoleA                   ;display the error message
                    mov     returnCode,ERROR                ;let caller know there was an error
                    jmp     finish                          ;exit program

RunProgram:
;********************
;Set Up the Buffer
;********************
				
					mov		r8,	 offset	Registers
					mov     rax, offset programBuffer		;Get the address of the programBuffer
					mov		r11, offset programBuffer		;Keeps the address of the beginning of the programBuffer
;********************************************************
;Compare the bytes to decide which which lable to jump to
;********************************************************

Comparison:
					xor		rcx, rcx							;Used for the index of The Registers array
					xor		rbx, rbx
					xor		rdx, rdx
					xor		r9, r9 

					mov     bl, ADDInstruction				;Move the value used to compare the opcode 				
					cmp		bl, [rax]						;Compare the opcode with the intructions if equal jump to the corresponding lable
					je		ADDLable
					mov     bl, SUBInstruction				;Move the value used to compare the opcode
					cmp		bl, [rax]						;Compare the opcode with the intructions if equal jump to the corresponding lable
					je		SUBLable
					mov     bl, XORInstruction				;Move the value used to compare the opcode
					cmp		bl, [rax]						;Compare the opcode with the intructions if equal jump to the corresponding lable
					je		XORLable
					mov     bl, LOADInstruction				;Move the value used to compare the opcode
					cmp		bl, [rax]						;Compare the opcode with the intructions if equal jump to the corresponding lable
					je		LOADLable
					mov     bl, LOADRInstruction			;Move the value used to compare the opcode
					cmp		bl, [rax]						;Compare the opcode with the intructions if equal jump to the corresponding lable
					je		LOADRLable
					mov     bl, STOREInstruction			;Move the value used to compare the opcode
					cmp		bl, [rax]						;Compare the opcode with the intructions if equal jump to the corresponding lable
					je		STORELable
					mov     bl, STORRInstruction			;Move the value used to compare the opcode
					cmp		bl, [rax]						;Compare the opcode with the intructions if equal jump to the corresponding lable
					je		STORRLable
					mov     bl, OUTInstruction			    ;Move the value used to compare the opcode
					cmp		bl, [rax]						;Compare the opcode with the intructions if equal jump to the corresponding lable
					je		OUTLable
					mov     bl, JNZInstruction			    ;Move the value used to compare the opcode
					cmp		bl, [rax]						;Compare the opcode with the intructions if equal jump to the corresponding lable
					je		JNZLable
					mov     bl, HALTInstruction			    ;Move the value used to compare the opcode
					cmp		bl, [rax]						;Compare the opcode with the intructions if equal jump to the corresponding lable
					je		Finish


					
ADDLable:;done			
					inc		rax							;Move to register 1
					mov		bl, [rax]					;Determine which register to use for register 1 
					inc		rax							;Move to register 2
					mov		cl, [rax]					;Determine which register to use for register 2
					mov		cl, [r8+rcx]				;add the value of register 2 with the value obtained from register 1
					add		[r8+rbx], cl				;Move the value stored in al into the specified emulated register 1
					inc		rax
					jmp		Comparison

					
SUBLable:;done		
					inc		rax							;Move to register 1
					mov		bl, [rax]					;Determine which register to use for register 1 
					inc		rax							;Move to register 2
					mov		cl, [rax]					;Determine which register to use for register 2
					mov		cl, [r8+rcx]				;add the value of register 2 with the value obtained from register 1
					sub		[r8+rbx], cl				;Move the value stored in al into the specified emulated register 1
					inc		rax
					jmp		Comparison

XORLable:;Done			
					inc		rax							;Move to register 1
					mov		bl, [rax]					;Determine which register to use for register 1 
					inc		rax							;Move to register 2
					mov		cl, [rax]					;Determine which register to use for register 2
					mov		cl, [r8+rcx]				;add the value of register 2 with the value obtained from register 1
					xor		[r8+rbx], cl				;Move the value stored in al into the specified emulated register 1
					inc		rax
					jmp		Comparison

LOADLable:;DOne
					inc		rax							;Increments from the op code into the register we have to use
					mov		bl, [rax]					;Move the number of the register into al
					inc		rax							;Move to the address that we need to use
					mov		cx, [rax]					;Move the address into a 16 bit register
					xchg	ch, cl						;Exhange the values in bh bl from big endian to little endian
					mov		dl, [r11 + rcx]			;Move to the correspoinding memory address and put it in the register
					mov		[r8+rbx], dl				;Move the value found a the address into the emulated register
					inc     rax
					inc		rax
					jmp		Comparison
LOADRLable:		
					inc		rax							;Increments from the op code into the register we have to use
					mov		bl, [rax]					;Move the number of the register into al
					inc		rax							;Move to the address that we need to use
					mov		cx, [rax]					;Move the address into a 16 bit register
					xchg	ch, cl						;Exhange the values in bh bl from big endian to little endian
					mov		r9, offset programBuffer	;Load the address of program buffer into r9
					add		r9, rcx						;Add the address of the program buffer and the address that we want
					add		dl, [r8 + rbx]				;MOve the value of the emulated register in to a register
					add		r9, rdx
					mov		rdx, [r9]					;Store the value of the combined registers in a new register
					mov		[r8+rbx], dl				;Store the value in the correct register
					inc     rax
					inc		rax
					
					jmp		Comparison
STORELable:		
					inc		rax							;Points to the address of the operand
					mov		bx, [rax]					;Puts the address of the instruction into bx
					xchg	bh, bl						;Change big Endian into little endian

					mov		dl, [r8]					;Put the Value of R0 into a register
					mov		[rax + rbx], dl				;Store the value of R0 into

					inc		rax
					inc		rax

					jmp		Comparison

STORRLable:	

					inc		rax							;Points to the address of the operand
					mov		cl, [rax]					;Determine the emulated register number we want
					inc		rax
					mov		bx, [rax]					;Puts the address of the instruction into bx
					
					xchg	bh, bl						;Change big Endian into little endian

					mov		r9, offset programBuffer	;Load the address of program buffer into r9
					add		r9, rbx 					;Add the address of the program buffer and the address that we want
					add		dl, [r8 + rcx]				;MOve the value of the emulated register in to a register
					add		r9, rdx						;Move to the correct Address of the password buffer

					mov		dl, [r8]					;mov the value within R0 to a register 

					mov		[r9], dl					;Store the value of R0 into

					inc		rax
					inc		rax

					jmp		Comparison
OUTLable:;TODO				
					;inc		rax
					;mov		bl, [rax]					   ;Determine which register to use for register 1
					;mov		bl, [
					;mov r12, offset NumCharsWritten              ;Number of characters written will be returned here
					;mov r13d, SIZEOF                        ;Number of bytes to write to console
					;mov rdx, offset mymsg                       ;Address of data to write to console
					;mov rcx,stdout                              ;Handle where to write
                    ;call WriteConsoleA
					;jmp		Comparison
JNZLable:;TODO					
					;inc		rax							;Move to register 1
					;mov		bl, [rdx]					;Determine which register to use for register 1
					;mov		al, [r9+r10]				;move the value of register and move the value to al
					;inc		rdx							;move to the next instruction
					;cmp		al, 0						;Compares the value of register 1 with zero
					;je		Comparison					;If the comparison is equal to zero jump to the comparison lable 



Finish:;done
                    ;Terminate Program
                    mov     ecx,returnCode                  ;parameter 1 contains the return code
                    call    ExitProcess                     ;Windows API - terminates the program

Main                endp

                    END

