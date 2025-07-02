[org 0x7C00]       ; Ponto onde o BIOS carrega o bootloader

start:
    xor ax, ax
    mov ds, ax
    mov es, ax

    mov bx, buffer      ; Endereço de destino da leitura

    ; Ler setor 1 (setor 2 para BIOS)
    mov ah, 0x02        ; Função: ler setor
    mov al, 1           ; 1 setor
    mov ch, 0           ; cilindro 0
    mov cl, 2           ; setor 2 (setor 1 real)
    mov dh, 0           ; cabeça 0
    mov dl, 0           ; drive 0 (disquete)
    int 0x13

    jc erro             ; se erro, pula pra erro

    mov si, buffer

print_loop:
    lodsb
    cmp al, 0
    je fim
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, 0x07
    int 0x10
    jmp print_loop

erro:
    mov si, msg_erro
.print_erro:
    lodsb
    cmp al, 0
    je fim
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, 0x0C
    int 0x10
    jmp .print_erro

fim:
    cli
    hlt

msg_erro db "Erro ao ler setor!", 0

buffer: times 256 db 0   ; buffer reduzido pra não estourar 512 bytes

; Preencher até 510 bytes e colocar a assinatura de boot
times 510-($-$$) db 0
dw 0xAA55
