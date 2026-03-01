.286
.model tiny
.code
org 100h

; === Constants for frame ===
TL_CHAR     equ 0DAh
TR_CHAR     equ 0BFh
BL_CHAR     equ 0C0h
BR_CHAR     equ 0D9h
HORZ_CHAR   equ 0C4h
VERT_CHAR   equ 0B3h
ATTR_COLOR  equ 3Fh 

start:
    jmp Main

; === Resident data ===
Old_Int09   dd ?
RegNames    db 'AXBXCXDXSIDIBPSPDSESSSCS'
RegVals     dw 12 dup(0)

; =============================================================
; New INT 09h Handler
; Entry: Hardware Interrupt 09h
; Exit:  Jumps to original BIOS INT 09h handler
; Expr:  Captures CPU state and draws frame if keys are pressed
; Destr: NONE (all registers saved and restored)
; =============================================================
NewInt09 proc
    cld
    push ax bx cx dx si di ds es bp

    mov cs:[RegVals], ax
    mov cs:[RegVals+2], bx
    mov cs:[RegVals+4], cx
    mov cs:[RegVals+6], dx
    mov cs:[RegVals+8], si
    mov cs:[RegVals+10], di
    mov cs:[RegVals+12], bp
    mov cs:[RegVals+16], ds
    mov cs:[RegVals+18], es
    mov cs:[RegVals+20], ss
    
    mov bp, sp
    
    mov ax, [bp+20]           ; (9 reg + ip)
    mov cs:[RegVals+22], ax
    
    mov ax, sp
    add ax, 24                ; (9 reg + ip + cs + flags)             
    mov cs:[RegVals+14], ax

    mov ax, cs:[RegVals]      ; restore ax

    ; === Shift handler ===
    in al, 60h
    cmp al, 2ah
    je ShiftPressed
    cmp al, 36h
    je ShiftPressed
    jmp SkipDrawing

ShiftPressed:
    mov ax, 0B800h
    mov es, ax
    call DrawFrame          
    call PrintRegisters

SkipDrawing:
    pop bp es ds di si dx cx bx ax
    jmp dword ptr cs:[Old_Int09]
NewInt09 endp

; =============================================================
; Draws a vertical narrow frame (12x14)
; Entry: NONE
; Exit:  Frame rendered in video memory
; Expr:  ES = 0B800h, AH = ATTR_COLOR
; Destr: NONE (all registers are stored)
; =============================================================
DrawFrame proc
    push ax bx cx dx di es
    
    mov di, (5 * 80 + 34) * 2     ; row 5, col 34
    mov ah, ATTR_COLOR
    
    ; === Top ===
    mov al, TL_CHAR
    stosw
    mov cx, 10
    mov al, HORZ_CHAR
    rep stosw
    mov al, TR_CHAR
    stosw
    
    ; === Sides ===
    mov bx, 12
draw_mid:
    add di, (80 - 12) * 2
    mov al, VERT_CHAR
    stosw
    mov cx, 10
    mov al, ' '                   ; сlear inner area
    rep stosw
    mov al, VERT_CHAR
    stosw
    dec bx
    jnz draw_mid
    
    ; === Bottom ===
    add di, (80 - 12) * 2
    mov al, BL_CHAR
    stosw
    mov cx, 10
    mov al, HORZ_CHAR
    rep stosw
    mov al, BR_CHAR
    stosw
    
    pop es di dx cx bx ax
    ret
DrawFrame endp

; =============================================================
; Prints registers from string in a vertical column and calls HEX word printing function
; Entry: RegVals contains captured CPU state
; Exit:  Register names and values printed inside the frame
; Exp:   ES = 0B800h
; Destr: NONE (all registers are stored)
; =============================================================
PrintRegisters proc
    push ax bx cx dx si di es ds
    
    mov ax, cs
    mov ds, ax
    
    mov si, offset RegNames
    mov bx, offset RegVals
    
    mov di, (6 * 80 + 36) * 2 ; row 6, col 36
    mov cx, 12
    mov ah, ATTR_COLOR

print_loop:
    push di

    lodsb
    stosw
    lodsb
    stosw
    
    mov al, ':'
    stosw
    mov al, ' '
    stosw
    
    mov dx, [bx]
    add bx, 2
    call PrintHexWord
    
    pop di
    add di, 160
    loop print_loop
    
    pop ds es di si dx cx bx ax
    ret
PrintRegisters endp

; =============================================================
; Converts a 2-byte word to HEX string and prints it to screan
; Entry: DX = Value to convert, AH = Attribute, ES:DI = Output
; Exit:  NONE
; Exp:   ES = 0B800h
; Destr: NONE (all registers are stored)
; =============================================================
PrintHexWord proc
    push cx dx ax
    mov cx, 4
hex_loop:
    mov al, dl
    shr al, 4
    add al, '0'
    cmp al, '9'
    jbe is_digit
    add al, 7
is_digit:
    stosw
    shl dx, 4
    loop hex_loop
    pop ax dx cx
    ret
PrintHexWord endp

; ========== MAIN ==========
Main:
    push 0
    pop es
    mov bx, 4*09h
    
    mov ax, es:[bx]
    mov word ptr cs:[Old_Int09], ax
    mov ax, word ptr es:[bx+2]
    mov word ptr cs:[Old_Int09+2], ax

    cli
    mov word ptr es:[bx], offset NewInt09
    mov word ptr es:[bx+2], cs
    sti

    mov dx, offset EOP
    shr dx, 4
    inc dx
    mov ax, 3100h
    int 21h

EOP:
end start