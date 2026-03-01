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
is_active   db 0                        
old_int09   dd ?
old_int08   dd ?
reg_names   db 'AXBXCXDXSIDIBPSPDSESSSCS'
reg_vals    dw 12 dup(0)

; === Buffers ===
; 14 rows x 12 col
save_buffer dw 168 dup(0)
draw_buffer dw 168 dup(0)

; =============================================================
; New INT 08h Handler
; Entry: Hardware Interrupt 08h (System Timer)
; Exit:  Jumps to original BIOS INT 08h handler
; Expr:  Compares VRAM with draw_buffer to detect and store background changes
; Destr: NONE (all registers saved and restored)
; =============================================================
NewInt08 proc
    pushf
    call dword ptr cs:[old_int08]

    cmp cs:[is_active], 1
    jne SkipTimer

    push ax bx cx dx si di ds es bp

    mov ax, cs
    mov ds, ax
    mov ax, 0B800h
    mov es, ax

    mov si, offset draw_buffer
    mov di, (5 * 80 + 34) * 2           ; row 5, col 34
    
    mov bx, 14                          ; 14 rows
check_row:
    mov cx, 12                          ; 12 columns
check_col:
    mov ax, es:[di]
    cmp ax, ds:[si]
    je match
    
    ; === MISMATCH DETECTED ===
    push bp
    mov bp, si
    sub bp, offset draw_buffer 
    mov ds:[offset save_buffer + bp], ax 
    pop bp
    
    mov ax, ds:[si]
    mov es:[di], ax

match:
    add si, 2                           ; Next char in buffer
    add di, 2                           ; Next char in VRAM
    loop check_col
    
    add di, (80 - 12) * 2               ; Move to next row
    dec bx
    jnz check_row

    pop bp es ds di si dx cx bx ax
SkipTimer:
    iret
NewInt08 endp

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

    ; Capture registers
    mov cs:[reg_vals], ax
    mov cs:[reg_vals+2], bx
    mov cs:[reg_vals+4], cx
    mov cs:[reg_vals+6], dx
    mov cs:[reg_vals+8], si
    mov cs:[reg_vals+10], di
    mov cs:[reg_vals+12], bp
    mov cs:[reg_vals+16], ds
    mov cs:[reg_vals+18], es
    mov cs:[reg_vals+20], ss
    
    mov bp, sp
    mov ax, [bp+20]           
    mov cs:[reg_vals+22], ax
    
    mov ax, sp
    add ax, 24                           
    mov cs:[reg_vals+14], ax
    mov ax, cs:[reg_vals]      

    in al, 60h
    cmp al, 36h
    je ShiftR_Pressed
    cmp al, 2ah
    je ShiftL_Pressed
    jmp SkipDrawing

ShiftR_Pressed:
    cmp cs:[is_active], 1
    jne SkipDrawing
    call RestoreScreen
    mov cs:[is_active], 0
    jmp SkipDrawing

ShiftL_Pressed:
    cmp cs:[is_active], 1
    je UpdateFrame
    
    call SaveScreen
    mov cs:[is_active], 1
    
UpdateFrame:
    call DrawFrame
    call PrintRegisters
    call CopyBufferToScreen
    
SkipDrawing:
    pop bp es ds di si dx cx bx ax
    jmp dword ptr cs:[old_int09]
NewInt09 endp

; =============================================================
; Save Screen to Buffer
; Entry: NONE
; Exit:  save_buffer updated with current VRAM content
; Expr:  Captures 14x12 area where frame will be drawn
; Destr: NONE
; =============================================================
SaveScreen proc
    push ax bx cx si di ds es
    mov ax, 0B800h
    mov ds, ax
    mov ax, cs
    mov es, ax
    mov si, (5 * 80 + 34) * 2
    mov di, offset save_buffer
    mov bx, 14
save_row:
    mov cx, 12
    rep movsw
    add si, (80 - 12) * 2
    dec bx
    jnz save_row
    pop es ds di si cx bx ax
    ret
SaveScreen endp

; =============================================================
; Restore Screen from Buffer
; Entry: NONE
; Exit:  VRAM restored from save_buffer
; Expr:  Used to hide frame and show original background
; Destr: NONE
; =============================================================
RestoreScreen proc
    push ax bx cx si di ds es
    mov ax, cs
    mov ds, ax
    mov ax, 0B800h
    mov es, ax
    mov si, offset save_buffer
    mov di, (5 * 80 + 34) * 2
    mov bx, 14
restore_row:
    mov cx, 12
    rep movsw
    add di, (80 - 12) * 2
    dec bx
    jnz restore_row
    pop es ds di si cx bx ax
    ret
RestoreScreen endp

; =============================================================
; Copy Draw Buffer to VRAM
; Entry: NONE
; Exit:  draw_buffer contents copied to video memory
; Expr:  Synchronizes logical draw buffer with physical VRAM
; Destr: NONE
; =============================================================
CopyBufferToScreen proc
    push ax bx cx si di ds es
    mov ax, cs
    mov ds, ax
    mov ax, 0B800h
    mov es, ax
    mov si, offset draw_buffer
    mov di, (5 * 80 + 34) * 2
    mov bx, 14
copy_row:
    mov cx, 12
    rep movsw
    add di, (80 - 12) * 2
    dec bx
    jnz copy_row
    pop es ds di si cx bx ax
    ret
CopyBufferToScreen endp

; =============================================================
; Draws frame directly to draw_buffer
; Entry: NONE
; Exit:  Static frame structure in draw_buffer
; Expr:  ES:DI points to draw_buffer. AH = attribute.
; Destr: NONE
; =============================================================
DrawFrame proc
    push ax bx cx di es
    mov ax, cs
    mov es, ax
    mov di, offset draw_buffer
    mov ah, ATTR_COLOR
    
    ; Top row
    mov al, TL_CHAR
    stosw
    mov cx, 10
    mov al, HORZ_CHAR
    rep stosw
    mov al, TR_CHAR
    stosw
    
    ; Mid rows
    mov bx, 12
draw_mid:
    mov al, VERT_CHAR
    stosw
    mov cx, 10
    mov al, ' '                   
    rep stosw
    mov al, VERT_CHAR
    stosw
    dec bx
    jnz draw_mid
    
    ; Bottom row
    mov al, BL_CHAR
    stosw
    mov cx, 10
    mov al, HORZ_CHAR
    rep stosw
    mov al, BR_CHAR
    stosw
    
    pop es di cx bx ax
    ret
DrawFrame endp

; =============================================================
; Prints registers to draw_buffer
; Entry: ds:si = reg_names, ds:bx = reg_vals
; Exit:  Formatted values inside draw_buffer
; Expr:  Iterates 12 times and uses PrintHexWord
; Destr: NONE
; =============================================================
PrintRegisters proc
    push ax bx cx dx si di es ds
    mov ax, cs
    mov ds, ax
    mov es, ax
    
    mov si, offset reg_names
    mov bx, offset reg_vals
    mov di, offset draw_buffer + 28   ; offset: 1 row (24 bytes) + 2 chars (4 bytes)
    mov cx, 12
    mov ah, ATTR_COLOR

print_loop:
    push di
    lodsb                             ; load char 1
    stosw
    lodsb                             ; load char 2
    stosw
    mov al, ' '
    stosw
    
    mov dx, [bx]                      ; load reg value
    add bx, 2
    call PrintHexWord
    
    pop di
    add di, 24                        ; next row 12*2 bytes
    loop print_loop
    
    pop ds es di si dx cx bx ax
    ret
PrintRegisters endp

; =============================================================
; Converts a 16-bit word to HEX string and prints it
; Entry: DX = Value to convert, AH = Attribute, ES:DI = Output
; Exit:  DI advanced by 8 bytes
; Expr:  Uses SHL to extract nibbles without ROL
; Destr: NONE
; =============================================================
PrintHexWord proc
    push cx dx ax
    mov cx, 4
hex_loop:
    mov al, dh
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

; =============================================================
; Installation: TSR setup
; Entry: NONE
; Exit:  Program stays resident in memory
; Expr:  Hooks INT 09h and INT 08h vectors
; Destr: AX, BX, DX, ES
; =============================================================
Main:
    push 0
    pop es
    
    ; Hook INT 09h
    mov bx, 4*09h
    mov ax, es:[bx]
    mov word ptr cs:[old_int09], ax
    mov ax, word ptr es:[bx+2]
    mov word ptr cs:[old_int09+2], ax

    cli
    mov word ptr es:[bx], offset NewInt09
    mov word ptr es:[bx+2], cs
    sti

    ; Hook INT 08h
    mov bx, 4*08h
    mov ax, es:[bx]
    mov word ptr cs:[old_int08], ax
    mov ax, word ptr es:[bx+2]
    mov word ptr cs:[old_int08+2], ax
    
    cli
    mov word ptr es:[bx], offset NewInt08
    mov word ptr es:[bx+2], cs
    sti

    mov dx, offset EOP
    shr dx, 4
    inc dx
    mov ax, 3100h
    int 21h

EOP:
end start