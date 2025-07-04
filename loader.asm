[org 0x7C00]
[bits 16]

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov [boot_drive], dl

    ; Mensagem de carregamento
    mov si, msg_loading
    call print_string

    ; === Lê FAT do setor 2 ===
    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [boot_drive]
    mov bx, 0x7E00
    int 0x13
    jc disk_error

    ; === Leitura encadeada usando FAT ===
    mov si, 0x7E00         ; SI aponta para FAT
    mov bl, [si]           ; BL = setor inicial
    mov di, 0x8000         ; destino dos dados

.load_loop:
    ; Lê setor atual (BL) para [DI]
    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, bl
    mov dh, 0
    mov dl, [boot_drive]
    mov bx, di
    int 0x13
    jc disk_error

    add di, 512            ; avança no buffer
    inc si                 ; próxima entrada na FAT
    mov bl, [si]           ; próximo setor

    cmp bl, 0xFF           ; fim da cadeia?
    jne .load_loop

    ; Mostra o conteúdo carregado
    mov si, 0x8000
    call print_string
    jmp $

; --- Funções ---
print_string:
    pusha
.loop:
    lodsb
    cmp al, 0
    je .done
    mov ah, 0x0E
    int 0x10
    jmp .loop
.done:
    popa
    ret

disk_error:
    mov si, msg_error
    call print_string
    jmp $

; --- Dados ---
boot_drive db 0
msg_loading db "Carregando via FAT...", 0x0D, 0x0A, 0
msg_error db "Erro de disco!", 0

times 510-($-$$) db 0
dw 0xAA55
