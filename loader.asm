[org 0x7C00]

start:
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; Ler tabela (setor 2)
    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, 0x80
    mov bx, tabela
    mov es, ax         ; es = 0
    int 0x13
    jc erro

    mov cx, 512 / 10   ; se cada entrada tem 10 bytes: nome(8) + setor(1) + tamanho_setores(1)
    mov si, tabela

proximo_arquivo:
    cmp byte [si], 0
    je fim

    ; pula linha
    mov al, 0x0A
    call print_char

    mov bl, [si + 8]       ; setor inicial
    mov bh, 0
    mov dl, 0x80
    mov ch, 0
    mov dh, 0

    mov cl, 1              ; número de setores lidos no momento
    mov al, [si + 9]       ; número de setores do arquivo
    or al, al
    jz proximo_setor       ; se 0, pula leitura

    mov si, buffer         ; buffer offset
    mov es, ax             ; segmento 0

leitura_setor:
    mov ah, 0x02
    mov al, 1              ; 1 setor por vez
    mov bx, si
    int 0x13
    jc erro

    ; imprimir setor lido
    mov di, si
    mov cx, 512
print_buffer:
    mov al, [es:di]
    cmp al, 0
    je fim_impressao
    call print_char
    inc di
    loop print_buffer

fim_impressao:
    inc bl                 ; próximo setor
    inc cl
    cmp cl, [si + 9]
    jle leitura_setor

proximo_setor:
    add si, 10             ; próxima entrada da tabela
    loop proximo_arquivo

fim:
    cli
    hlt

erro:
    mov si, msg_erro
.print_erro:
    lodsb
    cmp al, 0
    je fim
    call print_char
    jmp .print_erro

print_char:
    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x07
    int 0x10
    ret

msg_erro db "Erro ao carregar", 0
tabela equ 0x0500      ; endereço na RAM onde vamos guardar a tabela
buffer  equ 0x0600     ; endereço na RAM onde vamos guardar o conteúdo dos arquivos

%assign restante 510 - ($ - $$)
%if restante > 0
    times restante db 0
%endif
dw 0xAA55
