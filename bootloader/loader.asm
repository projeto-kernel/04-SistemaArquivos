[org 0x7C00]

start:
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; ----------------------------
    ; 1. Ler a TABELA (setor 2)
    ; ----------------------------
    mov ah, 0x02
    mov al, 1          ; 1 setor
    mov ch, 0          ; cilindro 0
    mov cl, 2          ; setor 2 (índice BIOS)
    mov dh, 0          ; cabeça 0
    mov dl, 0x80       ; drive 0x80 = HD
    mov bx, tabela
    int 0x13
    jc erro

    ; ----------------------------
    ; 2. Ler os arquivos da tabela
    ; ----------------------------
    mov cx, 512 / 9    ; máximo de entradas = 56
    mov si, tabela

proximo_arquivo:
    cmp byte [si], 0   ; se o nome estiver vazio, fim
    je fim

    ; pula linha antes de imprimir (só para múltiplos arquivos)
    mov al, 0x0A
    call print_char

    ; setor onde está o conteúdo do arquivo
    mov al, [si + 8]
    mov ah, 0
    mov cl, al
    mov ch, 0
    mov dh, 0
    mov dl, 0x80
    mov ah, 0x02
    mov al, 1
    mov bx, buffer
    int 0x13
    jc erro

    ; ----------------------------
    ; 3. Imprimir conteúdo do buffer
    ; ----------------------------
    mov si, buffer
print_loop:
    lodsb
    cmp al, 0
    je continuar
    call print_char
    jmp print_loop

continuar:
    add si, 9          ; próxima entrada da tabela
    dec cx
    jnz proximo_arquivo

    jmp fim

erro:
    mov si, msg_erro
.print_erro:
    lodsb
    cmp al, 0
    je fim
    call print_char
    jmp .print_erro

fim:
    cli
    hlt

; ----------------------------
; Subrotina de imprimir caractere
; ----------------------------
print_char:
    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x07
    int 0x10
    ret

; ----------------------------
; Dados
; ----------------------------
msg_erro db "Erro ao carregar", 0
tabela: times 72 db 0      ; suficiente para 8 entradas de 9 bytes = 72 bytes
buffer: times 128 db 0     ; 128 bytes para o conteúdo do arquivo

; ----------------------------
; Boot Signature (obrigatória!)
; ----------------------------

%assign restante 510 - ($ - $$)
%if restante > 0
    times restante db 0
%endif
dw 0xAA55
